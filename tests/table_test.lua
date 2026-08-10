-- Harness: the run-hands TABLE overlay through the real dispatcher/keygraph.
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

-- Stubs the modules touch at load/run time.
_G.love = { filesystem = { write = function() end, read = function() return nil end,
    append = function() end } }
_G.create_UIBox_hand_tip = function() end
_G.localize = function(key, cat)
    if key == "k_level_prefix" then return "lvl." end
    if cat == "poker_hands" then return key end
    if cat == "poker_hand_descriptions" then return { key .. " description" } end
    return tostring(key)
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

-- Fake game state: an overlay whose tree contains one full hands row (the
-- structural detector), and three visible hands.
local hands_row = {
    config = { on_demand_tooltip = { filler = { func = _G.create_UIBox_hand_tip } } },
    children = { { config = { text = "  #" } } },
}
-- The rows live inside an EMBEDDED UIBox (tab contents behind UIT.O), like
-- the real run info screen — the detection walk must descend it. A fake tab
-- strip control sits above, as run info's does.
_G.UIBox = {}
local tab_contents = {
    UIRoot = { children = { hands_row } },
    is = function(self, k) return k == _G.UIBox end,
}
local tab_strip = {
    UIT = 1,
    config = { focus_args = { type = "tab" } },
    states = { visible = true, hover = { can = true } },
    children = {},
    _label = "Poker Hands, tab",
}
_G.G = {
    OVERLAY_MENU = { UIRoot = { children = {
        tab_strip,
        { config = { object = tab_contents } },
    } } },
    GAME = { hands = {
        ["Flush"]     = { visible = true, level = 2, chips = 35, mult = 4, played = 3 },
        ["Pair"]      = { visible = true, level = 1, chips = 10, mult = 2, played = 7 },
        ["High Card"] = { visible = true, level = 1, chips = 5,  mult = 1, played = 12 },
        ["Two Pair"]  = { visible = false, level = 1, chips = 20, mult = 2, played = 0 },
    } },
}

local D = ba_require("overlay.dispatcher")
local RunHands = ba_require("overlays.run_hands")
D.register(RunHands)

-- Stub the mirror's vtable factory: the fake tab strip isn't a real game
-- widget, and only its label/identity matter to this harness.
local Mirror = ba_require("overlays.menu_mirror")
local MessageM = ba_require("ui.message")
Mirror.vtable_for = function(n)
    return { label = function(ctx)
        ctx.message:fragment(MessageM.raw(n._label or "control"))
    end }
end

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- Fresh open: focus lands on the TAB STRIP, not in the table.
local res = D.tick(nil)
check(res and res.message == "Poker Hands, tab", "open lands on the tab strip", res and res.message)

-- Down enters the table on the first hand's PRIMARY, which reads the whole
-- row (name, level, headered values, then the requirements).
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message == "Flush, lvl.2, chips 35, mult 4, played 3, Flush description",
    "down enters the full first row", res and res.message)

-- Right: crossing speaks the destination COLUMN header, then the cell.
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message:find("level") and res.message:find("lvl%.2"),
    "right into level: header + cell", res and res.message)

-- Down (in the level column): destination ROW name, then its level.
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message:find("Pair") and res.message:find("lvl%.1"),
    "down stays in column, names the row", res and res.message)

-- Right twice: chips then mult, each with headers.
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message:find("chips") and res.message:find("10"),
    "chips cell with header", res and res.message)
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message:find("mult") and res.message:find("2"),
    "mult cell with header", res and res.message)

-- Right twice more: played, then the REQUIREMENTS column at the right edge.
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message:find("played") and res.message:find("7"),
    "played cell with header", res and res.message)
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message:find("requirements") and res.message:find("Pair description"),
    "requirements is the rightmost column", res and res.message)
-- Down in the requirements column: next row's requirements, row named.
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message:find("High Card") and res.message:find("High Card description"),
    "requirements column walks", res and res.message)
-- Back to mult for the remaining checks.
res = D.tick({ kind = "move", dir = "left" })
res = D.tick({ kind = "move", dir = "left" })
check(res and res.message:find("mult") and res.message:find("1"),
    "column walk continues", res and res.message)

-- Left back to the played... left goes to chips (col 2) with its header.
res = D.tick({ kind = "move", dir = "left" })
check(res and res.message:find("chips") and res.message:find("5"),
    "left crossing names destination header", res and res.message)

-- All the way left: the primary reads its full row (no crossing header).
res = D.tick({ kind = "move", dir = "left" })
res = D.tick({ kind = "move", dir = "left" })
check(res and res.message == "High Card, lvl.1, chips 5, mult 1, played 12, High Card description",
    "primary reads the full row", res and res.message)

-- Up the name column: the previous row's FULL readout, unlabeled crossing.
res = D.tick({ kind = "move", dir = "up" })
check(res and res.message == "Pair, lvl.1, chips 10, mult 2, played 7, Pair description",
    "name column walks read whole rows", res and res.message)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
