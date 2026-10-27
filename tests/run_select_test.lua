-- Harness: Steamodded's paged New Run screen (overlays/run_select.lua) —
-- inert without Steamodded; with it, the deck grid in rendered rows with
-- columns kept, names / locked / selected / win sticker, descriptions and
-- position deferred, select vs advance on Enter, the page cycle, the
-- selection summary, and the nav buttons. Also the win-sticker stake name
-- under both sticker_map shapes (vanilla array, Steamodded hash).
local ROOT = arg[1] or "."
local loaded = {}
local function ba_require(name)
    if loaded[name] then return loaded[name] end
    local f = assert(io.open(ROOT .. "/src/" .. name:gsub("%.", "/") .. ".lua", "rb"))
    local code = f:read("*a"); f:close()
    local chunk = assert(load(code, "@" .. name, "t"))
    loaded[name] = true
    loaded[name] = chunk(ba_require) or true
    return loaded[name]
end

_G.love = { filesystem = { write = function() end, read = function() return nil end,
    append = function() end } }

local NAMES = {
    Back = { b_red = "Red Deck", b_blue = "Blue Deck", b_yellow = "Yellow Deck" },
    Stake = { stake_white = "White Stake", stake_red = "Red Stake", stake_gold = "Gold Stake" },
}
local STRINGS = {
    k_locked = "Locked",
    run_select_deck_choice = "Select Deck",
    run_select_stake_choice = "Select Stake",
    run_select_nothing = "Nothing",
}
_G.localize = function(a)
    if type(a) == "table" then
        if a.type == "name_text" then return (NAMES[a.set] or {})[a.key] or "ERROR" end
        return "ERROR"
    end
    return STRINGS[a] or "ERROR"
end

local Message = ba_require("ui.message")
local en = ba_require("loc.en")
Message.set_resolver(function(key)
    local node = en
    for part in tostring(key):gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return type(node) == "string" and node or nil
end)

local function class()
    local c = {}
    c.__index = c
    function c:is(k) return getmetatable(self) == k end
    return c
end
_G.Card, _G.CardArea, _G.UIBox = class(), class(), class()
_G.Back = setmetatable({}, { __call = function(_, center)
    return { generate_UI = function()
        return { { n = 1, config = { text = center.key .. " effect" } } }
    end }
end })

_G.G = {
    UIT = { T = 1, O = 2, C = 3, R = 4, ROOT = 5 },
    C = {},
    sticker_map = { stake_white = "white", stake_gold = "gold" },   -- Steamodded's shape
    P_STAKES = {},
    P_CENTER_POOLS = { Stake = {} },
}

local Graph = ba_require("overlay.graph")
local MB = ba_require("overlay.message_builder")
local RunSelect = ba_require("overlays.run_select")
local Proxy = ba_require("ui.proxies").Proxy

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function node(cfg, children)
    return { config = cfg or {}, children = children or {},
        states = { visible = true, hover = { can = true } } }
end

-- --- The screen ----------------------------------------------------------------
local choices = { deck_choice = "b_blue" }
local function deck_card(key, unlocked)
    local c = setmetatable({
        facing = "back",
        params = { run_select_selection_choice = { 1, "deck_choice" } },
        config = { center = { key = key, set = "Back", unlocked = unlocked } },
    }, Card)
    function c:click() choices.deck_choice = self.config.center.key end
    return c
end
local keys = { "b_red", "b_blue", "b_yellow", "b_red", "b_blue", "b_yellow", "b_red" }
local areas, area_nodes = {}, {}
for i, k in ipairs(keys) do
    local a = setmetatable({ cards = { deck_card(k, i ~= 3) } }, CardArea)
    areas[i] = a
    area_nodes[i] = node({ object = a, focus_args = { snap_to = true } })
end
areas[1].cards[1].sticker = "gold"

local page_label = { page = 1, text = "Page 1/2" }
local pass = { page_label = page_label }
local function arrow(dir)
    local n = node({ button = "cycler_default", pass_through = pass, direction = dir })
    function n:click()
        page_label.page = page_label.page == 1 and 2 or 1
        page_label.text = "Page " .. page_label.page .. "/2"
    end
    return n
end

local next_clicks = 0
local slot   -- the run_select slot, declared below
local next_btn = node({ id = "next_selection", button = "run_select_change_page" })
function next_btn:click()
    -- The game swaps the page's UIBox (here: a fresh box, same content).
    next_clicks = next_clicks + 1
    slot.config.object = setmetatable({ UIRoot = slot.config.object.UIRoot }, UIBox)
end
local random_btn = node({ button = "random_type" })
function random_btn:click() choices.deck_choice = "b_yellow" end

local page_root = node({}, {
    node({}, { node({}, { area_nodes[1], area_nodes[2], area_nodes[3], area_nodes[4], area_nodes[5] }),
               node({}, { area_nodes[6], area_nodes[7] }) }),
    node({}, { arrow(-1), arrow(1) }),
    random_btn,
})
local page_box = setmetatable({ UIRoot = page_root }, UIBox)
slot = node({ id = "run_select", object = page_box })
local overlay_root = node({}, { slot, node({}, { node({ id = "previous_selection" }), next_btn }) })
G.OVERLAY_MENU = setmetatable({ UIRoot = overlay_root }, UIBox)
function G.OVERLAY_MENU:get_UIE_by_ID(id)
    if id == "run_select" then return slot end
    if id == "next_selection" then return next_btn end
