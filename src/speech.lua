-- speech.lua — screen-reader output for Blindfold.
--
-- Primary backend is Prism (https://github.com/ethindp/prism, MPL-2.0): one
-- native library abstracting over screen readers and TTS engines (NVDA, JAWS,
-- SAPI, OneCore, ...), loaded via LuaJIT FFI. Prism talks to the screen
-- readers directly — no client DLLs — and takes plain UTF-8. A log fallback
-- always runs too, so the mod is testable BEFORE prism.dll is dropped in
-- (focus changes show up in %APPDATA%/Balatro/blindfold.log).
--
-- Binding ported from wotr-access's PrismHandler/PrismNative (C#): acquire
-- the best available backend once at init; prefer prism_backend_output (which
-- drives braille too where supported) and fall back to prism_backend_speak.

local ffi = require("ffi")
local bit = require("bit")

local M = { loaded = false, prism = nil, ctx = nil, backend = nil }

local is_win = ffi.os == "Windows"
local is_osx = ffi.os == "OSX"

if is_win then
    ffi.cdef([[
        int   MultiByteToWideChar(unsigned int cp, unsigned long flags,
                                  const char* mb, int cbmb, wchar_t* wc, int cchwc);
        void* LoadLibraryW(const wchar_t* path);
    ]])
end

ffi.cdef([[
    typedef struct prism_ctx prism_ctx;
    typedef struct prism_backend prism_backend;

    prism_ctx*     prism_init(void* config);
    void           prism_shutdown(prism_ctx* ctx);
    size_t         prism_registry_count(prism_ctx* ctx);
    uint64_t       prism_registry_id_at(prism_ctx* ctx, size_t index);
    const char*    prism_registry_name(prism_ctx* ctx, uint64_t id);
    prism_backend* prism_registry_create(prism_ctx* ctx, uint64_t id);
    prism_backend* prism_registry_create_best(prism_ctx* ctx);
    int            prism_backend_initialize(prism_backend* backend);
    void           prism_backend_free(prism_backend* backend);
    uint64_t       prism_backend_get_features(prism_backend* backend);
    const char*    prism_backend_name(prism_backend* backend);
    int            prism_backend_speak(prism_backend* backend, const char* text_utf8, bool interrupt);
    int            prism_backend_output(prism_backend* backend, const char* text_utf8, bool interrupt);
    int            prism_backend_stop(prism_backend* backend);
    int            prism_backend_set_volume(prism_backend* backend, float volume);
    int            prism_backend_set_rate(prism_backend* backend, float rate);
    int            prism_backend_set_pitch(prism_backend* backend, float pitch);
    int            prism_backend_get_volume(prism_backend* backend, float* out);
    int            prism_backend_get_rate(prism_backend* backend, float* out);
    int            prism_backend_get_pitch(prism_backend* backend, float* out);
    int            prism_backend_refresh_voices(prism_backend* backend);
    int            prism_backend_count_voices(prism_backend* backend, size_t* out);
    int            prism_backend_get_voice_name(prism_backend* backend, size_t voice_id, const char** out);
    int            prism_backend_get_voice_language(prism_backend* backend, size_t voice_id, const char** out);
    int            prism_backend_set_voice(prism_backend* backend, size_t voice_id);
    int            prism_backend_get_voice(prism_backend* backend, size_t* out);
]])

-- prism_error values the binding reacts to (the rest just mean "didn't work").
local OK = 0
local ALREADY_INITIALIZED = 1
local NOT_IMPLEMENTED = 9
-- prism_backend_get_features bits (PrismBackendFeature in prism.h).
local SUPPORTED_AT_RUNTIME = 0x1   -- engine actually present on this machine
local SUPPORTS_OUTPUT = 0x20       -- backend supports prism_backend_output
local FEATURE = {
    set_volume     = 2 ^ 10, get_volume = 2 ^ 11,
    set_rate       = 2 ^ 12, get_rate   = 2 ^ 13,
    set_pitch      = 2 ^ 14, get_pitch  = 2 ^ 15,
    refresh_voices = 2 ^ 16, count_voices = 2 ^ 17,
    get_voice_name = 2 ^ 18, get_voice_language = 2 ^ 19,
    get_voice      = 2 ^ 20, set_voice  = 2 ^ 21,
}
-- Features live in a uint64; LuaJIT's bit ops are 32-bit, so test the
-- high half separately (bits 10..21 all sit in the low word today, but
-- keep the helper honest).
local function has_feature(feat, flag)
    if flag < 2 ^ 32 then
        return bit.band(tonumber(feat % 2 ^ 32) or 0, flag) ~= 0
    end
    return bit.band(math.floor(tonumber(feat) / 2 ^ 32), flag / 2 ^ 32) ~= 0
end

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
-- next native call (backend-switch forensics: if the switch hard-crashes,
-- this line being last in the log is the whole point).
local function log_sync(text)
    pcall(function() love.filesystem.append("blindfold.log", log_line(text)) end)
end

local function log(text)
    -- Lands at %APPDATA%/Balatro/blindfold.log
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

-- Load Prism from the mod's lib/ folder and acquire the best available
-- backend (prism's own preference order). mod_dir is the deployed mod path.
function M.init(mod_dir)
    local ok, err = pcall(function()
        if is_win then
            local lib_dir = (mod_dir .. "/lib"):gsub("/", "\\")
            -- ffi.load routes through the ANSI LoadLibraryA, which garbles
            -- non-ASCII install paths (C:\Users\Usuário\... -> "module not
            -- found"). Load the DLL ourselves through the wide API; ffi.load by
            -- bare name then binds to the ALREADY-LOADED module (LoadLibrary
            -- resolves loaded modules by name before searching disk).
            local wide = to_wide(lib_dir .. "\\prism.dll")
            assert(wide and ffi.C.LoadLibraryW(wide) ~= nil,
                "LoadLibraryW failed for " .. lib_dir .. "\\prism.dll")
            M.prism = ffi.load("prism")
        elseif is_osx then
            local lib_path = mod_dir .. "/lib/libprism.dylib"
            M.prism = ffi.load(lib_path)
        else
            error("Unsupported operating system: " .. tostring(ffi.os))
        end

        M.ctx = M.prism.prism_init(nil)
        assert(M.ctx ~= nil, "prism_init returned null")
        M.backend = M.prism.prism_registry_create_best(M.ctx)
        assert(M.backend ~= nil, "no usable speech backend on this machine")
        M.supports_output = bit.band(tonumber(M.prism.prism_backend_get_features(M.backend)) or 0,
            SUPPORTS_OUTPUT) ~= 0
        M.current_backend = "auto"
        M.loaded = true
    end)
    if M.loaded then
        local name = M.prism.prism_backend_name(M.backend)
        log("Prism loaded (backend: " .. (name ~= nil and ffi.string(name) or "unknown") .. ").")
    else
        local lib_name = is_osx and "libprism.dylib" or "prism.dll"
        local lib_dir = is_win and (mod_dir .. "/lib"):gsub("/", "\\") or (mod_dir .. "/lib")
        log("Prism NOT loaded (" .. tostring(err) ..
            "). Drop the " .. lib_name .. " into " .. lib_dir ..
            " . Running with log output only.")
    end
    return M.loaded
end

-- Adopt a freshly-acquired backend as the active one and cache its features
-- (the query does real work per call on some backends).
local function adopt(backend, requested)
    M.backend = backend
    M.current_backend = requested
    M._features = M.prism.prism_backend_get_features(backend)
    M.supports_output = has_feature(M._features, SUPPORTS_OUTPUT)
    M._voices = nil
    local n = M.prism.prism_backend_name(backend)
    M.backend_name = n ~= nil and ffi.string(n) or "unknown"
    log("Prism backend: " .. M.backend_name .. " (requested " .. tostring(requested) .. ")")
    -- The per-backend voice settings (rate, volume, pitch, voice) are the
    -- user's, kept by the settings layer; it hands them back here so a
    -- fresh backend starts out configured the way they left it.
    if M.config_for then
        local ok, cfg = pcall(M.config_for, M.backend_name)
        if ok and type(cfg) == "table" then M.apply_config(cfg) end
    end
end

-- What the active backend lets the user adjust: the Voice settings screen
-- only shows a control when the backend can honor it.
function M.capabilities()
    local f = M._features
    if not M.loaded or f == nil then return {} end
    return {
        volume = has_feature(f, FEATURE.set_volume),
        rate   = has_feature(f, FEATURE.set_rate),
        pitch  = has_feature(f, FEATURE.set_pitch),
        voice  = has_feature(f, FEATURE.set_voice) and has_feature(f, FEATURE.count_voices)
                 and has_feature(f, FEATURE.get_voice_name),
    }
end

-- Prism normalizes volume, rate, and pitch to 0..1 (0.5 = the engine's
-- default for rate and pitch). Getters return nil when unsupported.
local function get_float(fn_name, flag)
    if not M.loaded or not has_feature(M._features, flag) then return nil end
    local out = ffi.new("float[1]")
    local ok, e = pcall(function() return M.prism[fn_name](M.backend, out) end)
    if ok and e == OK then return tonumber(out[0]) end
    return nil
end
function M.get_volume() return get_float("prism_backend_get_volume", FEATURE.get_volume) end
function M.get_rate()   return get_float("prism_backend_get_rate",   FEATURE.get_rate)   end
function M.get_pitch()  return get_float("prism_backend_get_pitch",  FEATURE.get_pitch)  end

local function set_float(fn_name, flag, v, what)
    if not M.loaded or type(v) ~= "number" or not has_feature(M._features, flag) then return false end
    v = math.max(0, math.min(1, v))
    local ok, e = pcall(function() return M.prism[fn_name](M.backend, v) end)
    if not ok or e ~= OK then
        log("Prism set " .. what .. " failed (" .. tostring(ok and e or e) .. ")")
        return false
    end
    return true
end
function M.set_volume(v) return set_float("prism_backend_set_volume", FEATURE.set_volume, v, "volume") end
function M.set_rate(v)   return set_float("prism_backend_set_rate",   FEATURE.set_rate,   v, "rate")   end
function M.set_pitch(v)  return set_float("prism_backend_set_pitch",  FEATURE.set_pitch,  v, "pitch")  end

-- The active backend's voices as { {id=, name=, language=}, ... }, enumerated
-- once per adoption (AVSpeech and SAPI need a refresh before they list any).
function M.voices()
    if not M.loaded or not M.capabilities().voice then return {} end
    if M._voices then return M._voices end
    local list = {}
    pcall(function()
        if has_feature(M._features, FEATURE.refresh_voices) then
            M.prism.prism_backend_refresh_voices(M.backend)
        end
        local count = ffi.new("size_t[1]")
        if M.prism.prism_backend_count_voices(M.backend, count) ~= OK then return end
        local name = ffi.new("const char*[1]")
        local lang = ffi.new("const char*[1]")
        local can_lang = has_feature(M._features, FEATURE.get_voice_language)
        for i = 0, tonumber(count[0]) - 1 do
            if M.prism.prism_backend_get_voice_name(M.backend, i, name) == OK and name[0] ~= nil then
                local l = nil
                if can_lang and M.prism.prism_backend_get_voice_language(M.backend, i, lang) == OK
                   and lang[0] ~= nil then
                    l = ffi.string(lang[0])
                end
                list[#list + 1] = { id = i, name = ffi.string(name[0]), language = l }
            end
        end
    end)
    M._voices = list
    return list
end

-- Name of the voice the backend is using now, or nil.
function M.current_voice_name()
    if not M.loaded or not has_feature(M._features, FEATURE.get_voice) then return nil end
    local out = ffi.new("size_t[1]")
    local ok, e = pcall(function() return M.prism.prism_backend_get_voice(M.backend, out) end)
    if not (ok and e == OK) then return nil end
    for _, v in ipairs(M.voices()) do
        if v.id == tonumber(out[0]) then return v.name end
    end
    return nil
end

function M.set_voice_by_name(name)
    if not M.loaded or type(name) ~= "string" then return false end
    for _, v in ipairs(M.voices()) do
        if v.name == name then
            local ok, e = pcall(function() return M.prism.prism_backend_set_voice(M.backend, v.id) end)
            if ok and e == OK then return true end
            log("Prism set voice '" .. name .. "' failed (" .. tostring(ok and e or e) .. ")")
            return false
        end
    end
    return false
end

-- Apply a saved configuration table { volume=, rate=, pitch= (0..1), voice=name }.
-- Missing entries leave the backend's own default in place.
function M.apply_config(cfg)
    if type(cfg) ~= "table" then return end
    if cfg.volume ~= nil then M.set_volume(cfg.volume) end
    if cfg.rate   ~= nil then M.set_rate(cfg.rate) end
    if cfg.pitch  ~= nil then M.set_pitch(cfg.pitch) end
    if cfg.voice  ~= nil then M.set_voice_by_name(cfg.voice) end
end

-- Backends we refuse to touch. UIA sat here briefly after a switch-away
-- crash, but the identical sequence survives in a windowed harness outside
-- the game (2026-07) — guilt unproven, so it's back for diagnosis now that
-- switches never free the outgoing backend. The pre-switch log line below
-- names the culprit if a switch ever kills the process again.
local BLOCKED = {}

-- Names of the backends actually usable on this machine (engine present),
-- enumerated once — the registry probe costs a native round-trip per entry.
function M.backends()
    -- Before init there is nothing to enumerate — and the miss must NOT be
    -- cached, or a call that lands too early (module load time) would pin the
    -- list empty forever.
    if not M.loaded then return {} end
    if M._backends then return M._backends end
    local names = {}
    do
        pcall(function()
            local count = tonumber(M.prism.prism_registry_count(M.ctx)) or 0
            for i = 0, count - 1 do
                local id = M.prism.prism_registry_id_at(M.ctx, i)
                local name = M.prism.prism_registry_name(M.ctx, id)
                if name ~= nil and not BLOCKED[ffi.string(name)] then
                    local b = M.prism.prism_registry_create(M.ctx, id)
                    if b ~= nil then
                        local feat = tonumber(M.prism.prism_backend_get_features(b)) or 0
                        if bit.band(feat, SUPPORTED_AT_RUNTIME) ~= 0 then
                            names[#names + 1] = ffi.string(name)
                        end
                        M.prism.prism_backend_free(b)
                    end
                end
            end
        end)
    end
    M._backends = names
    -- Forensics: the full lineup in registry order, once per session, so a
    -- later crash mid-switch can be placed against it.
    log("Prism backends detected: " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
    return names
end

-- Build a ready-to-use backend for the preference: the named backend if it can
-- be acquired (create + initialize), otherwise the best available. nil only
-- when nothing at all works. Does not touch M.backend.
local function acquire(name)
    if name and BLOCKED[name] then
        -- A stale saved choice from before the blocklist: never acquire it.
        log("Prism backend '" .. name .. "' is blocked (crashes in-game); using best available.")
        name = "auto"
    end
    if name and name ~= "auto" then
        local count = tonumber(M.prism.prism_registry_count(M.ctx)) or 0
        for i = 0, count - 1 do
            local id = M.prism.prism_registry_id_at(M.ctx, i)
            local n = M.prism.prism_registry_name(M.ctx, id)
            if n ~= nil and ffi.string(n) == name then
                local b = M.prism.prism_registry_create(M.ctx, id)
                if b ~= nil then
                    local e = M.prism.prism_backend_initialize(b)
                    if e == OK or e == ALREADY_INITIALIZED then return b end
                    M.prism.prism_backend_free(b)
                end
                break
            end
        end
        log("Prism backend '" .. name .. "' unavailable; falling back to best available.")
    end
    local b = M.prism.prism_registry_create_best(M.ctx)
    if b ~= nil then return b end
    return nil
end

-- Switch backends (the settings menu's Speech backend cycle; "auto" = best
-- available). Acquire the replacement BEFORE tearing down the current backend,
-- so a choice that can't be acquired never leaves us silent — never strand a
-- blind user with no voice (wotr-access rule).
function M.set_backend(name)
    if not M.loaded then return end
    name = name or "auto"
    if name == M.current_backend then return end
    -- Logged SYNCHRONOUSLY before any native call: if a switch hard-crashes
    -- the game, this is the last line in the log and names the backend being
    -- switched TO (and the live one being switched away from).
    log_sync("Prism: switching to '" .. name .. "' (from '" .. tostring(M.current_backend) .. "')")
    pcall(function()
        local replacement = acquire(name)
        if replacement == nil then
            log("Prism: nothing acquirable for '" .. name .. "'; keeping current backend.")
            return
        end
        log_sync("Prism: acquired '" .. name .. "', stopping the old backend")
        if M.backend ~= nil and replacement ~= M.backend then
            M.prism.prism_backend_stop(M.backend)
            -- Deliberately NEVER freed at runtime. A backend switch crashed
            -- the game between acquire/stop/free, and the identical sequence
            -- survives in a windowed harness outside it — so rather than
            -- guess which native teardown misbehaves inside LOVE, retire the
            -- handle unfreed (a stopped backend is a few KB; process exit
            -- reclaims all). Never trade a blind user's voice for tidy
            -- memory. Probe frees in backends()/acquire() stay: those
            -- backends were never initialized/started.
            M._retired = M._retired or {}
            M._retired[#M._retired + 1] = M.backend
        end
        adopt(replacement, name)
    end)
end

-- Speak text. interrupt defaults to false to honor the SayTheSpire2 preference
-- of never cutting off in-progress speech; pass true explicitly to override.
-- Lag forensics: a prism call runs synchronously on the game's main thread —
-- when the backend (NVDA controller, SAPI, ...) stalls, the window and the
-- screen reader hitch TOGETHER. Log any call beyond 30ms with its duration.
local function timer_now()
    local ok, t = pcall(function() return love.timer.getTime() end)
    return ok and t or nil
end
local function log_slow_call(t0, what, detail)
    if not t0 then return end
    local t1 = timer_now()
    if t1 and (t1 - t0) > 0.03 then
        log(string.format("SLOW prism %s: %dms%s", what,
            math.floor((t1 - t0) * 1000 + 0.5), detail or ""))
    end
end

function M.say(text, interrupt)
    if type(text) ~= "string" or text == "" then return end
    log(text)
    if not M.loaded then return end
    local cut = interrupt == true
    local t0 = timer_now()
    pcall(function()
        -- output drives speech AND braille where the backend supports it;
        -- anything but a clean OK falls through to plain speak so we still
        -- produce audio (mirrors the wotr-access handler).
        if M.supports_output then
            local e = M.prism.prism_backend_output(M.backend, text, cut)
            if e == OK then return end
            if e ~= NOT_IMPLEMENTED then
                log("prism output error " .. tostring(e) .. ", falling back to speak")
            end
        end
        M.prism.prism_backend_speak(M.backend, text, cut)
    end)
    log_slow_call(t0, "speak", " (" .. #text .. " chars)")
end

function M.silence()
    if not M.loaded then return end
    local t0 = timer_now()
    pcall(function() M.prism.prism_backend_stop(M.backend) end)
    log_slow_call(t0, "stop")
end

return M
