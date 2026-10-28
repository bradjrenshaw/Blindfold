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

-- Where the settings were opened from: "options" (the injected Options tab)
-- or "mods" (Steamodded's Config button, smods.lua). The sub-screens' Back
-- returns there (G.FUNCS.blindfold_settings_back, core).
M.origin = "options"

-- Called by the injected Options tab, and by Steamodded's Config tab with
-- origin "mods". Guarded so a build error degrades to a placeholder instead
-- of breaking the screen it sits in.
function M.settings_tab(origin)
    M.origin = origin == "mods" and "mods" or "options"
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
    return create_UIBox_generic_options({ back_func = "blindfold_settings_back", contents = { content } })
end

-- Voice settings. The voice is a hex id from the speech library's tree
-- ("auto" = its best available: the running screen reader, else the system
-- voice); rate, pitch and volume are integer percent (Loadstar's 0..1
-- underneath, 50 = the voice's own default for rate and pitch) and apply to
-- whichever voice speaks, which ignores what it cannot adjust.
local ADJUSTABLES = {
    { "rate",   "SET.RATE",   50 },
    { "pitch",  "SET.PITCH",  50 },
    { "volume", "SET.VOLUME", 100 },
}

-- What the speech module should speak with, from the saved settings.
function M.profile()
    local cfg = { voice = Settings.value("speech.voice") or "auto" }
    for _, a in ipairs(ADJUSTABLES) do
        local v = Settings.value("speech." .. a[1])
        if type(v) == "number" then cfg[a[1]] = v / 100 end
    end
    return cfg
end

-- Reopen the Voice screen in place when it is showing: the controls under
-- the picker belong to the voice that was speaking when it opened.
local function rebuild_voice_screen()
    if type(G.OVERLAY_MENU) == "table" and G.OVERLAY_MENU.blindfold_title_key == "SET.VOICE"
       and G.FUNCS.blindfold_voice then
        G.FUNCS.blindfold_voice()
    end
end

-- Registered once at load (after Settings.load, so saved values win). The
-- voice picker's options are filled in each time the Voice screen opens.
function M.register_voice_settings()
    Settings.register{ key = "speech.voice", type = "choice",
        label_key = "SET.VOICE_NAME", default = "auto", category = "voice",
        options = { "auto" }, labels = { "SET.BACKEND_AUTO" },
        apply = function(v)
            speech.set_profile({ voice = v })
            rebuild_voice_screen()
        end }
    for _, a in ipairs(ADJUSTABLES) do
        local what = a[1]
        Settings.register{ key = "speech." .. what, type = "number",
            label_key = a[2], category = "voice:" .. what, min = 0, max = 100, default = a[3],
            apply = function(v)
                if type(v) == "number" then speech.set_profile({ [what] = v / 100 }) end
            end }
    end
end

-- Built-in category keys the mod translates; product names (SAPI 5,
-- AVSpeech, ...) pass through as the library names them.
local CATEGORY_LABELS = { screen_readers = "SET.CAT_SCREEN_READERS", clipboard = "SET.CAT_CLIPBOARD" }

-- Refill the voice picker from the library's tree: Auto (naming what it
-- resolves to now), then each category's voices — the game's language first,
-- then alphabetical — labelled with category and language so a long list
-- stays navigable by ear.
local function refresh_voice_options()
    local s = Settings.by_key["speech.voice"]
    if not s then return end
    local voices = speech.voices()
    local lang = (G and G.SETTINGS and G.SETTINGS.language or "en"):lower():sub(1, 2)
    local order, groups = {}, {}
    for _, v in ipairs(voices) do
        if not groups[v.category] then
            groups[v.category] = {}
            order[#order + 1] = v.category
        end
        local g = groups[v.category]
        g[#g + 1] = v
    end
    local auto = loc("SET.BACKEND_AUTO")
    local now = speech.resolved()
    if now and Settings.value("speech.voice") == "auto" then auto = auto .. ": " .. now.name end
    local options, labels = { "auto" }, { auto }
    local seen = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        table.sort(g, function(a, b)
            local al = a.language:lower():sub(1, 2) == lang
            local bl = b.language:lower():sub(1, 2) == lang
            if al ~= bl then return al end
            return a.name < b.name
        end)
        local cat = CATEGORY_LABELS[key] and loc(CATEGORY_LABELS[key]) or g[1].category_name
        for _, v in ipairs(g) do
            options[#options + 1] = v.id
            local label = (#order > 1 and (cat .. ": ") or "") .. v.name
            if v.language ~= "" then label = label .. " (" .. v.language .. ")" end
            labels[#labels + 1] = label
            seen[v.id] = true
        end
    end
    -- A saved voice that is absent today (reader not running, voice removed)
    -- stays selectable so the picker shows the truth; the library speaks
    -- through its fallback meanwhile.
    local saved = Settings.value("speech.voice")
    if saved ~= "auto" and not seen[saved] then
        local name = speech.voice_name(saved)
        options[#options + 1] = saved
        labels[#labels + 1] = (name ~= "" and name or saved) .. " (" .. loc("SET.VOICE_UNAVAILABLE") .. ")"
    end
    Settings.register{ key = "speech.voice", options = options, label_values = labels }
end

-- The Voice sub-screen: the voice picker on top, then whatever the voice
-- now speaking lets the user adjust (rate, pitch, volume). Changing the voice
-- rebuilds the screen (see the picker's apply).
function M.voice_uibox()
    speech.refresh()   -- a reader started since boot shows up on the next visit
    refresh_voice_options()
    local nodes = controls("voice")
    local caps = speech.resolved() or {}
    local extra = {}
    for _, a in ipairs(ADJUSTABLES) do
        if caps[a[1]] then
            for _, c in ipairs(controls("voice:" .. a[1])) do extra[#extra + 1] = c end
        end
    end
    if #extra == 0 then
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
            { n = G.UIT.T, config = { text = loc("SET.NO_VOICE_OPTIONS"), scale = 0.35, colour = G.C.UI.TEXT_LIGHT } },
        } }
    end
    for _, c in ipairs(extra) do nodes[#nodes + 1] = c end
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = nodes }
    return create_UIBox_generic_options({ back_func = "blindfold_settings_back", contents = { content } })
end

-- The Scoring sub-screen: the scoring toggles plus the per-effect verbosity
-- cycles (how "+10 chips" reads during the fast scoring animations).
function M.scoring_uibox()
    local content = { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = controls("scoring") }
    return create_UIBox_generic_options({ back_func = "blindfold_settings_back", contents = { content } })
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
    return create_UIBox_generic_options({ back_func = "blindfold_settings_back", contents = { content } })
end

return M
