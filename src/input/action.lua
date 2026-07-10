-- input/action.lua — a rebindable input action (port of SayTheSpire2's
-- InputAction). Each action has a stable key, a localized label (for the
-- keybindings menu), a set of keyboard bindings, and what it drives: an
-- overlay COMMAND on owned screens, a mod HANDLER, and/or a fallback gamepad
-- BUTTON for the not-yet-owned game screens (menus). The button tier is
-- transitional — it dies once every screen is an owned overlay.
local require = ...
local Message = require("ui.message")

local InputAction = {}
InputAction.__index = InputAction

local function copy_bindings(t)
    local out = {}
    for i, b in ipairs(t) do out[i] = b end
    return out
end

-- opts: { key, label_key, command?, game_button?, handler?, bindings? }
function InputAction.new(opts)
    local self = setmetatable({
        key = opts.key,
        label_key = opts.label_key,   -- loc key, resolved by the settings menu
        command = opts.command,          -- overlay command table, or nil
        game_button = opts.game_button,  -- fallback gamepad button, or nil
        handler = opts.handler,          -- mod-only action fn(ctrl), or nil
        bindings = opts.bindings or {},
    }, InputAction)
    self.default_bindings = copy_bindings(self.bindings)
    return self
end

-- The first binding matching (key, mods), or nil.
function InputAction:matches(key, mods)
    for _, b in ipairs(self.bindings) do
        if b:matches(key, mods) then return b end
    end
    return nil
end

function InputAction:add_binding(b) self.bindings[#self.bindings + 1] = b; return self end
function InputAction:clear_bindings() self.bindings = {} end
function InputAction:reset_to_default() self.bindings = copy_bindings(self.default_bindings) end

function InputAction:bindings_display()
    if #self.bindings == 0 then return Message.localized("KEYS.UNBOUND"):resolve() end
    local parts = {}
    for _, b in ipairs(self.bindings) do parts[#parts + 1] = b:display() end
    return table.concat(parts, ", ")
end

return InputAction
