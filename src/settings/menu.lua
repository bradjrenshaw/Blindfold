-- settings/menu.lua — renders the settings registry as native Balatro controls
-- (create_toggle / create_option_cycle). These are read for free by our focus
-- proxies. Returns a UIT.ROOT node used as the content of the "Blindfold" tab
-- injected into the game's Options screen.
local require = ...
local Settings = require("settings.registry")
local Message = require("ui.message")
local Input = require("input.manager")

local M = {}

local function loc(key) return Message.localized(key):resolve() end

local function build()
    local nodes = {}
    -- Keybindings open in their own sub-screen (button at the top of the tab).
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
        UIBox_button({ label = { loc("SET.KEYBINDS") }, button = "blindfold_keybinds",
            minw = 4, minh = 0.6, scale = 0.5, colour = G.C.BLUE }),
    } }
    for _, s in ipairs(Settings.list) do
        if s.type == "bool" then
            nodes[#nodes + 1] = create_toggle({
                label = loc(s.label_key),
                ref_table = Settings.values,
                ref_value = s.key,
                -- The bound value is flipped automatically; persist on change.
                callback = function(newval) Settings.on_change(s.key, newval) end,
            })
        elseif s.type == "choice" then
            local labels = {}
            for i, opt in ipairs(s.options or {}) do
                labels[i] = (s.labels and s.labels[i]) and loc(s.labels[i]) or tostring(opt)
            end
            nodes[#nodes + 1] = create_option_cycle({
                label = loc(s.label_key),
                scale = 0.8,
                options = labels,
                current_option = Settings.choice_index(s),
                opt_callback = "blindfold_cycle",   -- registered in core
                blindfold_key = s.key,              -- read back via cycle_config
            })
        end
    end
    return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.1, colour = G.C.CLEAR }, nodes = nodes }
end

-- Called by the injected Options tab. Guarded so a build error degrades to a
-- placeholder instead of breaking the game's Options screen.
function M.settings_tab()
    local ok, root = pcall(build)
    if ok and root then return root end
    return { n = G.UIT.ROOT, config = { align = "cm", minh = 2, minw = 4, colour = G.C.CLEAR }, nodes = {
        { n = G.UIT.R, config = { align = "cm" }, nodes = {
            { n = G.UIT.T, config = { text = "Blindfold settings unavailable", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
        } },
    } }
end

-- The keybindings sub-screen: a single linear column of rebind buttons (one per
-- input action) — easiest to navigate by ear. Rows are compact so they fit on
-- screen (off-screen rows wouldn't be focusable). Opened via
-- G.FUNCS.blindfold_keybinds (overlay_menu); back returns to Options.
function M.keybinds_uibox()
    local rows = {}
    for _, a in ipairs(Input.actions or {}) do
        local label = (a.label_key and loc(a.label_key)) or a.key
        rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
            UIBox_button({
                label = { label .. ": " .. a:bindings_display() },
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
