-- core.lua — Blindfold entry point (Lovely-only Balatro screen-reader mod).
--
-- Registered as a Lovely module and required once from Game:start_up, right
-- after the Controller is created. The top-level chunk runs once and installs
-- the hooks. Everything is pcall-guarded so a failure logs instead of crashing
-- the game.

local speech = require("blindfold_speech")

local BA = { _installed = false }
_G.Blindfold = BA   -- expose for the in-game console / debugging

local MOD_DIR = love.filesystem.getSaveDirectory() .. "/Mods/Blindfold"

-- ---------------------------------------------------------------------------
-- Module loader — Balatro's `require` is sandboxed to the game's own files, so
-- the mod's multi-file Lua tree (ui/*) is loaded here from the mod folder
-- directly. ba_require("ui.foo") reads <mod>/ui/foo.lua, runs it once (passing
-- itself in as `...` so modules can require siblings), and caches the result.
-- ---------------------------------------------------------------------------
local _loaded = {}
local function read_mod_file(rel)
    local contents = love.filesystem.read("Mods/Blindfold/" .. rel)
    if contents then return contents end
    local f = io.open(MOD_DIR .. "/" .. rel, "rb")
    if f then local d = f:read("*a"); f:close(); return d end
    return nil
end
local function ba_require(name)
    if _loaded[name] ~= nil then return _loaded[name] end
    local rel = name:gsub("%.", "/") .. ".lua"
    local code = read_mod_file(rel)
    if not code then error("ba_require: cannot read " .. rel, 2) end
    local chunk, lerr = load(code, "@blindfold/" .. rel)
    if not chunk then error("ba_require: load error in " .. rel .. ": " .. tostring(lerr), 2) end
    _loaded[name] = true                 -- break require cycles
    _loaded[name] = chunk(ba_require) or true
    return _loaded[name]
end
BA.require = ba_require

