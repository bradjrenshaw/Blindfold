-- host.lua — the part of Blindfold that survives a hot reload (the wotr-access
-- HOST/MODULE split). Everything else is a GENERATION: core.lua and the whole
-- ba_require tree, re-run from disk by reload().
--
-- State lives on _G.BlindfoldHost, created by the first generation and reused
-- by every later one; this file's functions are simply redefined each time.
--
-- Hooks: hook(tbl, key, make) wraps tbl[key] ONCE with a permanent trampoline
-- that calls the current generation's implementation, make(orig). A reload
-- clears every implementation (the trampolines fall through to the game's
-- originals) and the new generation re-registers its own — so nothing is ever
-- double-wrapped, and a generation that stops hooking something simply stops.
local H = _G.BlindfoldHost
if not H then
    H = {
        gen = 0,
        hooks = {},   -- [tbl] = { [key] = { orig = fn, impl = fn? } }
    }
    _G.BlindfoldHost = H
end

function H.hook(tbl, key, make)
    if type(tbl) ~= "table" then return end
    local byk = H.hooks[tbl]
    if not byk then byk = {}; H.hooks[tbl] = byk end
    local rec = byk[key]
    if not rec then
        local orig = tbl[key]
        if type(orig) ~= "function" then return end
        rec = { orig = orig }
        byk[key] = rec
        tbl[key] = function(...)
            local impl = rec.impl
            if impl then return impl(...) end
            return rec.orig(...)
        end
    end
    rec.impl = make(rec.orig)
end

-- Start a new generation: every hook falls back to the original until the
-- generation re-registers it.
function H.begin_generation()
    H.gen = H.gen + 1
    for _, byk in pairs(H.hooks) do
        for _, rec in pairs(byk) do rec.impl = nil end
    end
end

-- Re-run core.lua from disk as a new generation. Compiles first, so a syntax
-- error leaves the running generation untouched. Main thread only.
function H.reload()
    if not H.read then return "[error] host has no file reader\n" end
    local code = H.read("core.lua")
    if not code then return "[error] cannot read core.lua\n" end
    local chunk, err = load(code, "@blindfold/core.lua")
    if not chunk then return "[compile error] " .. tostring(err) .. "\n" end
    local old = _G.Blindfold
    if old and old.teardown then pcall(old.teardown) end
    local ok, res = pcall(chunk)
    if not ok then return "[boot error] " .. tostring(res) .. "\n" end
    local ba = _G.Blindfold
    if ba and ba.boot_error then
        return "[boot error] generation " .. H.gen .. ": " .. tostring(ba.boot_error) .. "\n"
    end
    return "reloaded: generation " .. H.gen .. "\n"
end

return H
