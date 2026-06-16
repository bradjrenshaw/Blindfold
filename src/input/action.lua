-- input/action.lua — a rebindable input action (port of SayTheSpire2's
-- InputAction). Each action has a stable key, a localized label (for the future
-- settings menu), a set of keyboard bindings, and either a game gamepad button
-- to drive or a mod handler to run.
local require = ...

local InputAction = {}
InputAction.__index = InputAction

local function copy_bindings(t)
    local out = {}
    for i, b in ipairs(t) do out[i] = b end
    return out
end

-- opts: { key, label_key, game_button?, handler?, bindings? }
function InputAction.new(opts)
    local self = setmetatable({
        key = opts.key,
        label_key = opts.label_key,   -- loc key, resolved by the settings menu
        game_button = opts.game_button,  -- gamepad button to send, or nil
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
    if #self.bindings == 0 then return "(unbound)" end
    local parts = {}
    for _, b in ipairs(self.bindings) do parts[#parts + 1] = b:display() end
    return table.concat(parts, ", ")
end

return InputAction
