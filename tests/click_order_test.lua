-- Harness: the click-order play style through the real do_play/do_discard —
-- selection order becomes scoring order via the T.x quick-drag.
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
_G.localize = function() return "x" end

local Settings = ba_require("settings.registry")
local Play = ba_require("overlays.play")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- Hand of three cards at x = 1, 2, 3 (hand order a, b, c); the player
-- clicked c then a. The game FUNCS stub does exactly what the real one does:
-- sort highlighted by T.x (state_events.lua:463), then record the order.
local a = { name = "a", T = { x = 1 } }
local b = { name = "b", T = { x = 2 } }
local c = { name = "c", T = { x = 3 } }
local played
local function funcs_play()
    table.sort(G.hand.highlighted, function(p, q) return p.T.x < q.T.x end)
    played = {}
    for i, card in ipairs(G.hand.highlighted) do played[i] = card.name end
end
local function order() return table.concat(played, ",") end

_G.G = {
    STATES = { SELECTING_HAND = 1 }, STATE = 1,
    GAME = { current_round = { discards_left = 3 } },
    hand = { highlighted = { c, a }, cards = { a, b, c } },
    play = { cards = {} },
    FUNCS = { play_cards_from_highlighted = funcs_play,
              discard_cards_from_highlighted = funcs_play },
}

-- Toggle ON: click order (c, a) wins over hand order.
Settings.values["play.click_order"] = true
Play.do_play()
check(order() == "c,a", "play scores in click order", order())
check(b.T.x == 2, "unselected cards untouched", b.T.x)

-- Same through discard.
a.T.x, c.T.x = 1, 3
G.hand.highlighted = { c, a }
Play.do_discard()
check(order() == "c,a", "discard follows click order too", order())

-- Toggle OFF: hand order (by x) as always.
Settings.values["play.click_order"] = false
a.T.x, c.T.x = 1, 3
G.hand.highlighted = { c, a }
Play.do_play()
check(order() == "a,c", "toggle off keeps hand order", order())

-- Single selection: nothing to reorder either way.
Settings.values["play.click_order"] = true
a.T.x, c.T.x = 1, 3
G.hand.highlighted = { c }
Play.do_play()
check(order() == "c" and c.T.x == 3, "single card is a no-op", order())

-- --- The "selection N" focus announcement -----------------------------------

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
_G.localize = function(v) return tostring(v) end

local PC = ba_require("ui.proxies").PlayingCard
local function speak(card)
    local m = PC.new(card):get_focus_message()
    return m and m:resolve() or ""
end

local ace = { base = { value = "Ace", suit = "Spades" }, config = { center = {} },
    highlighted = true }
ace.area = G.hand
G.hand.highlighted = { c, ace }

-- Toggle ON: "selection 2" right after the name, replacing "selected".
Settings.values["play.click_order"] = true
local s = speak(ace)
check(s:find("Ace of Spades, selection 2, card", 1, true) == 1
    and not s:find("selected"), "focus speaks the selection position", s)

-- Toggle OFF: the plain "selected" word, no position.
Settings.values["play.click_order"] = false
s = speak(ace)
check(s:find("selected") and not s:find("selection %d"),
    "toggle off keeps the plain selected word", s)

-- ON but the card is somehow untracked: fall back to "selected".
Settings.values["play.click_order"] = true
G.hand.highlighted = { c }
s = speak(ace)
check(s:find("selected") and not s:find("selection %d"),
    "untracked highlighted card falls back to selected", s)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