-- Load the UI module tree defensively: this require runs inside Game:start_up,
-- so a syntax error in any ui/*.lua must not crash the game. On failure we log
-- and describe_focus stays silent.
local Factory, Input
do
    local ok, lerr = pcall(function()
        local Message = ba_require("ui.message")
        BA.loc = ba_require("loc.manager")
        BA.loc.init(G and G.SETTINGS and G.SETTINGS.language)
        Message.set_resolver(BA.loc.get)
        Factory = ba_require("ui.factory")

        Input = ba_require("input.manager")
        Input.init()
        Input.silence = speech.silence
        Input.register{ key = "dump_focus", label_key = "INPUT.DEBUG_DUMP",
            handler = function() BA.dump_focus() end,
            bindings = { Input.KeyboardBinding.new("f8") } }
        BA.input = Input
    end)
    if not ok then speech.log("Mod modules failed to load: " .. tostring(lerr)) end
end

-- ---------------------------------------------------------------------------
-- Focus -> spoken text. Builds the proxy for the focused node and composes its
-- announcements (label, type, status, ...). Returns "" when there's nothing
-- meaningful to say so the caller stays silent.
-- ---------------------------------------------------------------------------
function BA.describe_focus(node)
    if not Factory then return "" end
    local proxy = Factory.create(node)
    if not proxy then return "" end
    local m = proxy:get_focus_message()
    return m and m:resolve() or ""
end

-- ---------------------------------------------------------------------------
-- Per-frame focus tick: announce on focus change, then poll the focused
-- control's value and announce it when it changes (slider / cycle / checkbox /
-- tab). Balatro's UI has no change events, so we detect changes by polling.
-- ---------------------------------------------------------------------------
local _focus_node, _focus_proxy, _last_value, _deferred_done
function BA.focus_tick(ctrl)
    local t = ctrl and ctrl.focused and ctrl.focused.target
    if t ~= _focus_node then
        _focus_node, _focus_proxy, _last_value, _deferred_done = t, nil, nil, false
        if t and not t.REMOVED and Factory then
            _focus_proxy = Factory.create(t)
            if _focus_proxy then
                local m = _focus_proxy:get_focus_message()
                local s = m and m:resolve() or ""
                if s ~= "" then speech.say(s) end
                _last_value = _focus_proxy:poll_value()
            end
        end
    elseif _focus_proxy then
        local v = _focus_proxy:poll_value()
        if v ~= nil and v ~= _last_value then
            _last_value = v
            local m = _focus_proxy:get_value_message()
            local s = m and m:resolve() or ""
            -- Silence first so held / rapid value changes replace rather than
            -- queue (matches SayTheSpire2's silence-on-change behavior).
            if s ~= "" then speech.silence(); speech.say(s) end
        end
        -- Deferred follow-up (e.g. a card's description, which the game only
        -- populates one frame after focus). Spoken once, WITHOUT silencing, so
        -- it follows the name instead of replacing it.
        if not _deferred_done then
            local m = _focus_proxy:get_deferred()
            local s = m and m:resolve() or ""
            if s ~= "" then speech.say(s); _deferred_done = true end
        end
    end
end

-- Debug: dump the focused node's UI subtree to the log via the engine's own
-- print_topology, so we can see a control's exact structure while tuning proxies.
function BA.dump_focus()
    local node = G and G.CONTROLLER and G.CONTROLLER.focused and G.CONTROLLER.focused.target
    if node and node.print_topology then
        speech.log("FOCUS TOPOLOGY:" .. tostring(node:print_topology(0)))
    else
        speech.log("dump_focus: no focused UIElement")
    end
end

-- ---------------------------------------------------------------------------
-- Keyboard handling lives in the InputAction layer (input/manager.lua): it maps
-- keys to the gamepad buttons the engine already navigates with (the release
-- build disables the keyboard->gamepad path), and the engine routes them by
-- context. The hooks below just forward to it.
-- ---------------------------------------------------------------------------
function BA.install()
    if BA._installed then return end
    BA._installed = true

    -- 1) Announce focus changes + reactive value changes, once per frame.
    local orig_update_focus = Controller.update_focus
    function Controller:update_focus(dir)
        orig_update_focus(self, dir)
        pcall(BA.focus_tick, self)
    end

    -- 2) Drive the engine from the keyboard via the InputAction layer.
    local orig_key_press = Controller.key_press
    function Controller:key_press(key)
        if Input then
            local ok, consumed = pcall(Input.on_key_down, self, key)
            if ok and consumed then return end
        end
        return orig_key_press(self, key)
    end

    local orig_key_release = Controller.key_release
    function Controller:key_release(key)
        if Input then
            local ok, consumed = pcall(Input.on_key_up, self, key)
            if ok and consumed then return end
        end
        return orig_key_release(self, key)
    end

    -- 3) Once keyboard nav is active, refuse to fall back to mouse/touch mode.
    --    Otherwise any mouse movement (or a non-nav keypress, which the release
    --    build forces into mouse mode) snaps the game cursor to the physical
    --    mouse, the focused node stops colliding, and focus is lost.
    local orig_set_HID = Controller.set_HID_flags
    function Controller:set_HID_flags(HID_type, button)
        if Input and Input.lock_focus_mode and Input.kb_active
           and (HID_type == "mouse" or HID_type == "touch" or HID_type == "axis_cursor") then
            HID_type = "button"
        end
        return orig_set_HID(self, HID_type, button)
    end

    -- 4) Keep mod localization in sync when the player changes game language.
    if Game and Game.set_language then
        local orig_set_language = Game.set_language
        function Game:set_language()
            orig_set_language(self)
            if BA.loc then
                pcall(function() BA.loc.set_language(G.SETTINGS and G.SETTINGS.language) end)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
local ok, err = pcall(function()
    speech.init(MOD_DIR)
    BA.install()
    speech.say("Blindfold loaded.")
end)
if not ok then
    pcall(function()
        love.filesystem.append("blindfold.log", "FATAL during boot: " .. tostring(err) .. "\n")
    end)
end

return BA
