-- Harness: the "Other controls" row (overlay/extras) that the gameplay
-- overlays append for controls they don't list themselves — a mod's button
-- on the HUD must be reachable; the overlay's own controls, the vanilla
-- buttons the screens reach through their own keys, buttons on a card's own
-- UIBox, hidden / removed boxes and the overlay menu must not be repeated.
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
_G.G = { UIT = { T = 1, O = 2, C = 3, R = 4, ROOT = 5 }, C = {}, localization = { descriptions = {} } }

local Graph = ba_require("overlay.graph")
local Id = ba_require("overlay.id")
local MB = ba_require("overlay.message_builder")
local Extras = ba_require("overlay.extras")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function node(cfg, children)
    return { config = cfg or {}, children = children or {},
        states = { visible = true, hover = { can = true } } }
end
local function box(root, role) return setmetatable({ UIRoot = root, role = role or {},
    states = { visible = true } }, UIBox) end

local clicks = 0
local mod_btn = node({ button = "mod_thing" }, { node({ text = "Mod Button" }) })
mod_btn.UIT = G.UIT.C
mod_btn.children[1].UIT = G.UIT.T
function mod_btn:click() clicks = clicks + 1 end
local listed = node({ button = "mod_listed" })
local play = node({ button = "play_cards_from_highlighted" })
local hud = box(node({}, { play, listed, mod_btn }))

local card = setmetatable({}, Card)
local on_card = box(node({}, { node({ button = "mod_card_use" }) }), { major = card })
local hidden = box(node({}, { node({ button = "mod_hidden" }) }))
hidden.states.visible = false
local removed = box(node({}, { node({ button = "mod_removed" }) }))
removed.REMOVED = true
local menu = box(node({}, { node({ button = "mod_menu" }) }))
G.OVERLAY_MENU = menu
G.I = { UIBOX = { hud, on_card, hidden, removed, menu } }

local function overlay(b)
    b:start_row("main")
    b:add_clickable(Id.referenced(listed, "btn:listed"), function() end, function() end)
    b:end_row()
end

local b = Graph.new(); overlay(b)
local list = Extras.unlisted(b)
check(#list == 1 and list[1] == mod_btn, "only the unlisted mod button", #list)

Extras.append(b)
local r = b:build()
local n = r.nodes["extra:1"]
check(n ~= nil, "extras row appended")
check(r.nodes["btn:listed"].trans.down and r.nodes["btn:listed"].trans.down.to == "extra:1",
    "down from the overlay's last row reaches it")
local function speak(fn)
    local m = MB.new(); fn({ message = m, mods = {} }); return m:build()
end
local said = speak(r.nodes["btn:listed"].trans.down.label)
check(said == en.CONTAINER.OTHER, "entering the row says Other controls", said)
said = speak(n.vtable.label)
check(said:find("Mod Button", 1, true), "labelled by its text", said)
n.vtable.on_click({ message = MB.new(), mods = {} })
check(clicks == 1, "Enter clicks it", clicks)

-- Nothing extra: no row.
G.I.UIBOX = { box(node({}, { node({ button = "play_cards_from_highlighted" }), listed })) }
b = Graph.new(); overlay(b); Extras.append(b)
check(b:build().nodes["extra:1"] == nil, "no extras: no row")

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
