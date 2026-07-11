-- settings/menu.lua — renders the settings registry as native Balatro controls
-- (create_toggle / create_option_cycle), which the focus proxies read for free.
-- The main "Blindfold" tab (injected into Options) holds the scoring settings
-- plus buttons that open sub-screens (Keybindings, Announcements).
local require = ...
local Settings = require("settings.registry")
local Message = require("ui.message")
local Input = require("input.manager")

local M = {}

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
            labels[i] = (s.labels and s.labels[i]) and loc(s.labels[i]) or tostring(opt)
        end
        return create_option_cycle({
            label = loc(s.label_key), scale = 0.8,
            options = labels,
            current_option = Settings.choice_index(s),
            opt_callback = "blindfold_cycle",   -- registered in core
            blindfold_key = s.key,              -- read back via cycle_config
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

-- The Blindfold tab: sub-screen buttons + the scoring settings inline.
local function build_main()
    local nodes = {
        nav_button("SET.KEYBINDS", "blindfold_keybinds"),
        nav_button("SET.ANNOUNCEMENTS", "blindfold_announcements"),
        -- The game ships G.FUNCS.start_tutorial (reset progress + launch the
        -- tutorial run) but no vanilla UI ever calls it. Handy for TESTING
        -- the tutorial flow, but it's not a real game feature, so it stays
        -- out of the shipped menu — uncomment to re-test.
        -- nav_button("SET.TUTORIAL", "start_tutorial"),
    }
    for _, c in ipairs(controls("scoring")) do nodes[#nodes + 1] = c end
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
