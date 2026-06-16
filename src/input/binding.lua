-- input/binding.lua — a single keyboard binding (key + modifiers).
-- Port of SayTheSpire2's KeyboardBinding. The rebindable settings menu will
-- create/edit these; for now they're built from the default scheme.
local require = ...

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
local PRETTY = {
    ["return"] = "Enter", kpenter = "Keypad Enter",
    lshift = "Left Shift", rshift = "Right Shift",
    lctrl = "Left Ctrl", rctrl = "Right Ctrl", lalt = "Left Alt", ralt = "Right Alt",
    up = "Up", down = "Down", left = "Left", right = "Right",
    space = "Space", escape = "Escape", tab = "Tab", backspace = "Backspace",
}
function KeyboardBinding:display()
    local parts = {}
    if self.ctrl then parts[#parts + 1] = "Ctrl" end
    if self.shift then parts[#parts + 1] = "Shift" end
    if self.alt then parts[#parts + 1] = "Alt" end
    parts[#parts + 1] = PRETTY[self.key] or self.key
    return table.concat(parts, "+")
end

return KeyboardBinding
