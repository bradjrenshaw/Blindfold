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
    typedef struct prism_ctx prism_ctx;
    typedef struct prism_backend prism_backend;

    prism_ctx*     prism_init(void* config);
    void           prism_shutdown(prism_ctx* ctx);
    prism_backend* prism_registry_create_best(prism_ctx* ctx);
    void           prism_backend_free(prism_backend* backend);
    uint64_t       prism_backend_get_features(prism_backend* backend);
    const char*    prism_backend_name(prism_backend* backend);
    int            prism_backend_speak(prism_backend* backend, const char* text_utf8, bool interrupt);
    int            prism_backend_output(prism_backend* backend, const char* text_utf8, bool interrupt);
    int            prism_backend_stop(prism_backend* backend);
]])

-- prism_error values the binding reacts to (the rest just mean "didn't work").
local OK = 0
local NOT_IMPLEMENTED = 9
-- prism_backend_get_features bit: backend supports prism_backend_output.
local SUPPORTS_OUTPUT = 0x20

local function log(text)
    -- Lands at %APPDATA%/Balatro/blindfold.log
    pcall(function()
        love.filesystem.append("blindfold.log", os.date("%H:%M:%S ") .. text .. "\n")
    end)
end
M.log = log

-- Load Prism from the mod's lib/ folder and acquire the best available
-- backend (prism's own preference order). mod_dir is the deployed mod path.
function M.init(mod_dir)
    local lib_dir = (mod_dir .. "/lib"):gsub("/", "\\")
    local ok, err = pcall(function()
        M.prism = ffi.load(lib_dir .. "\\prism.dll")
        M.ctx = M.prism.prism_init(nil)
        assert(M.ctx ~= nil, "prism_init returned null")
        M.backend = M.prism.prism_registry_create_best(M.ctx)
        assert(M.backend ~= nil, "no usable speech backend on this machine")
        M.supports_output = bit.band(tonumber(M.prism.prism_backend_get_features(M.backend)) or 0,
            SUPPORTS_OUTPUT) ~= 0
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