end

local pool = {}
for i = 1, 15 do pool[i] = { key = "b_" .. i } end
local smods = {
    RunSelect = {
        Internals = {
            pages = { "deck_choice", "stake_choice" }, current_page = 1,
            select_areas = areas,
            next_button_text = "Select Stake >", previous_button_text = "",
        },
        Setup = { choices = choices },
        Pages = {
            deck_choice = { key = "deck_choice", type = "Back", grid_size = { 2, 5 },
                amount = 10, pool = pool, automatic_preview = true,
                selected_text = function(self, c) return NAMES.Back[c] end },
            stake_choice = { key = "stake_choice", type = "Stake" },
        },
    },
}

-- --- Vanilla: inert ------------------------------------------------------------
check(RunSelect:handler() == "inactive", "no Steamodded: inactive", RunSelect:handler())

_G.SMODS = smods
check(RunSelect:handler() == "active", "Steamodded screen: active", RunSelect:handler())

local function render()
    local b = Graph.new()
    RunSelect:build(b)
    return b:build()
end
local function label(r, key)
    local m = MB.new()
    r.nodes[key].vtable.label({ message = m, mods = {} })
    return m:build()
end
local function click(r, key)
    local m = MB.new()
    r.nodes[key].vtable.on_click({ message = m, mods = {} })
    return m:build()
end

-- Opening the screen starts on the tabs, not the grid.
local tab = node({ focus_args = { type = "tab" } })
table.insert(overlay_root.children, 1, tab)
local r = render()
check(r.start_key == "tab:1", "opening starts on the tabs", r.start_key)
table.remove(overlay_root.children, 1)
r = render()
check(r.start_key == "grid:2", "no tabs: lands on the selected deck", r.start_key)
check(r.nodes["grid:1"].trans.right.to == "grid:2", "left/right within a row", r.nodes["grid:1"].trans.right.to)
check(r.nodes["grid:2"].trans.down.to == "grid:7", "down keeps the column", r.nodes["grid:2"].trans.down.to)
check(r.nodes["grid:4"].trans.down.to == "grid:7", "down clamps to a shorter row", r.nodes["grid:4"].trans.down.to)
check(r.nodes["grid:7"].trans.up.to == "grid:2", "up keeps the column", r.nodes["grid:7"].trans.up.to)
check(not r.nodes["nav:prev"], "no Previous on the first page", r.nodes["nav:prev"])

local l = label(r, "grid:2")
check(l == "Blue Deck selected", "deck label: name, selected", l)
l = label(r, "grid:1")
check(l == "Red Deck Gold Stake sticker", "win sticker names its stake (Steamodded map)", l)
check(label(r, "grid:3") == "Locked", "locked deck reads Locked", label(r, "grid:3"))

local d = r.nodes["grid:1"].vtable.deferred()
check(d and d:find("b_red effect", 1, true) and d:find("1 of 15", 1, true),
    "deferred: description then position in the pool", d)

local m = click(r, "grid:3")
check(m == "locked" and choices.deck_choice == "b_blue", "locked deck refuses selection", m)
m = click(r, "grid:1")
check(m == "selected" and choices.deck_choice == "b_red", "Enter selects a new deck", m)
m = click(r, "grid:1")
check(m == nil, "Enter on the selected deck stays quiet (the game advances)", m)

check(label(r, "pager") == "Page 1/2 slider", "page cycle label", label(r, "pager"))
local mm = MB.new()
r.nodes["pager"].vtable.on_horizontal_adjust({ message = mm, mods = {} }, 1)
check(mm:build() == "Page 2/2", "page cycle adjusts and speaks", page_label.text)

check(label(r, "summary") == "Red Deck, selected", "selection summary", label(r, "summary"))
m = click(r, "random")
check(m and m:find("Yellow Deck, selected", 1, true), "Random speaks the new selection", m)
check(label(r, "nav:next") == "Select Stake button", "Next names its page", label(r, "nav:next"))

-- Next swaps the page box: the press speaks the new page's title, and the
-- fresh page lands on its selection.
table.insert(overlay_root.children, 1, tab)
m = click(r, "nav:next")
check(m and m:find("Select Deck", 1, true), "a page change speaks the page title", m)
RunSelect:handler()
r = render()
check(r.start_key == "grid:3", "a page change lands on the selection (Yellow, from Random)", r.start_key)

-- Entering the grid from the tabs crosses the title.
local tr = r.nodes["tab:1"].trans.down
local tm = MB.new()
if tr and tr.label then tr.label({ message = tm, mods = {} }) end
check(tm:build() == "Select Deck", "down from the tabs says the page title", tr and tr.to)

-- Leaving the screen (tab switch): inactive.
slot.config.object = nil
check(RunSelect:handler() == "inactive", "slot gone: inactive", RunSelect:handler())

-- Win stickers under vanilla's array-shaped sticker_map.
G.sticker_map = { "White", "Red" }
G.P_CENTER_POOLS.Stake = { { key = "stake_white" }, { key = "stake_red" } }
check(Proxy.sticker_stake_name("Red") == "Red Stake", "vanilla sticker map", Proxy.sticker_stake_name("Red"))
check(Proxy.sticker_stake_name("Purple") == "Purple", "unknown sticker falls back to its word",
    Proxy.sticker_stake_name("Purple"))

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
