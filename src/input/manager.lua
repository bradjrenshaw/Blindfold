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

-- Settings-menu rebind: capture the next keypress as a binding via cb(binding).
function M.start_listening(cb) M._listen_cb = cb end
function M.stop_listening() M._listen_cb = nil end

-- Restore every action's bindings to its defaults (keeps the action list, so
-- mod-only actions like the debug dump survive).
function M.reset_defaults()
    for _, a in ipairs(M.actions) do a:reset_to_default() end
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
    pcall(function()
        love.filesystem.write("blindfold_keybinds.lua",
            "return " .. ser({ v = BINDS_VERSION, map = map }))
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
    end)
end

return M
