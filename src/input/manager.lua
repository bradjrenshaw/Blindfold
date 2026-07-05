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

-- Modifier keys, skipped during rebind capture so combos (e.g. Ctrl+X) bind on
-- the X press with Ctrl folded into the held state.
local MODIFIER_KEYS = { lctrl = true, rctrl = true, lshift = true, rshift = true, lalt = true, ralt = true }

local M = {
    actions = {},
    by_key = {},
    _active = {},        -- pressed keyboard key -> gamepad button currently held
    _listen_cb = nil,    -- rebind capture callback (settings menu)
    kb_active = false,   -- has the keyboard driven nav yet (gates the mouse lock)
    lock_focus_mode = true,
    silence = nil,       -- optional fn() run when a key is consumed (speech.silence)
    dispatcher = nil,    -- overlay dispatcher (owned-UI layer), injected by core
    overlay_tick = nil,  -- fn(command) that runs + speaks a dispatcher tick, injected by core
    handlers = {},       -- direct-call action implementations, injected by core
                         -- (play_hand / discard call into the play overlay)
    _pad_active = {},    -- gamepad buttons whose press we consumed (swallow the release)
}

-- The mod's default controller scheme: physical gamepad buttons -> mod
-- actions, mirroring the keyboard defaults. Buttons absent from the live map
-- pass through to the engine's native handling (B = back/deselect, Start =
-- pause, Back = run info, triggers = view deck / secondary). Triggers can't
-- be mapped to mod actions: they arrive as axes, not through the gamepad
-- button callback (so they also can't be captured when rebinding).
local DEFAULT_PAD_ACTIONS = {
    dpup = "nav_up", dpdown = "nav_down", dpleft = "nav_left", dpright = "nav_right",
    a = "select",
    x = "play_hand",
    y = "discard",
    leftshoulder = "sell",
    rightshoulder = "use",
    leftstick = "grab",
}
M.PAD_ACTIONS = {}   -- the live (rebindable, persisted) map; filled in init

local PAD_NAMES = {
    dpup = "D-Pad Up", dpdown = "D-Pad Down", dpleft = "D-Pad Left", dpright = "D-Pad Right",
    a = "A", b = "B", x = "X", y = "Y",
    leftshoulder = "Left Bumper", rightshoulder = "Right Bumper",
    leftstick = "Left Stick Click", rightstick = "Right Stick Click",
    back = "Back", start = "Start", guide = "Guide",
}
function M.pad_display(button)
    return PAD_NAMES[button] or tostring(button)
end

-- The button an action is currently on, or nil (for the keybindings screen).
function M.pad_button_for(action_key)
    for btn, key in pairs(M.PAD_ACTIONS) do
        if key == action_key then return btn end
    end
    return nil
end

local function apply_pad_binding(action_key, button)
    for btn, key in pairs(M.PAD_ACTIONS) do
        if key == action_key then M.PAD_ACTIONS[btn] = nil end
    end
    M.PAD_ACTIONS[button] = action_key   -- steals the button from any other action
end

function M.set_pad_binding(action_key, button)
    apply_pad_binding(action_key, button)
    M.save_bindings()
end
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
    -- Rebind capture for the settings menu: the next non-modifier keypress
    -- becomes a binding (held modifiers are folded in).
    if M._listen_cb then
        if not MODIFIER_KEYS[key] then
            local cb = M._listen_cb
            M._listen_cb = nil
            local mods = mods_from(ctrl)
            cb(KeyboardBinding.new(key, mods.ctrl, mods.shift, mods.alt))
        end
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

    -- Owned-overlay routing: an action carrying an overlay command drives the
    -- key graph, and the engine never sees the key. engaged() also covers a
    -- "pending" (still settling) screen — there the tick is a no-op, which
    -- deliberately SWALLOWS the key rather than letting it leak to the engine
    -- and click whatever the game natively focused.
    if best.command and M.overlay_tick and M.dispatcher
        and (M.dispatcher.engaged and M.dispatcher.engaged() or M.dispatcher.captures()) then
        local c = best.command
        M.overlay_tick({ kind = c.kind, dir = c.dir, mods = mods })
        return true
    end

    if best.handler then
        pcall(best.handler, ctrl)
    elseif best.game_button then
        -- Transitional fallback for not-yet-owned screens (menus): emulate the
        -- gamepad button the engine routes by context.
        M.ensure_kb_nav(ctrl)
        ctrl:button_press(best.game_button)
        M._active[key] = best.game_button
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

-- Physical gamepad press (already G.button_mapping-resolved by the caller).
-- Same dispatch shape as on_key_down: overlay command when an overlay is
-- engaged, else a direct handler; anything unmapped (or a command with no
-- engaged overlay) returns false and the engine's native handling applies.
function M.on_pad_down(ctrl, button)
    -- Rebind capture: a gamepad press binds the action to that button (the
    -- callback receives { pad_button = ... } instead of a KeyboardBinding).
    if M._listen_cb then
        local cb = M._listen_cb
        M._listen_cb = nil
        M._pad_active[button] = true
        cb({ pad_button = button })
        return true
    end
    if ctrl and ctrl.text_input_hook then return false end
    local key = M.PAD_ACTIONS[button]
    local action = key and M.by_key[key]
    if not action then return false end
    if M.silence then pcall(M.silence) end
    if action.command and M.overlay_tick and M.dispatcher
        and (M.dispatcher.engaged and M.dispatcher.engaged() or M.dispatcher.captures()) then
        local c = action.command
        M.overlay_tick({ kind = c.kind, dir = c.dir, mods = {} })
        M._pad_active[button] = true
        return true
    end
    if action.handler then
        pcall(action.handler, ctrl)
        M._pad_active[button] = true
        return true
    end
    return false
end

function M.on_pad_up(button)
    if M._pad_active[button] then
        M._pad_active[button] = nil
        return true
    end
    return false
end

-- Right stick -> review buffers, mirroring Ctrl+arrows: up/down = next /
-- previous item, left/right = next / previous buffer. Polled per frame (the
-- stick is an axis pair, not buttons); edge-triggered on entering a direction
-- with hysteresis, so one flick = one step and centering re-arms it. The
-- keyboard-stub gamepad reports zero axes, so this is inert without a pad.
local PAD_AXIS_ACTIONS = {
    up = "buffer_next_item", down = "buffer_prev_item",
    right = "buffer_next", left = "buffer_prev",
}
local PRESS_AT, RELEASE_AT = 0.55, 0.35
local _stick_dir = nil

function M.update_pad_axes(ctrl)
    local pad = ctrl and ctrl.GAMEPAD and ctrl.GAMEPAD.object
    if not pad or not pad.getGamepadAxis then return end
    local ok, x, y = pcall(function()
        return pad:getGamepadAxis("rightx"), pad:getGamepadAxis("righty")
    end)
    if not ok then return end
    x, y = tonumber(x) or 0, tonumber(y) or 0

    local ax, ay = math.abs(x), math.abs(y)
    local mag = math.max(ax, ay)
    local dir
    if mag >= PRESS_AT then
        if ay >= ax then dir = (y < 0) and "up" or "down"
        else dir = (x < 0) and "left" or "right" end
    elseif mag < RELEASE_AT then
        dir = nil
    else
        dir = _stick_dir   -- hysteresis band: hold the current state
    end

    if dir ~= _stick_dir then
        _stick_dir = dir
        if dir then
            local action = M.by_key[PAD_AXIS_ACTIONS[dir]]
            if action and action.handler then
                if M.silence then pcall(M.silence) end
                pcall(action.handler, ctrl)
            end
        end
    end
end

-- Settings-menu rebind: capture the next keypress as a binding via cb(binding).
function M.start_listening(cb) M._listen_cb = cb end
function M.stop_listening() M._listen_cb = nil end

-- Restore every action's bindings (keyboard AND pad) to the defaults (keeps
-- the action list, so mod-only actions like the debug dump survive).
function M.reset_defaults()
    for _, a in ipairs(M.actions) do a:reset_to_default() end
    M.PAD_ACTIONS = {}
    for btn, key in pairs(DEFAULT_PAD_ACTIONS) do M.PAD_ACTIONS[btn] = key end
