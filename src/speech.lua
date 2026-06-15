-- speech.lua — screen-reader output for balatro-access.
--
-- Primary backend is Tolk (NVDA/JAWS/SAPI bridge) loaded via LuaJIT FFI. A log
-- fallback always runs too, so the mod is testable BEFORE Tolk.dll is dropped
-- in (focus changes show up in %APPDATA%/Balatro/balatro-access.log).
--
-- Tolk takes UTF-16 (wchar_t*), so we convert UTF-8 -> UTF-16 via the Win32
-- MultiByteToWideChar. Balatro is 64-bit, so Tolk.dll and its screen-reader
-- client DLLs must be the x64 builds.

local ffi = require("ffi")

local M = { loaded = false, tolk = nil }

ffi.cdef([[
    int  MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags,
                             const char* lpMultiByteStr, int cbMultiByte,
                             wchar_t* lpWideCharStr, int cchWideChar);
    int  SetDllDirectoryW(const wchar_t* lpPathName);

    void Tolk_Load();
    void Tolk_Unload();
    bool Tolk_IsLoaded();
    bool Tolk_Output(const wchar_t* str, bool interrupt);
    bool Tolk_Silence();
]])

local C = ffi.C
local CP_UTF8 = 65001

-- UTF-8 Lua string -> null-terminated UTF-16LE wchar_t buffer.
local function to_wide(s)
    local n = C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
    if n <= 0 then return nil end
    local buf = ffi.new("wchar_t[?]", n)
    C.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, n)
    return buf
end

local function log(text)
    -- Lands at %APPDATA%/Balatro/balatro-access.log
    pcall(function()
        love.filesystem.append("balatro-access.log", os.date("%H:%M:%S ") .. text .. "\n")
    end)
end
M.log = log

-- Load Tolk from the mod's lib/ folder. mod_dir is the deployed mod path.
function M.init(mod_dir)
    local lib_dir = (mod_dir .. "/lib"):gsub("/", "\\")
    local ok, err = pcall(function()
        -- So Tolk's own LoadLibrary calls find nvdaControllerClient64.dll etc.
        local wdir = to_wide(lib_dir)
        if wdir then C.SetDllDirectoryW(wdir) end
        M.tolk = ffi.load(lib_dir .. "\\Tolk.dll")
        M.tolk.Tolk_Load()
        M.loaded = M.tolk.Tolk_IsLoaded()
    end)
    if ok and M.loaded then
        log("Tolk loaded.")
    else
        log("Tolk NOT loaded (" .. tostring(err) ..
            "). Drop the x64 Tolk.dll + screen-reader client DLLs into " ..
            lib_dir .. " . Running with log output only.")
    end
    return M.loaded
end

-- Speak text. interrupt defaults to false to honor the SayTheSpire2 preference
-- of never cutting off in-progress speech; pass true explicitly to override.
function M.say(text, interrupt)
    if type(text) ~= "string" or text == "" then return end
    log(text)
    if M.loaded and M.tolk then
        local w = to_wide(text)
        if w then M.tolk.Tolk_Output(w, interrupt == true) end
    end
end

function M.silence()
    if M.loaded and M.tolk then pcall(function() M.tolk.Tolk_Silence() end) end
end

return M
