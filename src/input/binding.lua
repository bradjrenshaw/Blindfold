-- input/binding.lua — a single keyboard binding (key + modifiers).
-- Port of SayTheSpire2's KeyboardBinding. The rebindable settings menu will
-- create/edit these; for now they're built from the default scheme.
local require = ...
local Message = require("ui.message")

local KeyboardBinding = {}
KeyboardBinding.__index = KeyboardBinding

function KeyboardBinding.new(key, ctrl, shift, alt)
    return setmetatable({
        key = key, ctrl = ctrl or false, shift = shift or false, alt = alt or false,
    }, KeyboardBinding)
end

-- `mods` is { ctrl, shift, alt } booleans (the currently-held modifiers).
function KeyboardBinding:matches(key, mods)
    return self.key == key
        and self.ctrl == mods.ctrl and self.shift == mods.shift and self.alt == mods.alt
end

-- Human-readable form for the settings menu (e.g. "Ctrl+Left Shift").
-- Names live in loc KEYS.* (bare letter keys read as themselves).
local PRETTY = {
    ["return"] = "RETURN", kpenter = "KPENTER",
    lshift = "LSHIFT", rshift = "RSHIFT",
    lctrl = "LCTRL", rctrl = "RCTRL", lalt = "LALT", ralt = "RALT",
    up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
    space = "SPACE", escape = "ESCAPE", tab = "TAB", backspace = "BACKSPACE",
}
local function key_word(loc_key)
    return Message.localized("KEYS." .. loc_key):resolve()
end
function KeyboardBinding:display()
    local parts = {}
    if self.ctrl then parts[#parts + 1] = key_word("CTRL") end
    if self.shift then parts[#parts + 1] = key_word("SHIFT") end
    if self.alt then parts[#parts + 1] = key_word("ALT") end
    parts[#parts + 1] = PRETTY[self.key] and key_word(PRETTY[self.key]) or self.key
    return table.concat(parts, "+")
end

return KeyboardBinding
