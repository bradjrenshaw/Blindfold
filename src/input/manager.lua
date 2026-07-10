-- input/manager.lua — the InputAction registry + keyboard dispatch (port of
-- SayTheSpire2's InputManager). Keyboard keys are translated to the gamepad
-- buttons the engine already navigates with; the engine routes them by context
-- (registry / capture_focused_input), so we never special-case screens.
--
-- Designed for a later rebinding settings menu: actions carry labels + default
-- bindings, and start_listening/stop_listening capture a new binding.
local require = ...
local Message = require("ui.message")
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
-- actions, mirroring the keyboard defaults. Composite "trigger+button" keys
-- are CHORDS: the button pressed while that trigger is held (LT layer =
-- current-blind readouts, RT layer = run-persistent ones, mirroring the
-- keyboard's Ctrl combos). TOTAL OWNERSHIP (Brad): NOTHING falls through to
-- the engine — unmapped buttons are swallowed; the engine behaviors we keep
-- (B = back/deselect, Start = pause) are actions whose game_button the mod
-- presses DELIBERATELY.
local DEFAULT_PAD_ACTIONS = {
    dpup = "nav_up", dpdown = "nav_down", dpleft = "nav_left", dpright = "nav_right",
    a = "select",
    b = "back",
    x = "play_hand",
    y = "discard",
    leftshoulder = "sell",
    rightshoulder = "use",
    start = "pause",
    back = "run_info",
    ["triggerleft+a"] = "grab",   -- left stick click was awful (Brad)
    ["triggerleft+x"] = "info_hands",
    ["triggerleft+y"] = "info_discards",
    ["triggerleft+b"] = "info_score",
    ["triggerleft+leftshoulder"] = "run_info",
    ["triggerright+x"] = "info_money",
    ["triggerright+y"] = "info_jokers",
    ["triggerright+rightshoulder"] = "view_deck",
}
M.PAD_ACTIONS = {}   -- the live (rebindable, persisted) map; filled in init

-- Spoken names live in loc PAD.* (keyed by the uppercased button name).
local PAD_KEYS = {
    dpup = true, dpdown = true, dpleft = true, dpright = true,
    a = true, b = true, x = true, y = true,
    leftshoulder = true, rightshoulder = true,
    leftstick = true, rightstick = true,
    back = true, start = true, guide = true,
    triggerleft = true, triggerright = true,
}
function M.pad_display(button)
    local mod, btn = tostring(button):match("^(trigger%a+)%+(.+)$")
    if mod then
        return Message.localized("PAD.CHORD",
            { mod = M.pad_display(mod), button = M.pad_display(btn) }):resolve()
    end
    if PAD_KEYS[button] then
        return Message.localized("PAD." .. string.upper(button)):resolve()
    end
    return tostring(button)
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

-- Trigger held-state (they're axes, polled in update_triggers below). Lives
-- up here because on_pad_down consults it for chord dispatch.
local _trig_down = {}
local function held_trigger()
    return (_trig_down.triggerleft and "triggerleft")
        or (_trig_down.triggerright and "triggerright") or nil
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
    -- Held triggers fold in like keyboard modifiers: trigger + button binds
    -- the chord; a trigger pressed and released alone binds bare (the bind
    -- happens on its release, in on_pad_up).
    if M._listen_cb then
        if button == "triggerleft" or button == "triggerright" then return true end
        local cb = M._listen_cb
        M._listen_cb = nil
        M._pad_active[button] = true
        local mod = held_trigger()
        cb({ pad_button = mod and (mod .. "+" .. button) or button })
        return true
    end
    if ctrl and ctrl.text_input_hook then return false end
    -- A held trigger's chord layer wins; fall back to the bare button so a
    -- half-pulled trigger doesn't dead-zone the unchorded actions.
    local mod = held_trigger()
    local key = (mod and M.PAD_ACTIONS[mod .. "+" .. button]) or M.PAD_ACTIONS[button]
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
    if action.game_button then
        -- Deliberate engine behavior (B = back/deselect, Start = pause): the
        -- physical press was swallowed; press the engine button ourselves and
        -- forward the release symmetrically (stored as the string).
        if ctrl then pcall(ctrl.button_press, ctrl, action.game_button) end
        M._pad_active[button] = action.game_button
        return true
    end
    return false
end

function M.on_pad_up(button, ctrl)
    -- Rebind capture: a trigger that comes back up with the capture still
    -- live was pressed alone — bind it bare.
    if M._listen_cb and (button == "triggerleft" or button == "triggerright") then
        local cb = M._listen_cb
        M._listen_cb = nil
        cb({ pad_button = button })
        return true
    end
    local held = M._pad_active[button]
    if held then
        M._pad_active[button] = nil
        if type(held) == "string" and ctrl then
            pcall(ctrl.button_release, ctrl, held)
        end
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

-- Triggers, polled into the normal pad pipeline (they're axes — the engine
-- converts them itself in handle_axis_buttons, which core blanks entirely).
-- Thresholds match the engine's own (press .5, release .3). ALL trigger
-- presses feed through — total ownership; an unmapped trigger just no-ops.
local function update_triggers(ctrl, pad)
    for _, name in ipairs({ "triggerleft", "triggerright" }) do
        local ok, v = pcall(pad.getGamepadAxis, pad, name)
        v = ok and tonumber(v) or 0
        if not _trig_down[name] and v > 0.5 then
            _trig_down[name] = true
            M.on_pad_down(ctrl, name)
        elseif _trig_down[name] and v < 0.3 then
            _trig_down[name] = nil
            M.on_pad_up(name, ctrl)
        end
    end
end

-- Left stick -> navigation flicks (the engine's own stick-to-dpad conversion
-- is blanked by core along with the triggers). Same edge-trigger/hysteresis
-- as the right stick: one flick = one step, centering re-arms.
local NAV_AXIS_ACTIONS = {
    up = "nav_up", down = "nav_down", left = "nav_left", right = "nav_right",
}
local _lstick_dir = nil
local function update_left_stick(ctrl, pad)
    local ok, x, y = pcall(function()
        return pad:getGamepadAxis("leftx"), pad:getGamepadAxis("lefty")
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
        dir = _lstick_dir
    end
    if dir ~= _lstick_dir then
        _lstick_dir = dir
        if dir then
            local action = M.by_key[NAV_AXIS_ACTIONS[dir]]
            if action and action.command and M.overlay_tick and M.dispatcher
                and (M.dispatcher.engaged and M.dispatcher.engaged() or M.dispatcher.captures()) then
                if M.silence then pcall(M.silence) end
                local c = action.command
                M.overlay_tick({ kind = c.kind, dir = c.dir, mods = {} })
            end
        end
    end
end

function M.update_pad_axes(ctrl)
    local pad = ctrl and ctrl.GAMEPAD and ctrl.GAMEPAD.object
    if not pad or not pad.getGamepadAxis then return end
    update_triggers(ctrl, pad)
    update_left_stick(ctrl, pad)
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
    -- Pause has no keyboard default (Escape stays native, deliberately
    -- unbound); on pad it owns the Start button's engine behavior.
    reg("pause",     "INPUT.PAUSE",     { keys = {}, game_button = "start" })
    reg("play_hand", "INPUT.PLAY_HAND", { keys = { "x" }, handler = function() local h = M.handlers.play_hand; if h then h() end end })
    reg("discard",   "INPUT.DISCARD",   { keys = { "c" }, handler = function() local h = M.handlers.discard; if h then h() end end })
    reg("sell",      "INPUT.SELL",      { keys = { "s" }, command = { kind = "sell" } })
    reg("use",       "INPUT.USE",       { keys = { "u" }, command = { kind = "use" } })
    reg("tab_left",  "INPUT.TAB_LEFT",  { keys = { "[" }, game_button = "leftshoulder" })
    reg("tab_right", "INPUT.TAB_RIGHT", { keys = { "]" }, game_button = "rightshoulder" })
    -- View Deck / Run Info are OWNED actions (handlers injected by core call
    -- the game FUNCS directly — the old triggerleft fallback never opened the
    -- deck view at all: natively that trigger is the visual-only hold-to-peek
    -- deck preview). Pad access rides the trigger chords in
    -- DEFAULT_PAD_ACTIONS (RT+RB deck, LT+LB run info).
    reg("view_deck", "INPUT.VIEW_DECK", { keys = { "d" },
        handler = function() local h = M.handlers.view_deck; if h then h() end end })
    reg("run_info",  "INPUT.RUN_INFO",  { keys = { "tab" },
        handler = function() local h = M.handlers.run_info; if h then h() end end })

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
-- "grab" in v2 — a v1 save would shadow the new grab action; v3 moved View
-- Deck from Q to D and dropped the passthrough right_trigger action).
local BINDS_VERSION = 3

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
