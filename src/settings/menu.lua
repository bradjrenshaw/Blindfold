-- settings/menu.lua — renders the settings registry as native Balatro controls
-- (create_toggle / create_option_cycle), which the focus proxies read for free.
-- The main "Blindfold" tab (injected into Options) holds the scoring settings
-- plus buttons that open sub-screens (Keybindings, Announcements).
local require = ...
local Settings = require("settings.registry")
local Message = require("ui.message")
local Input = require("input.manager")

local M = {}

-- The speech module is loaded once by Lovely (as blindfold_speech) and handed
-- over by core as M.speech; loading it again here would re-run its ffi.cdef.
-- This proxy lets the code below say speech.xxx before core has set it.
local speech = setmetatable({}, { __index = function(_, k) return M.speech and M.speech[k] end })

local function loc(key) return Message.localized(key):resolve() end

-- The native control node for one setting.
local function control_for(s)
    if s.type == "bool" then
        return create_toggle({
            label = loc(s.label_key),
            ref_table = Settings.values,
            ref_value = s.key,
            callback = function(newval) Settings.on_change(s.key, newval) end,
        })
    elseif s.type == "choice" then
        local labels = {}
        for i, opt in ipairs(s.options or {}) do
            labels[i] = (s.label_values and s.label_values[i])
                or ((s.labels and s.labels[i]) and loc(s.labels[i]))
                or tostring(opt)
        end
        return create_option_cycle({
            label = loc(s.label_key), scale = 0.8,
            options = labels,
            current_option = Settings.choice_index(s),
            opt_callback = "blindfold_cycle",   -- registered in core
            blindfold_key = s.key,              -- read back via cycle_config
        })
    elseif s.type == "number" then
        -- The native slider writes straight into Settings.values; the
        -- callback (mouse drag, or the keyboard path in menu_mirror) then
        -- persists and applies it.
        if type(Settings.values[s.key]) ~= "number" then Settings.values[s.key] = s.default or 0 end
        return create_slider({
            label = loc(s.label_key), label_scale = 0.4, text_scale = 0.3,
            w = 3, h = 0.4,
            ref_table = Settings.values, ref_value = s.key,
            min = s.min or 0, max = s.max or 100, decimal_places = 0,
            callback = "blindfold_slider",      -- registered in core
        })
    end
end

