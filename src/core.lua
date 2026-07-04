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
local Factory, Input, Scoring, Containers, Screens, FocusBuffers, Overlays
do
    local ok, lerr = pcall(function()
        local Message = ba_require("ui.message")
        BA.loc = ba_require("loc.manager")
        BA.loc.init(G and G.SETTINGS and G.SETTINGS.language)
        Message.set_resolver(BA.loc.get)
        Factory = ba_require("ui.factory")
        Containers = ba_require("ui.containers")
        BA.containers = Containers
        Screens = ba_require("ui.screens")
        Screens.say = speech.say
        Screens.containers = Containers
        BA.screens = Screens

        Input = ba_require("input.manager")
        Input.init()
        Input.silence = speech.silence
        Input.register{ key = "dump_focus", label_key = "INPUT.DEBUG_DUMP",
            handler = function() BA.dump_focus() end,
            bindings = { Input.KeyboardBinding.new("f8") } }
        BA.input = Input

        -- Buffers: browsable review cursors over game state (Ctrl + arrows).
        local Buffers = ba_require("buffers.manager")
        Buffers.say = speech.say
        Buffers.add(ba_require("buffers.game"))
        -- Focus buffers: per-kind review of the focused element's detail
        -- (description + keyword tips), bound on focus in BA.focus_tick.
        FocusBuffers = ba_require("buffers.focus")
        Buffers.add(FocusBuffers.card)
        Buffers.add(FocusBuffers.joker)
        Buffers.add(FocusBuffers.consumable)
        Buffers.add(FocusBuffers.cashout)
        Buffers.add(FocusBuffers.ui)
        BA.focus_buffers = FocusBuffers
        BA.buffers = Buffers
        local kb = Input.KeyboardBinding
        Input.register{ key = "buffer_next_item", label_key = "INPUT.BUFFER_NEXT_ITEM",
            handler = function() Buffers.next_item() end, bindings = { kb.new("up", true) } }
        Input.register{ key = "buffer_prev_item", label_key = "INPUT.BUFFER_PREV_ITEM",
            handler = function() Buffers.prev_item() end, bindings = { kb.new("down", true) } }
        Input.register{ key = "buffer_next", label_key = "INPUT.BUFFER_NEXT",
            handler = function() Buffers.next_buffer() end, bindings = { kb.new("right", true) } }
        Input.register{ key = "buffer_prev", label_key = "INPUT.BUFFER_PREV",
            handler = function() Buffers.prev_buffer() end, bindings = { kb.new("left", true) } }

        -- Owned-UI overlay layer (port of Tanglebeep's key-graph framework):
        -- screens we own re-present live game state as a navigable graph; every
        -- other screen stays on the legacy focus-follower below.
        Overlays = ba_require("overlay.dispatcher")
        local PlayOverlay = ba_require("overlays.play")
        Overlays.register(PlayOverlay)
        Overlays.register(ba_require("overlays.blinds"))
        Overlays.register(ba_require("overlays.shop"))
        -- Packs must sit ABOVE the shop: during pack states the shop reports
        -- "sleeping" (position preserved), which would win the stack scan if it
        -- were higher.
        Overlays.register(ba_require("overlays.packs"))
        Overlays.register(ba_require("overlays.cashout"))
        -- Menu overlays (registered above play, so an open menu wins while the
        -- play screen sleeps underneath with its position intact): the bespoke
        -- main menu (spatial rows) and the generic mirror for every modal menu.
        local Mirror = ba_require("overlays.menu_mirror")
        Overlays.register(ba_require("overlays.main_menu"))
        Overlays.register(Mirror.overlay)
        -- End-of-run screens (game over / win): above the mirror, since both
        -- are overlay menus the mirror would otherwise claim (buttons only —
        -- the run summary rows aren't focusable controls).
        Overlays.register(ba_require("overlays.game_over"))
        BA.overlays = Overlays
        Input.dispatcher = Overlays
        Input.overlay_tick = function(cmd)
            local ok, res = pcall(Overlays.tick, cmd)
            if ok then
                BA.speak_overlay_result(res)
            else
                speech.log("overlay tick error: " .. tostring(res))
            end
        end
        -- Direct-call actions (X / C): the guarded play/discard logic shared
        -- with the play overlay's button row. Feedback for a fired action comes
        -- from the round/scoring hooks; errors are spoken here.
        local function direct(fn)
            return function()
                local ok, err = pcall(fn)
                if ok and err then speech.say(Message.localized(err):resolve()) end
            end
        end
        Input.handlers.play_hand = direct(PlayOverlay.do_play)
        Input.handlers.discard = direct(PlayOverlay.do_discard)

        Scoring = ba_require("events.scoring")
        Scoring.say = speech.say
        BA.scoring = Scoring

        -- Round actions: speak plays / discards (and how many remain).
        local Round = ba_require("events.round")
        Round.say = speech.say
        BA.round = Round

        -- Cash-out: accumulate the end-of-round money breakdown (browsable on
        -- the cash-out overlay / buffer) and speak each row as it animates in.
        BA.cashout = ba_require("events.cashout")
        BA.cashout.say = speech.say

        -- Settings: registry + the native "Blindfold" tab in the Options screen.
        local Settings = ba_require("settings.registry")
        Settings.register{ key = "scoring.enabled",      type = "bool",   label_key = "SET.SCORING_ENABLED", default = true,   category = "scoring" }
        Settings.register{ key = "scoring.hand_preview", type = "bool",   label_key = "SET.HAND_PREVIEW",    default = true,   category = "scoring" }
        Settings.register{ key = "scoring.detail",       type = "choice", label_key = "SET.SCORING_DETAIL",  default = "full", category = "scoring",
            options = { "full", "jokers", "summary" },
            labels  = { "SET.DETAIL_FULL", "SET.DETAIL_JOKERS", "SET.DETAIL_SUMMARY" } }
        Settings.register{ key = "round.actions",        type = "bool",   label_key = "SET.ROUND_ACTIONS",   default = true,   category = "scoring" }
        -- Per-announcement toggles (read by announce.Context / proxy descriptions).
        Settings.register{ key = "announce.type.enabled",        type = "bool", label_key = "SET.ANN_TYPE",        default = true, category = "announce" }
        Settings.register{ key = "announce.subtype.enabled",     type = "bool", label_key = "SET.ANN_SUBTYPE",     default = true, category = "announce" }
        Settings.register{ key = "announce.selected.enabled",    type = "bool", label_key = "SET.ANN_SELECTED",    default = true, category = "announce" }
        Settings.register{ key = "announce.description.enabled", type = "bool", label_key = "SET.ANN_DESCRIPTION", default = true, category = "announce" }
        Settings.register{ key = "announce.tooltip.enabled",     type = "bool", label_key = "SET.ANN_TOOLTIP",     default = true, category = "announce" }
        Settings.register{ key = "announce.extras.enabled",      type = "bool", label_key = "SET.ANN_EXTRAS",      default = true, category = "announce" }
        Settings.register{ key = "announce.position.enabled",    type = "bool", label_key = "SET.ANN_POSITION",    default = true, category = "announce" }
        Settings.register{ key = "announce.container.enabled",   type = "bool", label_key = "SET.ANN_CONTAINER",   default = true, category = "announce" }
        Settings.register{ key = "announce.screen.enabled",      type = "bool", label_key = "SET.ANN_SCREEN",      default = true, category = "announce" }
        Settings.load()
        BA.settings = Settings
        Scoring.settings = Settings
        Round.settings = Settings

        local Menu = ba_require("settings.menu")
        BA.settings_tab = Menu.settings_tab   -- referenced by the Options-tab patch

        -- Choice (cycle) controls route their callback through here.
        G.FUNCS.blindfold_cycle = function(a)
            local key = a and a.cycle_config and a.cycle_config.blindfold_key
            local s = key and Settings.by_key[key]
            if s and a.to_key and s.options then Settings.on_change(key, s.options[a.to_key]) end
        end

        -- Keybindings sub-screen + rebind capture. Tag the overlay so the screen
        -- tracker names it directly instead of scraping a title.
        G.FUNCS.blindfold_keybinds = function()
            G.FUNCS.overlay_menu{ definition = Menu.keybinds_uibox() }
            if type(G.OVERLAY_MENU) == "table" then G.OVERLAY_MENU.blindfold_title_key = "SET.KEYBINDS" end
        end
        G.FUNCS.blindfold_announcements = function()
            G.FUNCS.overlay_menu{ definition = Menu.announcements_uibox() }
            if type(G.OVERLAY_MENU) == "table" then G.OVERLAY_MENU.blindfold_title_key = "SET.ANNOUNCEMENTS" end
        end
        G.FUNCS.blindfold_rebind = function(e)
            local key = e and e.config and e.config.ref_table and e.config.ref_table.blindfold_action
            local action = key and Input.find(key)
            if not action then return end
            local label = (action.label_key and Message.localized(action.label_key):resolve()) or action.key
            speech.say(Message.localized("SET.PRESS_KEY", { action = label }):resolve())
            Input.start_listening(function(binding)
                if binding.key == "escape" then
                    speech.say(Message.localized("SET.CANCELLED"):resolve())
                else
                    action.bindings = { binding }
                    Input.save_bindings()
                    speech.say(Message.localized("SET.BOUND", { action = label, key = binding:display() }):resolve())
                end
                -- Rebuild the screen (deferred out of the input event).
                G.E_MANAGER:add_event(Event({ blocking = false, blockable = false,
                    func = function() G.FUNCS.blindfold_keybinds(); return true end }))
            end)
        end

        Input.load_bindings()   -- apply saved rebinds over the defaults
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
-- Owned-overlay output: speak a dispatcher tick's result and sync what follows
-- focus. Mirrors the legacy focus path: label first, then (for cards) the
-- deferred description + position follow-up, queued so it trails the label;
-- the focused card also binds into its review buffer.
-- ---------------------------------------------------------------------------
function BA.speak_overlay_result(res)
    if not res then return end
    if res.message and res.message ~= "" then speech.say(res.message) end
    -- Any focused backing object — a Card OR a UIElement — binds into its
    -- review buffer; and whenever the node's LABEL was what got spoken (a
    -- move, an edge bump, a fallback re-read — res.spoke_label), the deferred
    -- follow-up (description / position / a cycle's effect text) is queued
    -- after it, exactly like the legacy focus path. Keying on spoke_label
    -- keeps every label announcement identical regardless of which key
    -- produced it.
    local ref = res.focus_ref
    if ref and type(ref) == "table" then
        if FocusBuffers then pcall(FocusBuffers.bind_focus, ref) end
        if res.spoke_label and res.message and res.message ~= "" then
            pcall(function()
                local m
                if res.deferred then
                    -- The node's own deferred (e.g. row-relative position).
                    m = res.deferred()
                elseif Factory then
                    local proxy = Factory.create(ref)
                    m = proxy and proxy.get_deferred and proxy:get_deferred()
                end
                local s = type(m) == "string" and m or (m and m.resolve and m:resolve()) or ""
                if s ~= "" then speech.say(s) end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Per-frame tick: screen-change detection, then the owned-overlay dispatcher
-- (open/close detection, focus reconciliation, and any focus change the graph
-- made on its own — a fresh open, or the focused control vanishing).
--
-- The legacy native-focus follower is GONE: every screen is either an owned
-- overlay or (until its overlay is written: shop, blind select, packs, cash
-- out, game over) navigable-but-quiet via the gamepad-emulation fallback, with
-- the event announcements and review buffers still speaking. Following the
-- game's focus meant narrating its internal snap churn during transitions.
-- ---------------------------------------------------------------------------
function BA.focus_tick(ctrl)
    if Screens then pcall(Screens.tick) end
    if Overlays then
        local ok, res = pcall(Overlays.tick)
        if ok then
            BA.speak_overlay_result(res)
        else
            speech.log("overlay tick error: " .. tostring(res))
        end
    end
end

-- Debug: dump the focused node's UI subtree to the log via the engine's own
-- print_topology, so we can see a control's exact structure while tuning
-- proxies. When an owned overlay is active, dump its graph (nodes in traversal
-- order, labels, cursor, links) instead.
function BA.dump_focus()
    if Overlays then
        local ok, desc = pcall(Overlays.describe)
        speech.log("OVERLAY:\n" .. tostring(ok and desc or desc))
        -- Gate diagnostics: every buttoned node in the open game overlay with
        -- the states our focusability gates read — for finding controls the
        -- walk rejected (or never reached).
        if type(G.OVERLAY_MENU) == "table" and G.OVERLAY_MENU.UIRoot then
            pcall(function()
                local function dump(n, d)
                    if type(n) ~= "table" or d > 30 then return end
                    local c = n.config
                    if c and c.button then
                        speech.log(string.format("  BTN %-28s vis=%s hover=%s removed=%s",
                            tostring(c.button),
                            tostring(n.states and n.states.visible),
                            tostring(n.states and n.states.hover and n.states.hover.can),
                            tostring(n.REMOVED)))
                    end
                    if n.children then
                        for _, ch in pairs(n.children) do dump(ch, d + 1) end
                    end
                end
                dump(G.OVERLAY_MENU.UIRoot, 0)
            end)
        end
        if ok and desc ~= "overlay: none" then return end
    end
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

    -- 5) Announce the hand-scoring sequence (and other floating chips / mult /
    --    joker feedback) by wrapping the two functions that produce it. These
    --    fire as timed events, so the spoken sequence follows the animation.
    if Scoring then
        if card_eval_status_text then
            local orig_status = card_eval_status_text
            function card_eval_status_text(card, eval_type, amt, percent, dir, extra)
                -- Speech BEFORE the original: both queue onto the sequential
                -- base event queue, and 'before' events run their func the
                -- moment they reach the queue front, holding the queue for
                -- their delay AFTERWARD (event.lua:92). Queued this way, the
                -- utterance fires in the same beat as its popup; queued after,
                -- it would land one popup late.
                pcall(Scoring.on_status, card, eval_type, amt, extra)
                orig_status(card, eval_type, amt, percent, dir, extra)
            end
        end
        if update_hand_text then
            local orig_hand = update_hand_text
            function update_hand_text(config, vals)
                orig_hand(config, vals)
                pcall(Scoring.on_hand_text, config, vals)
            end
        end
    end

    -- 6) Announce play / discard actions with the hands / discards remaining, by
    --    wrapping the two FUNCS the play/discard buttons invoke.
    if BA.round and G and G.FUNCS then
        local Round = BA.round
        if G.FUNCS.play_cards_from_highlighted then
            local orig_play = G.FUNCS.play_cards_from_highlighted
            G.FUNCS.play_cards_from_highlighted = function(e)
                orig_play(e)
                pcall(Round.on_play)
            end
        end
        if G.FUNCS.discard_cards_from_highlighted then
            local orig_discard = G.FUNCS.discard_cards_from_highlighted
            G.FUNCS.discard_cards_from_highlighted = function(e, hook)
                orig_discard(e, hook)
                pcall(Round.on_discard, hook)
            end
        end
    end

    -- 7) Record the end-of-round money breakdown (read by ProxyCashOut) by
    --    wrapping the global that builds each cash-out row.
    if BA.cashout and add_round_eval_row then
        local Cashout = BA.cashout
        local orig_row = add_round_eval_row
        function add_round_eval_row(config)
            pcall(Cashout.on_row, config)
            return orig_row(config)
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
