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
local Factory, Input, Scoring, Containers, Screens, FocusBuffers, Overlays, Events
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

        -- Run events (tags firing, cards created/destroyed, resource deltas):
        -- hooks in BA.install emit through the dispatcher; its history buffer
        -- joins the review cycle.
        Events = ba_require("events.dispatcher")
        Events.say = speech.say
        Buffers.add(Events.buffer)
        BA.events = Events
        local kb = Input.KeyboardBinding
        Input.register{ key = "buffer_next_item", label_key = "INPUT.BUFFER_NEXT_ITEM",
            handler = function() Buffers.next_item() end, bindings = { kb.new("up", true) } }
        Input.register{ key = "buffer_prev_item", label_key = "INPUT.BUFFER_PREV_ITEM",
            handler = function() Buffers.prev_item() end, bindings = { kb.new("down", true) } }
        Input.register{ key = "buffer_next", label_key = "INPUT.BUFFER_NEXT",
            handler = function() Buffers.next_buffer() end, bindings = { kb.new("right", true) } }
        Input.register{ key = "buffer_prev", label_key = "INPUT.BUFFER_PREV",
            handler = function() Buffers.prev_buffer() end, bindings = { kb.new("left", true) } }

        -- Status readouts: one-shot spoken values on Ctrl+letter; the default
        -- pad chords (LT/RT + face buttons) live in the input manager's
        -- DEFAULT_PAD_ACTIONS under these action keys.
        local Status = ba_require("status")
        Status.say = speech.say
        Input.register{ key = "info_hands", label_key = "INPUT.INFO_HANDS",
            handler = Status.hands, bindings = { kb.new("x", true) } }
        Input.register{ key = "info_discards", label_key = "INPUT.INFO_DISCARDS",
            handler = Status.discards, bindings = { kb.new("c", true) } }
        Input.register{ key = "info_score", label_key = "INPUT.INFO_SCORE",
            handler = Status.score, bindings = { kb.new("s", true) } }
        Input.register{ key = "info_jokers", label_key = "INPUT.INFO_JOKERS",
            handler = Status.jokers, bindings = { kb.new("j", true) } }
        Input.register{ key = "info_money", label_key = "INPUT.INFO_MONEY",
            handler = Status.money, bindings = { kb.new("m", true) } }

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
        -- Above the mirror: the poker-hands listing as a 2D table (run info
        -- tab + the standalone current-hands popup).
        Overlays.register(ba_require("overlays.run_hands"))
        -- The deck view is an overlay menu the mirror would otherwise claim;
        -- registered above it, the bespoke layout wins while G.VIEWING_DECK.
        Overlays.register(ba_require("overlays.deck_view"))
        -- Challenge list + description: two side-by-side columns that read
        -- bottom-heavy in the mirror's flat order; bespoke, description first.
        Overlays.register(ba_require("overlays.challenges"))
        -- Collection card screens: the game's grid rows (G.your_collection)
        -- become navigable rows instead of one long flat list.
        Overlays.register(ba_require("overlays.collection"))
        -- Blinds collection: sprite chips the mirror's collector can't reach.
        Overlays.register(ba_require("overlays.blind_gallery"))
        -- Stats screen (high-score rows are unreadable renders) and Card
        -- Stats (top-10 usage histograms whose counts were silent).
        Overlays.register(ba_require("overlays.stats"))
        Overlays.register(ba_require("overlays.card_stats"))
        -- Credits: tabbed text walls (tagged at open by the show_credits wrap).
        Overlays.register(ba_require("overlays.credits"))
        -- End-of-run screens (game over / win): above the mirror, since both
        -- are overlay menus the mirror would otherwise claim (buttons only —
        -- the run summary rows aren't focusable controls).
        Overlays.register(ba_require("overlays.game_over"))
        -- Tutorial (topmost): Jimbo's Next-button steps override whatever
        -- screen sits underneath; action-listening steps yield to it.
        Overlays.register(ba_require("overlays.tutorial"))
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
        -- View Deck / Run Info: direct FUNCS calls (both ignore their button
        -- arg) — deterministic on owned screens instead of riding the game's
        -- pip routing. Guarded to a live run with no menu already on top;
        -- run_info advances the tutorial's listen step exactly like the pip
        -- click used to.
        local function info_screen(func_key, listen)
            return function()
                if not (G and G.STAGES and G.STAGE == G.STAGES.RUN
                    and not G.OVERLAY_MENU and G.FUNCS and G.FUNCS[func_key]) then return end
                if listen then pcall(PlayOverlay.tut_listen, listen) end
                G.FUNCS[func_key]()
            end
        end
        Input.handlers.view_deck = info_screen("deck_info")
        Input.handlers.run_info = info_screen("run_info", "run_info")

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

        -- Per-effect verbosity formats (the Scoring submenu). Options are
        -- style ids; the cycle shows live examples rendered in the player's
        -- language ("+10 chips" / "+10c" / ...), so no per-option loc keys.
        -- Losses have their own style — vanilla never emits a negative
        -- chips/mult popup, but the renderer is signed either way.
        local function fmt_setting(key, label_key, kind, styles, default)
            local examples = {}
            for i, st in ipairs(styles) do
                local ok2, ex = pcall(Scoring.format_example, kind, st)
                examples[i] = ok2 and ex or st
            end
            Settings.register{ key = key, type = "choice", label_key = label_key,
                default = default, category = "scoring",
                options = styles, label_values = examples }
        end
        fmt_setting("scoring.fmt.chips_gain", "SET.FMT_CHIPS_GAIN", "chips_gain",
            { "signed_word", "signed", "word", "bare", "signed_abbr", "abbr" }, "signed_word")
        fmt_setting("scoring.fmt.chips_loss", "SET.FMT_CHIPS_LOSS", "chips_loss",
            { "signed_word", "signed_abbr", "signed" }, "signed_word")
        fmt_setting("scoring.fmt.mult_gain", "SET.FMT_MULT_GAIN", "mult_gain",
            { "signed_word", "signed_abbr", "abbr" }, "signed_word")
        -- No bare "-10" for mult: without the m/word it's indistinguishable
        -- from a chips line (Brad).
        fmt_setting("scoring.fmt.mult_loss", "SET.FMT_MULT_LOSS", "mult_loss",
            { "signed_word", "signed_abbr" }, "signed_word")
        fmt_setting("scoring.fmt.xmult", "SET.FMT_XMULT", "xmult",
            { "word", "x_abbr", "x" }, "word")
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
        Settings.register{ key = "announce.keywords.enabled",    type = "bool", label_key = "SET.ANN_KEYWORDS",    default = true, category = "announce" }
        Events.register_settings()   -- events.<group>.enabled toggles (same screen)

        -- Speech backend picker: "auto" plus whatever Prism says is usable on
        -- this machine. Product names (NVDA, JAWS...) are not translated —
        -- only the auto option carries a loc label. This block runs at module
        -- load, BEFORE speech.init, so the real options are filled in at boot
        -- (see the boot pcall) once prism has enumerated.
        Settings.register{ key = "speech.backend", type = "choice",
            label_key = "SET.SPEECH_BACKEND", default = "auto", category = "speech",
            options = { "auto" }, labels = { "SET.BACKEND_AUTO" },
            apply = function(v) speech.set_backend(v) end }

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
        G.FUNCS.blindfold_scoring = function()
            G.FUNCS.overlay_menu{ definition = Menu.scoring_uibox() }
            if type(G.OVERLAY_MENU) == "table" then G.OVERLAY_MENU.blindfold_title_key = "SET.SCORING" end
        end
        -- Bundled docs: README.md / changes.md, copied into <mod>/docs by
        -- deploy.ps1 and build_release.ps1, opened in the OS default handler.
        -- MOD_DIR already uses forward slashes (love save dir); encode spaces
        -- for the file URL (a username with a space, say).
        local function open_doc(rel, speak_key)
            local url = "file:///" .. (MOD_DIR .. "/docs/" .. rel):gsub(" ", "%%20")
            speech.say(Message.localized(speak_key):resolve())
            pcall(function() love.system.openURL(url) end)
        end
        G.FUNCS.blindfold_docs = function() open_doc("README.md", "SET.OPENING_DOCS") end
        G.FUNCS.blindfold_changes = function() open_doc("changes.md", "SET.OPENING_CHANGES") end
        -- Community links (the game opens its own links the same way).
        G.FUNCS.blindfold_discord = function()
            speech.say(Message.localized("SET.OPENING_DISCORD"):resolve())
            love.system.openURL("https://discord.gg/Dz8u2Pr9py")
        end
        G.FUNCS.blindfold_patreon = function()
            speech.say(Message.localized("SET.OPENING_PATREON"):resolve())
            love.system.openURL("https://www.patreon.com/bradjrenshaw")
        end
        -- Tag the credits overlay for its bespoke reader (nothing structural
        -- identifies it: anonymous tab closures, raw-string tab labels).
        if G.FUNCS.show_credits then
            local orig_credits = G.FUNCS.show_credits
            G.FUNCS.show_credits = function(e)
                orig_credits(e)
                if type(G.OVERLAY_MENU) == "table" then G.OVERLAY_MENU.blindfold_credits = true end
            end
        end
        G.FUNCS.blindfold_rebind = function(e)
            local key = e and e.config and e.config.ref_table and e.config.ref_table.blindfold_action
            local action = key and Input.find(key)
            if not action then return end
            local label = (action.label_key and Message.localized(action.label_key):resolve()) or action.key
            speech.say(Message.localized("SET.PRESS_KEY", { action = label }):resolve())
            Input.start_listening(function(binding)
                if binding.pad_button then
                    -- A gamepad press: rebind the action's controller button.
                    Input.set_pad_binding(action.key, binding.pad_button)
                    speech.say(Message.localized("SET.BOUND",
                        { action = label, key = Input.pad_display(binding.pad_button) }):resolve())
                elseif binding.key == "escape" then
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
-- Forensics for the save-reload pack bugs: log every G.STATE transition with
-- the context that decides which overlay claims the screen. Fires only on
-- change, so the log stays readable; remove once the reload flow is settled.
local _last_logged_state = "boot"
local function _state_name(st)
    if st == nil then return "nil" end
    for k, v in pairs((G and G.STATES) or {}) do
        if v == st then return k end
    end
    return tostring(st)
end
local function log_state_transition()
    if not G or G.STATE == _last_logged_state then return end
    local from = _last_logged_state
    _last_logged_state = G.STATE
    local pc = G.pack_cards
    local pack = type(pc) == "table"
        and (tostring(#(pc.cards or {})) .. " cards" .. (pc.REMOVED and ", REMOVED" or ""))
        or "nil"
    speech.log(string.format("STATE %s -> %s | pack_cards=%s booster=%s pack_interrupt=%s complete=%s",
        _state_name(from ~= "boot" and from or nil), _state_name(G.STATE),
        pack, tostring(G.booster_pack ~= nil),
        _state_name(G.GAME and G.GAME.PACK_INTERRUPT), tostring(G.STATE_COMPLETE)))
end

-- Recover a save bricked in PLAY_TAROT. PLAY_TAROT is transient bookkeeping
-- inside use_card: live, it ALWAYS has G.TAROT_INTERRUPT set (assigned before
-- the state, synchronously) and the use lock held, and exits via a queued
-- restore ~0.3s later. A save written while G.GAME.PACK_INTERRUPT was
-- poisoned (the pre-fix reload-replay double-use) loads straight into
-- PLAY_TAROT with neither — the game's updater for it does nothing, so the
-- run idles forever. If that shape holds for half a second, put the state
-- back: the hand deals only during a blind, so cards-in-hand means we were
-- selecting; otherwise the shop (STATE_COMPLETE=false rebuilds its UI from
-- the still-pending G.load_shop_* saved areas).
local _dead_tarot_ticks = 0
local function recover_dead_state()
    if not (G and G.STAGES and G.STAGE == G.STAGES.RUN and G.STATES
        and G.STATE == G.STATES.PLAY_TAROT
        and not G.TAROT_INTERRUPT
        and not (G.CONTROLLER and G.CONTROLLER.locks and G.CONTROLLER.locks.use)
        and not (type(G.pack_cards) == "table" and not G.pack_cards.REMOVED)) then
        _dead_tarot_ticks = 0
        return
    end
    _dead_tarot_ticks = _dead_tarot_ticks + 1
    if _dead_tarot_ticks == 30 then
        local in_hand = G.hand and G.hand.cards and #G.hand.cards > 0
        G.STATE = in_hand and G.STATES.SELECTING_HAND or G.STATES.SHOP
        G.STATE_COMPLETE = false
        speech.log("recovered dead PLAY_TAROT -> " .. (in_hand and "SELECTING_HAND" or "SHOP"))
    end
end

-- ---------------------------------------------------------------------------
-- Version + boot announcement + update check.
--
-- The installed version lives in <mod>/version — written by the installer
-- (release tag "vX.Y.Z" or dev build "main@<sha>"), by scripts/deploy.ps1 and
-- the post-merge git hook for junction installs, and stamped into release
-- zips by scripts/build_release.ps1.
--
-- Speaking at Game:start_up is too early — the window isn't up yet and screen
-- readers drop or garble it — so the loaded line waits until the game has
-- rendered for BOOT_DELAY seconds of real time, then the update check starts:
-- a love.thread fetches GitHub (releases + tip of main; see update_thread.lua)
-- and the poll announces once when the installed channel has something newer.
-- ---------------------------------------------------------------------------
BA.version = (function()
    -- love.filesystem first: PhysFS handles Unicode save paths, while
    -- io.open's ANSI fopen garbles non-ASCII user names (C:\Users\Usuário)
    -- and reported "no version file" on a perfectly good install. io.open
    -- stays as the junction-install fallback.
    local v = love.filesystem.read("Mods/Blindfold/version")
    if not v then
        local f = io.open(MOD_DIR .. "/version", "rb")
        if f then v = f:read("*a"); f:close() end
    end
    if not v then return nil end
    v = v:gsub("%s+", "")
    return v ~= "" and v or nil
end)()

local GITHUB_RELEASES = "https://api.github.com/repos/bradjrenshaw/Blindfold/releases/latest"
local GITHUB_COMMITS = "https://api.github.com/repos/bradjrenshaw/Blindfold/commits/main"
local UPDATE_CHANNEL = "blindfold_update"

local function loc_line(key, fallback, subs)
    local s = (BA.loc and BA.loc.get and BA.loc.get(key)) or fallback
    for k, v in pairs(subs or {}) do
        s = s:gsub("{" .. k .. "}", (tostring(v):gsub("%%", "%%%%")))
    end
    return s
end

local _update_started = false
local function start_update_check()
    if _update_started then return end
    _update_started = true
    pcall(function()
        local code = read_mod_file("update_thread.lua")
        if not code then return end
        love.thread.newThread(code):start(UPDATE_CHANNEL, GITHUB_RELEASES, GITHUB_COMMITS)
    end)
end

local function ver_nums(v)
    local a, b, c = tostring(v):match("^[vV]?(%d+)%.(%d+)%.?(%d*)")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c) or 0
end

local function release_newer(latest, current)
    local l1, l2, l3 = ver_nums(latest)
    if not l1 then return false end
    local c1, c2, c3 = ver_nums(current)
    if not c1 then return false end   -- unknown local version: stay quiet
    if l1 ~= c1 then return l1 > c1 end
    if l2 ~= c2 then return l2 > c2 end
    return l3 > c3
end

local _update_done = false
local function poll_update_check()
    if _update_done or not _update_started then return end
    local ch = love.thread.getChannel(UPDATE_CHANNEL)
    if ch:getCount() < 2 then return end
    _update_done = true
    local releases = ch:pop() or ""
    local commits = ch:pop() or ""
    local current = BA.version or ""
    local latest
    if current:match("^main") then
        -- Dev channel: compare our commit against the tip of main.
        local sha = commits:match('"sha"%s*:%s*"(%x+)"')
        local cur = current:match("^main@(%x+)")
        if sha and cur and sha:sub(1, #cur) ~= cur then
            latest = "main@" .. sha:sub(1, 7)
        end
    else
        -- Release channel: semver against the latest release tag.
        local tag = releases:match('"tag_name"%s*:%s*"([^"]+)"')
        if tag and release_newer(tag, current) then latest = tag end
    end
    if latest then
        speech.say(loc_line("MISC.UPDATE_AVAILABLE",
            "Blindfold update available: {current} to {latest}.",
            { current = current ~= "" and current or "unknown", latest = latest }))
    else
        speech.log("update check: up to date (" .. (current ~= "" and current or "no version file") .. ")")
    end
end

local BOOT_DELAY = 0.5
local _boot_announced = false
local function boot_announce()
    if _boot_announced then return end
    local t = G and G.TIMERS and G.TIMERS.REAL
    if not t or t < BOOT_DELAY then return end
    _boot_announced = true
    speech.say(loc_line("MISC.LOADED", "Blindfold {version} loaded.",
        { version = BA.version or "dev" }))
    start_update_check()
end

function BA.focus_tick(ctrl)
    pcall(boot_announce)
    pcall(poll_update_check)
    pcall(log_state_transition)
    pcall(recover_dead_state)
    if Screens then pcall(Screens.tick) end
    -- Right-stick -> buffer navigation (polled; sticks are axes, not buttons).
    if Input and Input.update_pad_axes then pcall(Input.update_pad_axes, ctrl) end
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

    -- 1b) Deselect-all feedback: Backspace / B / right-click all land in the
    -- engine's queue_R_cursor_press (controller.lua:1026), which clears the
    -- hand's highlights silently. Speak only when a selection actually
    -- cleared (the engine's own guards may refuse — mid-scoring, locked).
    local orig_r_cursor = Controller.queue_R_cursor_press
    function Controller:queue_R_cursor_press(x, y)
        local before = (G and G.hand and G.hand.highlighted and #G.hand.highlighted) or 0
        orig_r_cursor(self, x, y)
        local after = (G and G.hand and G.hand.highlighted and #G.hand.highlighted) or 0
        if before > 0 and after == 0 then
            pcall(function()
                speech.say(loc_line("PLAY.SELECTION_CLEARED", "Selection cleared"))
            end)
        end
    end

    -- 1c) Make that deselect RELIABLE under the owned overlays: the engine's
    -- own b-button routing (controller.lua:731) only deselects when the
    -- ENGINE's focus target is a hand card — and our overlays don't drive
    -- engine focus, so it's stale and B "sometimes works". When an overlay
    -- owns the screen (and no game menu is up), route b straight to
    -- queue_R_cursor_press — same call, same gameplay guards, no focus check.
    local orig_bpu = Controller.button_press_update
    function Controller:button_press_update(button, dt)
        if button == "b" and Overlays and Overlays.captures and Overlays.captures()
            and not (G and G.OVERLAY_MENU)
            and G and G.hand and G.hand.highlighted and G.hand.highlighted[1] then
            self:queue_R_cursor_press()
            return
        end
        return orig_bpu(self, button, dt)
    end

    -- ---- Run events (through the events dispatcher: grouped toggles in the
    -- Announcements screen, mirrored into the Events review buffer) --------

    -- A card named via its focus proxy, or nil. Face-down cards label as
    -- "face down card" — exactly what a sighted player would see destroyed.
    local function card_label(card)
        local ok, name = pcall(function()
            local proxy = Factory.create(card)
            local m = proxy and proxy.get_label and proxy:get_label()
            return m and m:resolve() or nil
        end)
        return ok and name or nil
    end
    local function emit(group, text, opts)
        if Events then pcall(Events.emit, group, text, opts) end
    end

    -- 1d) attention_text popups nothing else covers: the Wheel of Fortune's
    -- "Nope!" (card.lua:1502) and the Plasma Deck's "Balanced" swirl
    -- (back.lua:139). Everything else attention_text shows announces through
    -- paths we already hook or is decorative.
    if type(attention_text) == "function" then
        local orig_attention = attention_text
        _G.attention_text = function(args)
            pcall(function()
                local text = args and type(args.text) == "string" and args.text or nil
                if not text then return end
                if text == (localize and localize("k_nope_ex")) then
                    emit("cards", text, { instant = true })
                elseif text == (localize and localize("k_balanced")) then
                    emit("resources", text, { instant = true })
                end
            end)
            return orig_attention(args)
        end
    end

    -- 1e) An edition landing on a card (Wheel of Fortune / Aura / Hex /
    -- Ectoplasm): set_edition's celebration (juice + per-edition sound,
    -- card.lua:432) never names the card or edition. Announce exactly when
    -- the game celebrates — the silent calls are spawn-time decoration.
    local orig_set_edition = Card.set_edition
    function Card:set_edition(edition, immediate, silent)
        orig_set_edition(self, edition, immediate, silent)
        if not (self.edition and not silent) then return end
        pcall(function()
            local Proxy = ba_require("ui.proxies").Proxy
            local name = card_label(self)
            local word = Proxy.edition_word(self)
            word = word and word:resolve() or nil
            if name and word then
                emit("cards", loc_line("CARD.TIP", "{name}, {desc}",
                    { name = name, desc = word }))
            end
        end)
    end

    -- 1f) Tags firing: Tag:yep pops the effect text over the HUD tag
    -- (tag.lua:62, "+$25" etc.), Tag:nope pops a literal NOPE. Named with the
    -- game's localized tag name.
    if Tag then
        local function tag_name(tag)
            local ok, name = pcall(localize, { type = "name_text", set = "Tag", key = tag.key })
            return (ok and type(name) == "string" and name ~= "" and name ~= "ERROR") and name or nil
        end
        local orig_yep = Tag.yep
        function Tag:yep(message, _colour, func)
            pcall(function()
                local name = tag_name(self)
                local text = tostring(message or "")
                emit("tags", name and loc_line("CARD.TIP", "{name}, {desc}",
                    { name = name, desc = text }) or text)
            end)
            return orig_yep(self, message, _colour, func)
        end
        local orig_nope = Tag.nope
        function Tag:nope()
            pcall(function()
                local name = tag_name(self)
                emit("tags", name and loc_line("CARD.TIP", "{name}, {desc}",
                    { name = name, desc = "NOPE" }) or "NOPE")
            end)
            return orig_nope(self)
        end
    end

    -- 1g) Cards destroyed: the victim of Ceremonial Dagger / Hex / Immolate /
    -- Madness just plays its dissolve. Announce dissolves from the joker row
    -- and the hand; NOT sells (sell_card dissolves too — flagged below, the
    -- sell announcement covers it), used consumables (G.consumeables), pack
    -- skips, or scoring shatters (G.play — the eval message names those).
    local orig_sell_card = Card.sell_card
    function Card:sell_card()
        self._ba_selling = true
        return orig_sell_card(self)
    end
    local orig_dissolve = Card.start_dissolve
    function Card:start_dissolve(...)
        pcall(function()
            if self._ba_selling then return end
            if not (G and self.area and (self.area == G.jokers or self.area == G.hand)) then return end
            local name = card_label(self)
            if name then
                emit("cards", loc_line("EVENTS.DESTROYED", "{name} destroyed",
                    { name = name }), { instant = true })
            end
        end)
        return orig_dissolve(self, ...)
    end

    -- 1h) Cards created mid-run (Judgement, Riff-Raff, Ankh and Invisible
    -- Joker copies, spectral-made consumables): they materialize into the
    -- joker/consumable rows via emplace. Purchases and pack picks arrive
    -- through the same emplace — flagged at their FUNCS below, since buying
    -- already announces.
    local orig_buy = G.FUNCS.buy_from_shop
    if orig_buy then
        G.FUNCS.buy_from_shop = function(e)
            pcall(function()
                local c = e and e.config and e.config.ref_table
                if c then c._ba_acquired = true end
            end)
            return orig_buy(e)
        end
    end
    local orig_use = G.FUNCS.use_card
    if orig_use then
        G.FUNCS.use_card = function(e, mute, nosave)
            pcall(function()
                local c = e and e.config and e.config.ref_table
                if c then c._ba_acquired = true end
            end)
            return orig_use(e, mute, nosave)
        end
    end
    local orig_emplace = CardArea.emplace
    function CardArea:emplace(card, location, stay_flipped)
        local from = card and card.area
        orig_emplace(self, card, location, stay_flipped)
        pcall(function()
            if not (G and (self == G.jokers or self == G.consumeables)) then return end
            if from ~= nil then return end            -- moved, not created
            if card._ba_acquired then card._ba_acquired = nil; return end
            local name = card_label(card)
            if name then
                emit("cards", loc_line("EVENTS.ADDED", "{name} added", { name = name }))
            end
        end)
    end

    -- 1i) Resource deltas: the game pops "+1"/"-1" next to the HUD number
    -- whenever hands/discards/ante/round change outside the normal round
    -- reset (ease_*, common_events.lua:111+). Money (ease_dollars) is
    -- deliberately NOT hooked: every dollar change already announces through
    -- the scoring, cash-out, or tag paths — hooking it would double-speak.
    local EASES = {
        { name = "ease_hands_played", key = "EVENTS.HANDS",    fallback = "{amt} hands" },
        { name = "ease_discard",      key = "EVENTS.DISCARDS", fallback = "{amt} discards" },
        { name = "ease_ante",         key = "EVENTS.ANTE",     fallback = "{amt} ante" },
        { name = "ease_round",        key = "EVENTS.ROUND",    fallback = "{amt} round" },
    }
    for _, spec in ipairs(EASES) do
        local orig = _G[spec.name]
        if type(orig) == "function" then
            _G[spec.name] = function(mod, ...)
                pcall(function()
                    local n = tonumber(mod)
                    if n and n ~= 0 then
                        local amt = n > 0 and ("+" .. tostring(n)) or tostring(n)
                        emit("resources", loc_line(spec.key, spec.fallback, { amt = amt }))
                    end
                end)
                return orig(mod, ...)
            end
        end
    end

    -- 1j) "No space!" — a joker/consumable-creating effect firing with full
    -- slots (alert_no_space, misc_functions.lua:885). The game's word.
    if type(alert_no_space) == "function" then
        local orig_no_space = alert_no_space
        _G.alert_no_space = function(card, area)
            pcall(function()
                local ok, text = pcall(localize, "k_no_space_ex")
                emit("cards", (ok and type(text) == "string") and text or "No space!",
                    { instant = true })
            end)
            return orig_no_space(card, area)
        end
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
        -- The play-area banner ("Not Allowed!" from The Eye / The Mouth).
        -- Speech queued before the original for the same reason as above.
        if play_area_status_text then
            local orig_pas = play_area_status_text
            function play_area_status_text(text, silent, delay)
                pcall(Scoring.on_play_area_status, text)
                return orig_pas(text, silent, delay)
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
                -- The Hook's forced discard: name the victims BEFORE the game
                -- consumes the highlight.
                if hook then pcall(Round.on_hook_discard) end
                orig_discard(e, hook)
                pcall(Round.on_discard, hook)
            end
        end
        -- Boss-blind effects that are only rendered (The Hook is the wrap
        -- above): Crimson Heart's roaming joker debuff, The Ox's money wipe,
        -- The Tooth's per-card drain.
        if Blind then
            if Blind.drawn_to_hand then
                local orig_dth = Blind.drawn_to_hand
                function Blind:drawn_to_hand()
                    local before = {}
                    for _, c in ipairs((G.jokers and G.jokers.cards) or {}) do
                        before[c] = c.debuff and true or false
                    end
                    local r = orig_dth(self)
                    pcall(Round.on_joker_debuffs, before)
                    return r
                end
            end
            if Blind.debuff_hand then
                local orig_dbh = Blind.debuff_hand
                function Blind:debuff_hand(cards, hand, handname, check)
                    local r = orig_dbh(self, cards, hand, handname, check)
                    pcall(Round.on_blind_hand, self, check)
                    return r
                end
            end
            if Blind.press_play then
                local orig_bpp = Blind.press_play
                function Blind:press_play()
                    local r = orig_bpp(self)
                    pcall(Round.on_blind_played, self)
                    return r
                end
            end
        end
        -- The Arm's hand level-down: level_up_hand's piecemeal hand-text
        -- updates carry no hand name, so the upgrade announcements never see
        -- a downgrade — announce from the function itself.
        if BA.scoring and level_up_hand then
            local orig_lvl = level_up_hand
            function level_up_hand(card, hand, instant, amount)
                orig_lvl(card, hand, instant, amount)
                if (amount or 1) < 0 then pcall(BA.scoring.on_level_down, hand) end
            end
        end
    end

    -- 6b) Jimbo's dialogue (tutorial guidance, win/loss quips): every bubble
    --     funnels through Card_Character:add_speech_bubble — tutorial keys,
    --     'wq_*' win quips, 'lq_*' loss quips, and the demo's literal-table
    --     text all render into the same UIBox, so scraping the built bubble
    --     (static text + DynaText) covers them uniformly. The bubble turns
    --     visible a beat later (say_stuff's 0.1s reveal), so speaking on add
    --     lands with it.
    if Card_Character and Card_Character.add_speech_bubble then
        local okp, ProxyMod = pcall(ba_require, "ui.proxies")
        local P = okp and ProxyMod and ProxyMod.Proxy or nil
        if P then
            local orig_bubble = Card_Character.add_speech_bubble
            function Card_Character:add_speech_bubble(text_key, align, loc_vars)
                local r = orig_bubble(self, text_key, align, loc_vars)
                pcall(function()
                    local bubble = self.children and self.children.speech_bubble
                    local root = bubble and bubble.UIRoot
                    local text = root and P.all_text(root)
                    if type(text) == "string" and text ~= "" then
                        speech.say(text)
                    end
                end)
                return r
            end
        end
    end

    -- 6c) Unlock / discovery toasts: notify_alert slides a visual-only box
    --     in from the screen edge (new Joker/Voucher/Deck unlocks,
    --     achievements, Challenge Mode unlocking) and slides it away — no
    --     focus, never spoken. The box's text names only the CATEGORY; the
    --     art identifies what unlocked, so the name joins the announcement.
    if notify_alert then
        local okp, ProxyMod = pcall(ba_require, "ui.proxies")
        local P = okp and ProxyMod and ProxyMod.Proxy or nil
        local SUBTEXT_KEYS = { Joker = "k_joker", Voucher = "k_voucher", Back = "k_deck" }
        local orig_notify = notify_alert
        function notify_alert(_achievement, _type)
            pcall(function()
                local t = _type or "achievement"
                local parts = {}
                local function add_loc(key, set)
                    local ok, s = pcall(localize, key, set)
                    if ok and type(s) == "string" and s ~= "" then parts[#parts + 1] = s end
                end
                if t == "achievement" then
                    add_loc(_achievement, "achievement_names")
                    add_loc(G.F_TROPHIES and "k_trophy" or "k_achievement")
                else
                    local center = G.P_CENTERS and G.P_CENTERS[_achievement]
                    local name = center and P and P.center_name(center)
                    if name then parts[#parts + 1] = tostring(name) end
                    if _achievement == "b_challenge" then
                        add_loc("k_challenges")
                    else
                        add_loc(SUBTEXT_KEYS[t])
                    end
                    add_loc("k_unlocked_ex")
                end
                if parts[1] then speech.say(table.concat(parts, ", ")) end
            end)
            return orig_notify(_achievement, _type)
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

    -- 8) Physical gamepad -> the mod's own controller scheme, with TOTAL
    --    ownership (see the love-callback wrap below). Wrapped at the love
    --    callbacks, NOT Controller:button_press: the keyboard fallback and
    --    on_pad_down's game_button branch synthesize button_press calls
    --    (brackets -> shoulders for menu tabs, backspace/B -> b, Start ->
    --    start) that must keep their native meaning.
    -- 9) TOTAL AXIS OWNERSHIP: blank EVERY axis-to-button conversion (left
    -- stick's dpad synthesis + both triggers) — the mod polls the axes
    -- itself (update_pad_axes: triggers -> chords, left stick -> nav flicks,
    -- right stick -> buffers). Blanking only .current lets an in-flight hold
    -- release cleanly through .previous.
    local orig_axis_buttons = Controller.handle_axis_buttons
    function Controller:handle_axis_buttons()
        if Input and self.axis_buttons then
            for _, k in ipairs({ "l_stick", "l_trig", "r_trig" }) do
                if self.axis_buttons[k] then self.axis_buttons[k].current = "" end
            end
        end
        return orig_axis_buttons(self)
    end

    -- TOTAL BUTTON OWNERSHIP (Brad): every physical press dispatches through
    -- the mod's map or does NOTHING — no button ever reaches the engine's
    -- context-overloaded native handling on its own. Engine behaviors we keep
    -- (B, Start) are actions whose game_button on_pad_down presses
    -- deliberately. Presses still register the gamepad + HID flags
    -- (controller detection, button glyphs). Sole exception: an active text
    -- input (seed/profile fields) keeps fully native input.
    if love and love.gamepadpressed and love.gamepadreleased then
        local orig_pad_down = love.gamepadpressed
        local orig_pad_up = love.gamepadreleased
        love.gamepadpressed = function(joystick, button)
            local mapped = (G.button_mapping and G.button_mapping[button]) or button
            if not Input then return orig_pad_down(joystick, button) end
            if G.CONTROLLER and G.CONTROLLER.text_input_hook then
                return orig_pad_down(joystick, button)
            end
            pcall(function()
                G.CONTROLLER:set_gamepad(joystick)
                G.CONTROLLER:set_HID_flags("button", mapped)
            end)
            pcall(Input.on_pad_down, G.CONTROLLER, mapped)
        end
        love.gamepadreleased = function(joystick, button)
            local mapped = (G.button_mapping and G.button_mapping[button]) or button
            if not Input then return orig_pad_up(joystick, button) end
            if G.CONTROLLER and G.CONTROLLER.text_input_hook then
                return orig_pad_up(joystick, button)
            end
            pcall(Input.on_pad_up, mapped, G.CONTROLLER)
        end
    end

    -- 10) Save-reload repair: G.sort_id (the card id counter) is NOT part of
    --     the save, but restored cards keep their saved ids — so cards created
    --     after a load can DUPLICATE a restored card's sort_id. The game's
    --     mid-pack restore replays "open the booster" by scanning G.I.CARD
    --     for the saved sort_id and calling use_card on EVERY match: on a
    --     collision it also uses an unrelated card — eating a pack card,
    --     bouncing G.STATE back to SHOP under the open pack, and consuming
    --     G.GAME.PACK_INTERRUPT so the pack's real close later assigns
    --     G.STATE = nil (every screen, game and mod, goes dead). Keeping the
    --     counter above every loaded id keeps new ids unique.
    if Card and Card.load then
        local orig_card_load = Card.load
        function Card:load(cardTable, other_card)
            local r = orig_card_load(self, cardTable, other_card)
            if type(self.sort_id) == "number" and (G.sort_id or 0) < self.sort_id then
                G.sort_id = self.sort_id
            end
            return r
        end
    end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
local ok, err = pcall(function()
    speech.init(MOD_DIR)
    -- The backend picker registered before prism was up (module load time):
    -- fill its options in now that the registry can enumerate, and apply the
    -- saved choice (a no-op on "auto").
    pcall(function()
        local s = BA.settings and BA.settings.by_key and BA.settings.by_key["speech.backend"]
        if s then
            local opts = { "auto" }
            for _, name in ipairs(speech.backends()) do opts[#opts + 1] = name end
            s.options = opts
        end
        speech.set_backend(BA.settings and BA.settings.value("speech.backend"))
    end)
    BA.install()
    -- The loaded announcement is deliberately NOT here: it waits for the
    -- window (boot_announce in focus_tick), or screen readers drop it.
end)
if not ok then
    pcall(function()
        love.filesystem.append("blindfold.log", "FATAL during boot: " .. tostring(err) .. "\n")
    end)
end

return BA