-- Control nodes for every setting in a category (in registration order).
local function controls(category)
    local nodes = {}
    for _, s in ipairs(Settings.list) do
        if s.category == category then
            local c = control_for(s)
            if c then nodes[#nodes + 1] = c end
        end
    end
    return nodes
end

-- A button that opens a sub-screen.
local function nav_button(label_key, func)
    return { n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = {
        UIBox_button({ label = { loc(label_key) }, button = func,
            minw = 4, minh = 0.6, scale = 0.5, colour = G.C.BLUE }),
    } }
end

-- The Blindfold tab: sub-screen buttons + the remaining speech settings inline.
local function build_main()
    local nodes = {
        nav_button("SET.KEYBINDS", "blindfold_keybinds"),
        nav_button("SET.ANNOUNCEMENTS", "blindfold_announcements"),
        nav_button("SET.SCORING", "blindfold_scoring"),
        nav_button("SET.VOICE", "blindfold_voice"),
        -- The game ships G.FUNCS.start_tutorial (reset progress + launch the
        -- tutorial run) but no vanilla UI ever calls it. Enabled while the
        -- tutorial lockup reports are being chased — comment out again to
        -- ship without it.
        nav_button("SET.TUTORIAL", "start_tutorial"),
    }
    for _, c in ipairs(controls("speech")) do nodes[#nodes + 1] = c end
    -- Bundled docs, opened in the OS default handler (spoken confirmation in core).
    nodes[#nodes + 1] = nav_button("SET.VIEW_DOCS", "blindfold_docs")
    nodes[#nodes + 1] = nav_button("SET.VIEW_CHANGES", "blindfold_changes")
    -- Community links, opened in the browser (spoken confirmation in core).
    nodes[#nodes + 1] = nav_button("SET.DISCORD", "blindfold_discord")
    nodes[#nodes + 1] = nav_button("SET.PATREON", "blindfold_patreon")
    return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.1, colour = G.C.CLEAR }, nodes = nodes }
end

-- Called by the injected Options tab. Guarded so a build error degrades to a
-- placeholder instead of breaking the game's Options screen.
function M.settings_tab()
    local ok, root = pcall(build_main)
    if ok and root then return root end
    return { n = G.UIT.ROOT, config = { align = "cm", minh = 2, minw = 4, colour = G.C.CLEAR }, nodes = {
        { n = G.UIT.R, config = { align = "cm" }, nodes = {
            { n = G.UIT.T, config = { text = (function()
                local ok2, s = pcall(loc, "SET.UNAVAILABLE")
                return ok2 and s or "Blindfold settings unavailable"
            end)(), scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
        } },
    } }
end

-- The Announcements sub-screen: a single column of announcement toggles.
function M.announcements_uibox()
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = controls("announce") }
    return create_UIBox_generic_options({ back_func = "options", contents = { content } })
end

-- Settings key for one adjustable of one backend ("speech.cfg.avspeech.rate").
local function backend_key(backend_name, what)
    local slug = tostring(backend_name or "unknown"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return "speech.cfg." .. slug .. "." .. what
end
M.backend_key = backend_key

-- The saved configuration for a backend, in Prism's 0..1 units, or nil
-- for anything the user never touched (speech.adopt leaves those at the
-- engine's defaults). Sliders store integer percentages.
function M.config_for(backend_name)
    local cfg = {}
    for _, what in ipairs({ "volume", "rate", "pitch" }) do
        local v = Settings.values[backend_key(backend_name, what)]
        if type(v) == "number" then cfg[what] = v / 100 end
    end
    local voice = Settings.values[backend_key(backend_name, "voice")]
    if type(voice) == "string" and voice ~= "" then cfg.voice = voice end
    return cfg
end

-- Register (or refresh) the per-backend settings for the ACTIVE backend:
-- one slider per adjustable it supports, a voice picker when it lists
-- voices. Defaults come from the backend's current values, so the first
-- visit shows the engine as it is rather than an invented midpoint.
-- Category "voice:<slug>" keeps each backend's controls together.
local function ensure_backend_settings()
    local name = speech.backend_name
    if not name then return nil end
    local caps = speech.capabilities()
    local category = "voice:" .. backend_key(name, "")
    local function pct(v) return v and math.floor(v * 100 + 0.5) or 50 end
    local specs = {
        { "volume", "SET.VOLUME", caps.volume, speech.get_volume, speech.set_volume, 100 },
        { "rate",   "SET.RATE",   caps.rate,   speech.get_rate,   speech.set_rate,   50 },
        { "pitch",  "SET.PITCH",  caps.pitch,  speech.get_pitch,  speech.set_pitch,  50 },
    }
    for _, spec in ipairs(specs) do
        local what, label_key, supported, getter, setter, fallback = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
        if supported then
            local current = getter()
            Settings.register{ key = backend_key(name, what), type = "number",
                label_key = label_key, category = category, min = 0, max = 100,
                default = current and pct(current) or fallback,
                apply = function(v) if type(v) == "number" then setter(v / 100) end end }
        end
    end
    if caps.voice then
        local voices = speech.voices()
        if #voices > 0 then
            -- Voices for the game's language first, then the rest, each
            -- group alphabetical; the label carries the language tag so a
            -- long list stays navigable by ear.
            local lang = (G and G.SETTINGS and G.SETTINGS.language or "en"):lower():sub(1, 2)
            table.sort(voices, function(a, b)
                local al = (a.language or ""):lower():sub(1, 2) == lang
                local bl = (b.language or ""):lower():sub(1, 2) == lang
                if al ~= bl then return al end
                return a.name < b.name
            end)
            local names, labels = {}, {}
            for i, v in ipairs(voices) do
                names[i] = v.name
                labels[i] = v.language and (v.name .. " (" .. v.language .. ")") or v.name
            end
            Settings.register{ key = backend_key(name, "voice"), type = "choice",
                label_key = "SET.VOICE_NAME", category = category,
                options = names, label_values = labels,
                default = speech.current_voice_name() or names[1],
                apply = function(v) speech.set_voice_by_name(v) end }
        end
    end
    return category
end

-- The Voice sub-screen: the backend picker on top, then whatever the active
-- backend lets the user adjust (volume, rate, pitch, voice). Switching the
-- backend rebuilds the screen (core reopens it from the picker's apply).
function M.voice_uibox()
    local nodes = controls("voice")
    local category = ensure_backend_settings()
    local extra = category and controls(category) or {}
    if #extra == 0 then
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
            { n = G.UIT.T, config = { text = loc("SET.NO_VOICE_OPTIONS"), scale = 0.35, colour = G.C.UI.TEXT_LIGHT } },
        } }
    end
    for _, c in ipairs(extra) do nodes[#nodes + 1] = c end
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = nodes }
    return create_UIBox_generic_options({ back_func = "options", contents = { content } })
end

-- The Scoring sub-screen: the scoring toggles plus the per-effect verbosity
-- cycles (how "+10 chips" reads during the fast scoring animations).
function M.scoring_uibox()
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = controls("scoring") }
    return create_UIBox_generic_options({ back_func = "options", contents = { content } })
end

-- The keybindings sub-screen: a single linear column of rebind buttons (one per
-- input action) — easiest to navigate by ear. Opened via
-- G.FUNCS.blindfold_keybinds; back returns to Options.
function M.keybinds_uibox()
    local rows = {}
    for _, a in ipairs(Input.actions or {}) do
        local label = (a.label_key and loc(a.label_key)) or a.key
        local disp = label .. ": " .. a:bindings_display()
        local pad = Input.pad_button_for and Input.pad_button_for(a.key)
        if pad then disp = disp .. " / " .. Input.pad_display(pad) end
        rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
            UIBox_button({
                label = { disp },
                button = "blindfold_rebind",
                ref_table = { blindfold_action = a.key },
                minw = 5, minh = 0.4, scale = 0.3, colour = G.C.GREY,
            }),
        } }
    end
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = rows }
    return create_UIBox_generic_options({ back_func = "options", contents = { content } })
end

return M
