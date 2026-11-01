-- platform/macos.lua — macOS-only adjustments to the game's own window.
--
-- LÖVE's window library (SDL) gives the game a standard macOS menu bar, and
-- its Window > Minimize item claims Command+M. Blindfold's default readouts
-- use Command where Windows uses Ctrl (input/binding.lua), so Command+M is
-- "read money" — but a menu key equivalent wins before the game ever sees
-- the key, and the window minimized instead. free_command_m clears that one
-- key equivalent; Minimize stays in the menu, without a shortcut.
--
-- Talks to AppKit through LuaJIT's FFI and the Objective-C runtime. Every
-- message goes through a cast to its exact prototype (objc_msgSend must not
-- be called variadically on arm64). Safe to run again (a hot reload): the
-- cdef is guarded and a cleared item no longer matches.
local M = {}

local NS_COMMAND = 0x100000  -- NSEventModifierFlagCommand

function M.free_command_m()
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi or ffi.os ~= "OSX" then return false, "not macOS" end
    -- Already declared by an earlier generation: LuaJIT refuses a redefinition.
    pcall(ffi.cdef, [[
        void *objc_getClass(const char *name);
        void *sel_registerName(const char *name);
        void objc_msgSend(void);
    ]])
    local C = ffi.C
    local send = ffi.cast("void *", C.objc_msgSend)
    local msg = ffi.cast("void *(*)(void *, void *)", send)
    local msg_long = ffi.cast("long (*)(void *, void *)", send)
    local msg_ulong = ffi.cast("unsigned long (*)(void *, void *)", send)
    local msg_at = ffi.cast("void *(*)(void *, void *, long)", send)
    local msg_str = ffi.cast("const char *(*)(void *, void *)", send)
    local msg_set = ffi.cast("void (*)(void *, void *, void *)", send)
    local sel = C.sel_registerName

    local app = msg(C.objc_getClass("NSApplication"), sel("sharedApplication"))
    local menu = app ~= nil and msg(app, sel("mainMenu")) or nil
    if menu == nil then return false, "no main menu" end

    local cleared = 0
    -- C longs come back as 64-bit cdata; plain numbers for the loops.
    for i = 0, tonumber(msg_long(menu, sel("numberOfItems"))) - 1 do
        local sub = msg(msg_at(menu, sel("itemAtIndex:"), i), sel("submenu"))
        if sub ~= nil then
            for j = 0, tonumber(msg_long(sub, sel("numberOfItems"))) - 1 do
                local item = msg_at(sub, sel("itemAtIndex:"), j)
                local key = msg(item, sel("keyEquivalent"))
                local text = key ~= nil and msg_str(key, sel("UTF8String")) or nil
                local mods = tonumber(msg_ulong(item, sel("keyEquivalentModifierMask")))
                -- Exactly Command+M (not, say, Option+Command+M).
                if text ~= nil and ffi.string(text) == "m" and mods == NS_COMMAND then
                    local empty = msg(C.objc_getClass("NSString"), sel("string"))
                    msg_set(item, sel("setKeyEquivalent:"), empty)
                    cleared = cleared + 1
                end
            end
        end
    end
    return cleared > 0, cleared > 0 and "cleared" or "no Command+M item"
end

return M
