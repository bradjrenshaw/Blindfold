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

ffi.cdef([[
    int   MultiByteToWideChar(unsigned int cp, unsigned long flags,
                              const char* mb, int cbmb, wchar_t* wc, int cchwc);
    void* LoadLibraryW(const wchar_t* path);

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
]])

-- prism_error values the binding reacts to (the rest just mean "didn't work").
local OK = 0
local ALREADY_INITIALIZED = 1
local NOT_IMPLEMENTED = 9
-- prism_backend_get_features bits.
local SUPPORTED_AT_RUNTIME = 0x1   -- engine actually present on this machine
local SUPPORTS_OUTPUT = 0x20       -- backend supports prism_backend_output

local function log(text)
    -- Lands at %APPDATA%/Balatro/blindfold.log
    pcall(function()
        love.filesystem.append("blindfold.log", os.date("%H:%M:%S ") .. text .. "\n")
    end)
end
M.log = log

-- UTF-8 Lua string -> null-terminated UTF-16LE buffer (for the wide Win32 API).
local CP_UTF8 = 65001
local function to_wide(s)
    local n = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
    if n <= 0 then return nil end
    local buf = ffi.new("wchar_t[?]", n)
    ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, n)
    return buf
end

-- Load Prism from the mod's lib/ folder and acquire the best available
-- backend (prism's own preference order). mod_dir is the deployed mod path.
function M.init(mod_dir)
    local lib_dir = (mod_dir .. "/lib"):gsub("/", "\\")
    local ok, err = pcall(function()
        -- ffi.load routes through the ANSI LoadLibraryA, which garbles
        -- non-ASCII install paths (C:\Users\Usuário\... -> "module not
        -- found"). Load the DLL ourselves through the wide API; ffi.load by
        -- bare name then binds to the ALREADY-LOADED module (LoadLibrary
        -- resolves loaded modules by name before searching disk).
        local wide = to_wide(lib_dir .. "\\prism.dll")
        assert(wide and ffi.C.LoadLibraryW(wide) ~= nil,
            "LoadLibraryW failed for " .. lib_dir .. "\\prism.dll")
        M.prism = ffi.load("prism")
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
        log("Prism NOT loaded (" .. tostring(err) ..
            "). Drop the x64 prism.dll into " .. lib_dir ..
            " . Running with log output only.")
    end
    return M.loaded
end

-- Adopt a freshly-acquired backend as the active one and cache its features
-- (the query does real work per call on some backends).
local function adopt(backend, requested)
    M.backend = backend
    M.current_backend = requested
    M.supports_output = bit.band(tonumber(M.prism.prism_backend_get_features(backend)) or 0,
        SUPPORTS_OUTPUT) ~= 0
    local n = M.prism.prism_backend_name(backend)
    log("Prism backend: " .. (n ~= nil and ffi.string(n) or "unknown")
        .. " (requested " .. tostring(requested) .. ")")
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
    -- Logged BEFORE any native call: if a switch hard-crashes the game, this
    -- is the last line in the log and names the backend being switched TO
    -- (and the live one being switched away from).
    log("Prism: switching to '" .. name .. "' (from '" .. tostring(M.current_backend) .. "')")
    pcall(function()
        local replacement = acquire(name)
        if replacement == nil then
            log("Prism: nothing acquirable for '" .. name .. "'; keeping current backend.")
            return
        end
        log("Prism: acquired '" .. name .. "', stopping the old backend")
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
function M.say(text, interrupt)
    if type(text) ~= "string" or text == "" then return end
    log(text)
    if not M.loaded then return end
    local cut = interrupt == true
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
end

function M.silence()
    if M.loaded then pcall(function() M.prism.prism_backend_stop(M.backend) end) end
end

return M
