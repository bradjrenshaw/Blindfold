-- Harness: the Screen buffer (buffers/screen) — every visible box's text and
-- controls in reading order: rows top to bottom (a raised box stays in its
-- row), left to right within a row; hidden, removed, off-screen and
-- card-attached boxes left out; only the overlay menu (and what it embeds)
-- while one is up; dollar-sign runs read as a count.
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
_G.G = { UIT = { T = 1, O = 2, C = 3, R = 4, ROOT = 5 }, C = {}, localization = { descriptions = {} },
    ROOM = { T = { w = 20, h = 11 } } }

local Screen = ba_require("buffers.screen")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function text(s)
    return { UIT = G.UIT.T, config = { text = s }, children = {}, states = { visible = true } }
end
local function row(...)
    return { UIT = G.UIT.R, config = {}, children = { ... }, states = { visible = true } }
end
local function box(x, y, ...)
    local root = { UIT = G.UIT.ROOT, config = {}, children = { ... }, states = { visible = true } }
    return setmetatable({ UIRoot = root, role = {}, states = { visible = true },
        VT = { x = x, y = y, w = 3, h = 2 } }, UIBox)
end

local left = box(1, 3.7, row(text("Small Blind")), row(text("Reward: $$$+")))
local raised = box(5, 3.0, row(text("Big Blind")))
local right = box(9, 3.7, row(text("Boss")))
local header = box(1, 1, row(text("Choose your next Blind")))
local hidden = box(1, 5, row(text("hidden")))
hidden.states.visible = false
local removed = box(1, 5, row(text("removed")))
removed.REMOVED = true
local parked = box(1, 27, row(text("Cash Out")))
local popup = box(1, 6, row(text("card popup")))
popup.role.major = setmetatable({}, Card)
G.I = { UIBOX = { right, left, raised, header, hidden, removed, parked, popup } }

local got = table.concat(Screen.lines(), " | ")
check(got == "Choose your next Blind | Small Blind | Reward: $3+ | Big Blind | Boss",
    "reading order; hidden, removed, off-screen and card boxes left out", got)

-- An overlay menu covers the screen: only it and the boxes it embeds.
local menu = box(2, 2, row(text("Settings")))
local embedded = box(3, 4, row(text("Tab contents")))
embedded.role.major = { UIBox = menu }   -- hangs off a node of the menu
G.OVERLAY_MENU = menu
G.I.UIBOX[#G.I.UIBOX + 1] = menu
G.I.UIBOX[#G.I.UIBOX + 1] = embedded
got = table.concat(Screen.lines(), " | ")
check(got == "Settings | Tab contents", "overlay menu: only the menu", got)

Screen:update()
check(Screen:count() == 2 and Screen:current_item() == "Settings", "buffer populated from the lines",
    Screen:count())

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
