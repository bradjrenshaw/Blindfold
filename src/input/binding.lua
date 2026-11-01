-- input/binding.lua — a single keyboard binding (key + modifiers).
-- Port of SayTheSpire2's KeyboardBinding. The rebindable settings menu will
-- create/edit these; for now they're built from the default scheme.
local require = ...
local Message = require("ui.message")

local KeyboardBinding = {}
KeyboardBinding.__index = KeyboardBinding

-- `gui` is Command on macOS (the Windows key elsewhere; LÖVE's lgui/rgui).
function KeyboardBinding.new(key, ctrl, shift, alt, gui)
    return setmetatable({
        key = key, ctrl = ctrl or false, shift = shift or false, alt = alt or false,
        gui = gui or false,
    }, KeyboardBinding)
end

local function is_mac()
    return love and love.system and love.system.getOS and love.system.getOS() == "OS X"
end

-- The modifier the default combos use: Command on macOS, where Ctrl+arrows
-- belong to Mission Control and Spaces; Ctrl everywhere else.
function KeyboardBinding.primary_modifier()
    return is_mac() and "gui" or "ctrl"
end

-- `key` with the platform's primary modifier (Ctrl+X on Windows, Command+X
-- on macOS).
function KeyboardBinding.primary(key)
    local gui = KeyboardBinding.primary_modifier() == "gui"
    return KeyboardBinding.new(key, not gui, false, false, gui)
end

-- `mods` is { ctrl, shift, alt, gui } booleans (the currently-held modifiers).
function KeyboardBinding:matches(key, mods)
    return self.key == key
        and self.ctrl == mods.ctrl and self.shift == mods.shift and self.alt == mods.alt
        and self.gui == (mods.gui or false)
end

-- Same key and modifiers.
function KeyboardBinding:same(other)
    return self.key == other.key and self.ctrl == other.ctrl and self.shift == other.shift
        and self.alt == other.alt and self.gui == (other.gui or false)
end

-- Human-readable form for the settings menu (e.g. "Ctrl+Left Shift").
-- Names live in loc KEYS.* (bare letter keys read as themselves).
local PRETTY = {
    ["return"] = "RETURN", kpenter = "KPENTER",
    lshift = "LSHIFT", rshift = "RSHIFT",
    lctrl = "LCTRL", rctrl = "RCTRL", lalt = "LALT", ralt = "RALT",
    lgui = "LGUI", rgui = "RGUI",
    up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
    space = "SPACE", escape = "ESCAPE", tab = "TAB", backspace = "BACKSPACE",
}
local function key_word(loc_key)
    -- The gui key (either side) is Command on macOS, the Windows key elsewhere.
    if loc_key == "GUI" or loc_key == "LGUI" or loc_key == "RGUI" then
        loc_key = is_mac() and "CMD" or "WIN"
    end
    return Message.localized("KEYS." .. loc_key):resolve()
end
function KeyboardBinding:display()
    local parts = {}
    if self.gui then parts[#parts + 1] = key_word("GUI") end
    if self.ctrl then parts[#parts + 1] = key_word("CTRL") end
    if self.shift then parts[#parts + 1] = key_word("SHIFT") end
    if self.alt then parts[#parts + 1] = key_word("ALT") end
    parts[#parts + 1] = PRETTY[self.key] and key_word(PRETTY[self.key]) or self.key
    return table.concat(parts, "+")
end

return KeyboardBinding