end

-- Register the default action set — keyboard-first, one key one meaning
-- (Brad's scheme): arrows move, Enter selects/activates, Space grabs (pick up
-- / place, distinct from select), Home/End jump to row ends, and dedicated
-- letters for the run actions (X play, C discard, S sell, U use). game_button
-- fallbacks remain ONLY for the not-yet-owned screens: nav/select/back drive
-- native menus, brackets switch menu tabs, Q/E/Tab reach the engine features
-- that are still game-driven. Escape is intentionally NOT bound — it falls
-- through to the game's native handler (options / exit-overlay).
function M.init()
    M.actions = {}
    M.by_key = {}
    M._active = {}
    local function reg(key, label, opts)
        local binds = {}
        for _, k in ipairs(opts.keys) do binds[#binds + 1] = KeyboardBinding.new(k) end
        M.register{ key = key, label_key = label, bindings = binds,
            command = opts.command, game_button = opts.game_button, handler = opts.handler }
    end
    reg("nav_up",    "INPUT.NAV_UP",    { keys = { "up" },    command = { kind = "move", dir = "up" },    game_button = "dpup" })
    reg("nav_down",  "INPUT.NAV_DOWN",  { keys = { "down" },  command = { kind = "move", dir = "down" },  game_button = "dpdown" })
    reg("nav_left",  "INPUT.NAV_LEFT",  { keys = { "left" },  command = { kind = "move", dir = "left" },  game_button = "dpleft" })
    reg("nav_right", "INPUT.NAV_RIGHT", { keys = { "right" }, command = { kind = "move", dir = "right" }, game_button = "dpright" })
    reg("row_start", "INPUT.ROW_START", { keys = { "home" },  command = { kind = "move_to_edge", dir = "left" } })
    reg("row_end",   "INPUT.ROW_END",   { keys = { "end" },   command = { kind = "move_to_edge", dir = "right" } })
    reg("select",    "INPUT.SELECT",    { keys = { "return", "kpenter" }, command = { kind = "confirm" }, game_button = "a" })
    reg("grab",      "INPUT.GRAB",      { keys = { "space" }, command = { kind = "grab" } })
    reg("back",      "INPUT.BACK",      { keys = { "backspace", "lshift", "rshift" }, game_button = "b" })
    reg("play_hand", "INPUT.PLAY_HAND", { keys = { "x" }, handler = function() local h = M.handlers.play_hand; if h then h() end end })
    reg("discard",   "INPUT.DISCARD",   { keys = { "c" }, handler = function() local h = M.handlers.discard; if h then h() end end })
    reg("sell",      "INPUT.SELL",      { keys = { "s" }, command = { kind = "sell" } })
    reg("use",       "INPUT.USE",       { keys = { "u" }, command = { kind = "use" } })
    reg("tab_left",  "INPUT.TAB_LEFT",  { keys = { "[" }, game_button = "leftshoulder" })
    reg("tab_right", "INPUT.TAB_RIGHT", { keys = { "]" }, game_button = "rightshoulder" })
    reg("view_deck", "INPUT.VIEW_DECK", { keys = { "q" }, game_button = "triggerleft" })
    reg("right_trigger", "INPUT.RIGHT_TRIGGER", { keys = { "e" }, game_button = "triggerright" })
    reg("run_info",  "INPUT.RUN_INFO",  { keys = { "tab" }, game_button = "back" })

    M.PAD_ACTIONS = {}
    for btn, key in pairs(DEFAULT_PAD_ACTIONS) do M.PAD_ACTIONS[btn] = key end
end

-- ---- Persistence of rebound keys (blindfold_keybinds.lua in the save dir) ----
local function ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "boolean" or t == "number" then return tostring(v)
    elseif t == "table" then
        local parts, arr = {}, #v > 0
        for k, val in pairs(v) do
            if arr and type(k) == "number" then parts[#parts + 1] = ser(val)
            else parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(val) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

-- Keymap-format version: bump when the default scheme changes meaning so that
-- stale rebinds don't resurrect old semantics (e.g. Space was "select" in v1,
-- "grab" in v2 — a v1 save would shadow the new grab action).
local BINDS_VERSION = 2

function M.save_bindings()
    local map = {}
    for _, a in ipairs(M.actions) do
        local binds = {}
        for _, b in ipairs(a.bindings) do
            binds[#binds + 1] = { key = b.key, ctrl = b.ctrl, shift = b.shift, alt = b.alt }
        end
        map[a.key] = binds
    end
    -- Pad map saved per ACTION (action -> button), matching the keyboard
    -- shape; rebuilt into the button -> action runtime map on load.
    local pad = {}
    for btn, key in pairs(M.PAD_ACTIONS) do pad[key] = btn end
    pcall(function()
        love.filesystem.write("blindfold_keybinds.lua",
            "return " .. ser({ v = BINDS_VERSION, map = map, pad = pad }))
    end)
end

function M.load_bindings()
    pcall(function()
        local data = love.filesystem.read("blindfold_keybinds.lua")
        if not data then return end
        local chunk = load(data, "@blindfold_keybinds.lua")
        local t = chunk and chunk()
        -- Older formats (v1 was a bare map) are discarded: defaults win.
        if type(t) ~= "table" or t.v ~= BINDS_VERSION or type(t.map) ~= "table" then return end
        for _, a in ipairs(M.actions) do
            local saved = t.map[a.key]
            if type(saved) == "table" then
                a.bindings = {}
                for _, b in ipairs(saved) do
                    if type(b) == "table" and type(b.key) == "string" then
                        a.bindings[#a.bindings + 1] = KeyboardBinding.new(b.key, b.ctrl, b.shift, b.alt)
                    end
                end
            end
        end
        -- Pad rebinds, applied over the defaults (a save without `pad` — from
        -- before controller support — keeps the default scheme).
        if type(t.pad) == "table" then
            for key, btn in pairs(t.pad) do
                if M.by_key[key] and type(btn) == "string" then
                    apply_pad_binding(key, btn)
                end
            end
        end
    end)
end

return M
