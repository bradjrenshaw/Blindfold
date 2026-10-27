-- speech.lua — screen-reader output for Blindfold.
--
-- Speech goes through Loadstar (https://github.com/bradjrenshaw/loadstar),
-- the shared native library behind all of these mods, loaded via LuaJIT FFI.
-- Its speech layer (the lv_* surface, docs/speech-spec.md there) owns
-- everything that used to live here: one tree of voices (screen readers
-- through Prism on Windows, SAPI 5, AVSpeech on macOS, clipboard), a worker
-- thread that talks to them so the game thread never blocks on a backend,
-- and a queue with explicit interrupt semantics. A log fallback always runs
-- too, so the mod is testable without speech (every announcement lands in
-- blindfold.log).
--
-- Voice ids are uint64. Lua numbers cannot hold them exactly, so outside
-- this file a voice is a 16-digit hex string ("auto" = the root auto, 0).

local ffi = require("ffi")
local bit = require("bit")

local M = { loaded = false }

local is_win = ffi.os == "Windows"
local is_osx = ffi.os == "OSX"

if is_win then
    ffi.cdef([[
        int   MultiByteToWideChar(unsigned int cp, unsigned long flags,
                                  const char* mb, int cbmb, wchar_t* wc, int cchwc);
        void* LoadLibraryW(const wchar_t* path);
    ]])
end

-- From loadstar's include/loadstar.h (speech section). Enums are uint32_t.
ffi.cdef([[
    typedef struct LsSpeech_ LsSpeech_;
    typedef struct LsSpeechConfig {
        const char* prism_path;
        uint32_t    load_prism;
        uint32_t    utterance_history;
    } LsSpeechConfig;
    typedef struct LsSpeechProfile {
        uint64_t voice;
        float    rate;
        float    pitch;
        float    volume;
        uint32_t flags;
    } LsSpeechProfile;

    uint32_t ls_abi_version(void);
    uint32_t lv_create(const LsSpeechConfig* cfg, LsSpeech_** out_ctx);
    void     lv_destroy(LsSpeech_* ctx);
    uint32_t lv_prism_version(LsSpeech_* ctx, char* buf, size_t cap, size_t* written);
    uint32_t lv_tree_refresh(LsSpeech_* ctx, bool* changed);
    uint32_t lv_tree_generation(LsSpeech_* ctx, uint64_t* generation);
    uint32_t lv_category_count(LsSpeech_* ctx, size_t* count);
    uint32_t lv_category_at(LsSpeech_* ctx, size_t index, uint64_t* id);
    uint32_t lv_category_key(LsSpeech_* ctx, uint64_t id, char* buf, size_t cap, size_t* written);
    uint32_t lv_category_name(LsSpeech_* ctx, uint64_t id, char* buf, size_t cap, size_t* written);
    uint32_t lv_voice_count(LsSpeech_* ctx, uint64_t category, size_t* count);
    uint32_t lv_voice_at(LsSpeech_* ctx, uint64_t category, size_t index, uint64_t* id);
    uint32_t lv_voice_name(LsSpeech_* ctx, uint64_t id, char* buf, size_t cap, size_t* written);
    uint32_t lv_voice_language(LsSpeech_* ctx, uint64_t id, char* buf, size_t cap, size_t* written);
    uint32_t lv_voice_features(LsSpeech_* ctx, uint64_t id, uint64_t* bits);
    uint32_t lv_resolve(LsSpeech_* ctx, const LsSpeechProfile* profile, uint64_t required,
                        uint64_t* voice, bool* fell_back, uint64_t* missing);
    uint32_t lv_output(LsSpeech_* ctx, uint32_t queue, const LsSpeechProfile* profile,
                       const char* text, uint32_t flags, uint64_t* utterance);
    uint32_t lv_stop_all(LsSpeech_* ctx);
]])

local OK = 0
local QUEUE = 0           -- the default queue: sequential, no gap
local INTERRUPT = 1       -- SpeakFlags::Interrupt
-- SpeechFeature bits (all in the low 32, so LuaJIT's 32-bit bit ops suffice).
local F_SPEAK, F_RATE, F_PITCH, F_VOLUME = 0x1, 0x40, 0x80, 0x100

-- Rotate at boot: the log grows with every utterance and had reached
-- multiple megabytes across sessions, making each synchronous append (and
-- the antivirus scan behind it) pricier — implicated in main-thread stalls.
-- The live file holds only the current session; the previous one is .old.
pcall(function()
    local info = love.filesystem.getInfo and love.filesystem.getInfo("blindfold.log")
    if info and (info.size or 0) > 0 then
        local data = love.filesystem.read("blindfold.log")
        if data then love.filesystem.write("blindfold.log.old", data) end
        love.filesystem.remove("blindfold.log")
    end
end)

-- Log writes go through a writer THREAD: the per-utterance append was
-- synchronous disk I/O on the main thread, and the forensic timers caught it
-- stalling ("SLOW log append: 80ms") — the game and the screen reader hitch
-- together when that happens. The main thread only pushes lines onto a
-- channel; the thread does the appends. Falls back to direct appends when
-- love.thread is unavailable.
local LOG_THREAD = [[
require("love.filesystem")
local channel = love.thread.getChannel("blindfold_log")
while true do
    local line = channel:demand()
    if line == false then break end
    pcall(love.filesystem.append, "blindfold.log", line)
end
]]
local _log_channel
pcall(function()
    if love.thread and love.thread.newThread then
        local t = love.thread.newThread(LOG_THREAD)
        t:start()
        _log_channel = love.thread.getChannel("blindfold_log")
    end
end)

local function log_line(text) return os.date("%H:%M:%S ") .. text .. "\n" end

-- Synchronous append, for the rare lines that MUST be on disk before the
-- next native call.
local function log_sync(text)
    pcall(function() love.filesystem.append("blindfold.log", log_line(text)) end)
end

local function log(text)
    -- Lands at %APPDATA%/Balatro/blindfold.log (macOS: ~/Library/Application Support/Balatro)
    if _log_channel then
        local ok = pcall(function() _log_channel:push(log_line(text)) end)
        if ok then return end
    end
    log_sync(text)
end
M.log = log
M.log_sync = log_sync

-- UTF-8 Lua string -> null-terminated UTF-16LE buffer (for the wide Win32 API).
local to_wide
if is_win then
    local CP_UTF8 = 65001
    to_wide = function(s)
        local n = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
        if n <= 0 then return nil end
        local buf = ffi.new("wchar_t[?]", n)
        ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, n)
        return buf
    end
end

-- uint64 voice id <-> 16-digit hex string. 0 (the root auto) is "auto".
local TWO32 = 4294967296
local function id_to_hex(v)
    if v == 0 then return "auto" end
    local hi = tonumber(v / TWO32)
    local lo = tonumber(v % TWO32)
    return bit.tohex(hi, 8) .. bit.tohex(lo, 8)
end
local function hex_to_id(s)
    if type(s) ~= "string" or s == "auto" or not s:match("^%x+$") or #s > 16 then
        return ffi.new("uint64_t", 0)
    end
    s = ("0"):rep(16 - #s) .. s
    local hi, lo = tonumber(s:sub(1, 8), 16), tonumber(s:sub(9), 16)
    return ffi.new("uint64_t", hi) * TWO32 + lo
end
M.id_to_hex, M.hex_to_id = id_to_hex, hex_to_id

-- The two-call string-out pattern: a null buffer answers BufferTooSmall with
-- the capacity needed (terminator included), then a real buffer is filled.
local BUFFER_TOO_SMALL = 3
local size_out = ffi.new("size_t[1]")
local function string_out(fn, id)
    if M.lv[fn](M.ctx, id, nil, 0, size_out) ~= BUFFER_TOO_SMALL then return "" end
    local cap = tonumber(size_out[0])
    if cap <= 1 then return "" end
    local buf = ffi.new("char[?]", cap)
    if M.lv[fn](M.ctx, id, buf, cap, size_out) ~= OK then return "" end
    return ffi.string(buf, tonumber(size_out[0]))
end

-- The profile every utterance speaks through: the user's voice choice plus
-- rate/pitch/volume (0..1, 0.5 = the voice's default for rate and pitch).
-- Leaves without a feature ignore that field.
local profile = ffi.new("LsSpeechProfile")
profile.voice, profile.rate, profile.pitch, profile.volume = 0, 0.5, 0.5, 1.0

-- Load Loadstar from the mod's lib/ folder and open a speech context. Cheap
-- and silent: the library probes its backends on its own worker, and text
-- spoken before that finishes is queued until it has.
function M.init(mod_dir)
    local lib_dir = mod_dir .. "/lib"
    local ok, err = pcall(function()
        if is_win then
            local dir = lib_dir:gsub("/", "\\")
            -- ffi.load routes through the ANSI LoadLibraryA, which garbles
            -- non-ASCII install paths (C:\Users\Usuário\... -> "module not
            -- found"). Load the DLL ourselves through the wide API; ffi.load by
            -- bare name then binds to the ALREADY-LOADED module (LoadLibrary
            -- resolves loaded modules by name before searching disk).
            local wide = to_wide(dir .. "\\loadstar.dll")
            assert(wide and ffi.C.LoadLibraryW(wide) ~= nil,
                "LoadLibraryW failed for " .. dir .. "\\loadstar.dll")
            M.lv = ffi.load("loadstar")
        elseif is_osx then
            M.lv = ffi.load(lib_dir .. "/libloadstar.dylib")
        else
            error("Unsupported operating system: " .. tostring(ffi.os))
        end

        -- Prism (Windows screen readers) ships beside it. Loadstar takes the
        -- path as UTF-8 and loads it through the wide API itself.
        local cfg = ffi.new("LsSpeechConfig")
        local prism = is_win and (lib_dir .. "/prism.dll"):gsub("/", "\\") or nil
        cfg.prism_path = prism
        cfg.load_prism = prism and 1 or 0
        M._cfg_keepalive = { cfg, prism }   -- the C string points into `prism`
        local out = ffi.new("LsSpeech_*[1]")
        local st = M.lv.lv_create(cfg, out)
        assert(st == OK and out[0] ~= nil, "lv_create failed (status " .. tostring(st) .. ")")
        M.ctx = out[0]
        M.loaded = true
    end)
    if M.loaded then
        local prism = ""
        pcall(function()
            local buf = ffi.new("char[512]")
            if M.lv.lv_prism_version(M.ctx, buf, 512, size_out) == OK then
                prism = ffi.string(buf, math.min(tonumber(size_out[0]), 511))
            end
        end)
        log("Loadstar loaded (ABI " .. tostring(M.lv.ls_abi_version()) .. ")" ..
            (prism ~= "" and (", Prism " .. prism) or ", no Prism") .. ".")
    else
        log("Loadstar NOT loaded (" .. tostring(err) .. "). Expected " ..
            (is_win and "loadstar.dll" or "libloadstar.dylib") .. " in " .. lib_dir ..
            " . Running with log output only.")
    end
    return M.loaded
end

-- Adopt the user's settings: { voice = hex|"auto", rate, pitch, volume (0..1) }.
-- Missing fields keep their current value.
function M.set_profile(cfg)
    if type(cfg) ~= "table" then return end
    if cfg.voice ~= nil then profile.voice = hex_to_id(cfg.voice) end
    local function unit(v) return math.max(0, math.min(1, v)) end
    if type(cfg.rate) == "number" then profile.rate = unit(cfg.rate) end
    if type(cfg.pitch) == "number" then profile.pitch = unit(cfg.pitch) end
    if type(cfg.volume) == "number" then profile.volume = unit(cfg.volume) end
end

-- Ask the library to re-probe (a screen reader started after boot). The
-- result lands asynchronously; the Voice screen calls this as it opens.
function M.refresh()
    if not M.loaded then return end
    local changed = ffi.new("bool[1]")
    M.lv.lv_tree_refresh(M.ctx, changed)
end

-- Every voice in the tree, in the library's category order:
-- { {id=hex, name=, language=, category=key, category_name=}, ... }.
-- Empty until the first probe has published.
function M.voices()
    if not M.loaded then return {} end
    local list = {}
    pcall(function()
        local n, cid, vid = ffi.new("size_t[1]"), ffi.new("uint64_t[1]"), ffi.new("uint64_t[1]")
        if M.lv.lv_category_count(M.ctx, n) ~= OK then return end
        for ci = 0, tonumber(n[0]) - 1 do
            if M.lv.lv_category_at(M.ctx, ci, cid) == OK then
                local cat = cid[0]
                local key = string_out("lv_category_key", cat)
                local cat_name = string_out("lv_category_name", cat)
                local vn = ffi.new("size_t[1]")
                if M.lv.lv_voice_count(M.ctx, cat, vn) == OK then
                    for vi = 0, tonumber(vn[0]) - 1 do
                        if M.lv.lv_voice_at(M.ctx, cat, vi, vid) == OK then
                            local v = vid[0]
                            list[#list + 1] = {
                                id = id_to_hex(v),
                                name = string_out("lv_voice_name", v),
                                language = string_out("lv_voice_language", v),
                                category = key,
                                category_name = cat_name,
                            }
                        end
                    end
                end
            end
        end
    end)
    return list
end

-- Display name for a voice id (hex), absent ones included; "" if unknown.
function M.voice_name(hex)
    if not M.loaded then return "" end
    local ok, name = pcall(string_out, "lv_voice_name", hex_to_id(hex))
    return ok and name or ""
end

-- The voice that speaks right now for the current profile (after fallback),
-- as { id=hex, name=, fell_back=bool, rate=, pitch=, volume= (adjustable?) },
-- or nil when nothing can speak.
function M.resolved()
    if not M.loaded then return nil end
    local voice, fell, missing = ffi.new("uint64_t[1]"), ffi.new("bool[1]"), ffi.new("uint64_t[1]")
    if M.lv.lv_resolve(M.ctx, profile, F_SPEAK, voice, fell, missing) ~= OK or voice[0] == 0 then
        return nil
    end
    local bits = ffi.new("uint64_t[1]")
    M.lv.lv_voice_features(M.ctx, voice[0], bits)
    local f = tonumber(bits[0] % TWO32)
    return {
        id = id_to_hex(voice[0]),
        name = string_out("lv_voice_name", voice[0]),
        fell_back = fell[0],
        rate = bit.band(f, F_RATE) ~= 0,
        pitch = bit.band(f, F_PITCH) ~= 0,
        volume = bit.band(f, F_VOLUME) ~= 0,
    }
end

-- Game-thread cost forensics: an lv_* call only resolves and enqueues
-- (microseconds); anything past 30ms would mean the library regressed.
local function timer_now()
    local ok, t = pcall(function() return love.timer.getTime() end)
    return ok and t or nil
end
local function log_slow_call(t0, what, detail)
    if not t0 then return end
    local t1 = timer_now()
    if t1 and (t1 - t0) > 0.03 then
        log(string.format("SLOW loadstar %s: %dms%s", what,
            math.floor((t1 - t0) * 1000 + 0.5), detail or ""))
    end
end

-- Speak text (speech + braille where the voice has both). interrupt defaults
-- to false to honor the SayTheSpire2 preference of never cutting off
-- in-progress speech; pass true to cut the queue and speak this instead.
local utterance = ffi.new("uint64_t[1]")
function M.say(text, interrupt)
    if type(text) ~= "string" or text == "" then return end
    log(text)
    -- Dev server tap (GET /speech): what was spoken, for a driver that can't
    -- hear it. Set only while the dev server runs.
    if M.observer then pcall(M.observer, text) end
    if not M.loaded then return end
    local t0 = timer_now()
    local ok, st = pcall(M.lv.lv_output, M.ctx, QUEUE, profile, text,
        interrupt == true and INTERRUPT or 0, utterance)
    if not ok or st ~= OK then
        log("loadstar output failed (" .. tostring(ok and st or st) .. ")")
    end
    log_slow_call(t0, "output", " (" .. #text .. " chars)")
end

-- Cut what is speaking and drop everything queued.
function M.silence()
    if not M.loaded then return end
    local t0 = timer_now()
    pcall(M.lv.lv_stop_all, M.ctx)
    log_slow_call(t0, "stop")
end

return M
