-- Harness: which screens the blind/tag gallery claims. It must read the
-- collection's Blinds and Tags pages in both layouts (vanilla sprites on UI
-- nodes; Steamodded's stand-in cards in CardAreas, and its tags page in a
-- nested box with id your_collection_tags_contents), and must NOT claim Run
-- Info's Blinds tab, whose skip-tag sprites sit in an ordinary nested tab
-- box (that tab belongs to run_blinds; claiming it put tags above the tab
-- strip).
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
_G.localize = function() return "ERROR" end

local function class()
    local c = {}
    c.__index = c
    function c:is(k) return getmetatable(self) == k end
    return c
end
_G.Card, _G.CardArea, _G.UIBox = class(), class(), class()
_G.G = { UIT = { T = 1, O = 2, C = 3, R = 4, ROOT = 5 }, C = {} }

local Graph = ba_require("overlay.graph")
local Gallery = ba_require("overlays.blind_gallery")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function node(cfg, children)
    return { config = cfg or {}, children = children or {},
        states = { visible = true, hover = { can = true } } }
end
local function box(root) return setmetatable({ UIRoot = root }, UIBox) end
local function menu(root) G.OVERLAY_MENU = box(root) end
local back = node({ id = "overlay_menu_back_button", button = "exit_overlay_menu" })

local function build()
    local b = Graph.new()
    Gallery:build(b)
    return b:build()
end
local function count_items(r)
    local n = 0
    for k in pairs(r.nodes) do if type(k) ~= "string" then n = n + 1 end end
    return n
end

-- Vanilla collection: blind sprites straight on UIT.O nodes.
local sprites = {}
for i = 1, 6 do sprites[i] = node({ object = { config = { blind = { discovered = true } } } }) end
menu(node({}, { node({}, sprites), back }))
check(Gallery:handler() == "active", "vanilla blinds page claimed", Gallery:handler())
check(count_items(build()) == 6, "vanilla: six blinds listed", count_items(build()))

-- Steamodded blinds page: stand-in cards (config.blind) in CardAreas.
local cards = {}
for i = 1, 5 do
    cards[i] = setmetatable({ facing = "front", config = { blind = { discovered = true } },
        states = { visible = true, hover = { can = true } } }, Card)
end
local area = setmetatable({ cards = cards }, CardArea)
menu(node({}, { node({ object = area }), back }))
check(Gallery:handler() == "active", "Steamodded blinds page claimed", Gallery:handler())
check(count_items(build()) == 5, "Steamodded: the stand-in cards listed once (not again as cards)",
    count_items(build()))

-- Steamodded tags page: tags inside the your_collection_tags_contents box.
local tags = {}
for i = 1, 4 do tags[i] = node({ object = { config = { tag = { key = "tag_" .. i } } } }) end
menu(node({}, { node({ id = "your_collection_tags_contents", object = box(node({}, tags)) }), back }))
check(Gallery:handler() == "active", "Steamodded tags page claimed", Gallery:handler())
check(count_items(build()) == 4, "Steamodded: four tags listed", count_items(build()))

-- Run Info's Blinds tab: skip-tag sprites in an ordinary nested tab box.
local skip_tags = {
    node({ object = { config = { tag = { key = "tag_polychrome" } } } }),
    node({ object = { config = { tag = { key = "tag_juggle" } } } }),
}
local strip = node({ focus_args = { type = "tab" } })
menu(node({}, { strip, node({ object = box(node({}, skip_tags)) }), back }))
check(Gallery:handler() == "inactive", "Run Info Blinds tab left to run_blinds", Gallery:handler())

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
