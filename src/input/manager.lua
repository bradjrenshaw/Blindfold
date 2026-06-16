-- input/manager.lua — the InputAction registry + keyboard dispatch (port of
-- SayTheSpire2's InputManager). Keyboard keys are translated to the gamepad
-- buttons the engine already navigates with; the engine routes them by context
-- (registry / capture_focused_input), so we never special-case screens.
--
-- Designed for a later rebinding settings menu: actions carry labels + default
-- bindings, and start_listening/stop_listening capture a new binding.
local require = ...
local KeyboardBinding = require("input.binding")
local InputAction = require("input.action")

local M = {
    actions = {},
    by_key = {},
    _active = {},        -- pressed keyboard key -> gamepad button currently held
    _listen_cb = nil,    -- rebind capture callback (settings menu)
    kb_active = false,   -- has the keyboard driven nav yet (gates the mouse lock)
    lock_focus_mode = true,
    silence = nil,       -- optional fn() run when a key is consumed (speech.silence)
}
M.KeyboardBinding = KeyboardBinding
M.InputAction = InputAction

function M.register(opts)
    local a = InputAction.new(opts)
    M.actions[#M.actions + 1] = a
    M.by_key[a.key] = a
    return a
end

function M.find(key) return M.by_key[key] end

-- Force the controller into keyboard-driven focus mode. The engine's built-in
-- keyboard "gamepad" stub reports zero axes, so update_axis stays safe.
function M.ensure_kb_nav(ctrl)
    if ctrl.GAMEPAD.object ~= ctrl.keyboard_controller then
        pcall(function() ctrl:set_gamepad(ctrl.keyboard_controller) end)
        ctrl.GAMEPAD.object = ctrl.keyboard_controller
    end
    ctrl:set_HID_flags("button")
    M.kb_active = true
end

local function mods_from(ctrl)
    local h = ctrl.held_keys or {}
    return {
        ctrl = (h.lctrl or h.rctrl) and true or false,
        shift = (h.lshift or h.rshift) and true or false,
        alt = (h.lalt or h.ralt) and true or false,
    }
end

-- Returns true if the key was consumed (the caller then suppresses the game's
-- own handling of it).
function M.on_key_down(ctrl, key)
    -- Rebind capture for the settings menu: the next keypress becomes a binding.
    if M._listen_cb then
        local cb = M._listen_cb
        M._listen_cb = nil
        local mods = mods_from(ctrl)
        cb(KeyboardBinding.new(key, mods.ctrl, mods.shift, mods.alt))
        return true
    end
    -- Let the game's text fields (seed / profile name) receive keys untouched.
    if ctrl.text_input_hook then return false end

    local mods = mods_from(ctrl)
    -- Most-specific match wins (a Ctrl+X binding beats a bare X binding).
    local best, best_score
    for _, a in ipairs(M.actions) do
        local b = a:matches(key, mods)
        if b then
            local score = (b.ctrl and 1 or 0) + (b.shift and 1 or 0) + (b.alt and 1 or 0)
            if not best or score > best_score then best, best_score = a, score end
        end
    end
    if not best then return false end

    if M.silence then pcall(M.silence) end
    if best.game_button then
        M.ensure_kb_nav(ctrl)
        ctrl:button_press(best.game_button)
        M._active[key] = best.game_button
    elseif best.handler then
        pcall(best.handler, ctrl)
    end
    return true
end

function M.on_key_up(ctrl, key)
    if M._listen_cb then return true end
    local btn = M._active[key]
    if btn then
        M._active[key] = nil
        ctrl:button_release(btn)
        return true
    end
    return false
end

-- Settings-menu rebind: capture the next keypress as a binding via cb(binding).
function M.start_listening(cb) M._listen_cb = cb end
function M.stop_listening() M._listen_cb = nil end

-- Restore every action's bindings to its defaults (keeps the action list, so
-- mod-only actions like the debug dump survive).
function M.reset_defaults()
    for _, a in ipairs(M.actions) do a:reset_to_default() end
end

-- Register the default action set: the dev's keyboard scheme (WASD nav, Space
-- select, Shift back, X play, C discard, Q/E triggers) plus arrows/Enter for
-- accessibility, and bracket/Tab keys for the shoulders/run-info the dev scheme
-- left unbound. Escape is intentionally NOT bound — it falls through to the
-- game's native handler (options / exit-overlay), which is richer than 'start'.
function M.init()
    M.actions = {}
    M.by_key = {}
    M._active = {}
    local function reg(key, label, button, keys)
        local binds = {}
        for _, k in ipairs(keys) do binds[#binds + 1] = KeyboardBinding.new(k) end
        M.register{ key = key, label_key = label, game_button = button, bindings = binds }
    end
    reg("nav_up",         "INPUT.NAV_UP",         "dpup",          { "w", "up" })
    reg("nav_down",       "INPUT.NAV_DOWN",       "dpdown",        { "s", "down" })
    reg("nav_left",       "INPUT.NAV_LEFT",       "dpleft",        { "a", "left" })
    reg("nav_right",      "INPUT.NAV_RIGHT",      "dpright",       { "d", "right" })
    reg("select",         "INPUT.SELECT",         "a",             { "space", "return", "kpenter" })
    reg("back",           "INPUT.BACK",           "b",             { "lshift", "rshift", "backspace" })
    reg("play_hand",      "INPUT.PLAY_HAND",      "x",             { "x" })
    reg("discard",        "INPUT.DISCARD",        "y",             { "c" })
    reg("shoulder_left",  "INPUT.SHOULDER_LEFT",  "leftshoulder",  { "[" })
    reg("shoulder_right", "INPUT.SHOULDER_RIGHT", "rightshoulder", { "]" })
    reg("view_deck",      "INPUT.VIEW_DECK",      "triggerleft",   { "q" })
    reg("right_trigger",  "INPUT.RIGHT_TRIGGER",  "triggerright",  { "e" })
    reg("run_info",       "INPUT.RUN_INFO",       "back",          { "tab" })
end

return M
