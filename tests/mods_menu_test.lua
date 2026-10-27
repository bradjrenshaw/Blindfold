-- Harness: Steamodded's Mods menu — inert without Steamodded; each mod a
-- row (card with name / version or Lovely Mod / authors, enable checkbox
-- and config button named for the mod); and Blindfold's own checkbox needs
-- a second press to switch Blindfold off (it silences speech after the
-- restart), while switching it back on is immediate.
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

local now = 0
_G.love = { filesystem = { write = function() end, read = function() return nil end,
    append = function() end }, timer = { getTime = function() return now end } }
local STRINGS = { b_lovely_mod = "(Lovely Mod) ", b_by = "By: ", b_config = "Config" }
_G.localize = function(a) return STRINGS[a] or "ERROR" end

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
local MB = ba_require("overlay.message_builder")
local Mods = ba_require("overlays.mods_menu")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function node(cfg, children)
    return { config = cfg or {}, children = children or {},
        states = { visible = true, hover = { can = true } } }
end

local amulet = { id = "Amulet", name = "Amulet", version = "3.6.1", author = { "frostice482", "..." },
    should_enable = true }
local blindfold = { id = "lovely-compat-Blindfold", name = "Blindfold", lovely_only = true,
    blacklist_name = "Blindfold", should_enable = true }

-- A create_toggle stand-in: clicking flips ref_table[ref_value].
local function toggle(mod)
    local n = node({ button = "toggle_button", ref_table = { ref_table = mod, ref_value = "should_enable" } })
    function n:click() mod.should_enable = not mod.should_enable end
    return n
end

G.OVERLAY_MENU = setmetatable({ UIRoot = node({}, {
    node({ button = "openModUI_Amulet" }), toggle(amulet), node({ button = "openModUI_Amulet", page = "config" }),
    node({ button = "openModUI_lovely-compat-Blindfold" }), toggle(blindfold),
    node({ id = "overlay_menu_back_button", button = "exit_mods" }),
}) }, UIBox)

check(Mods:handler() == "inactive", "no Steamodded: inactive", Mods:handler())
_G.SMODS = { Mods = { Amulet = amulet, ["lovely-compat-Blindfold"] = blindfold } }
check(Mods:handler() == "active", "Steamodded Mods tab: active", Mods:handler())

local b = Graph.new(); Mods:build(b); local r = b:build()
local function label(key)
    local m = MB.new()
    r.nodes[key].vtable.label({ message = m, mods = {} })
    return m:build()
end
local function click(key)
    local m = MB.new()
    r.nodes[key].vtable.on_click({ message = m, mods = {} })
    return m:build()
end

check(label("card:Amulet") == "Amulet, 3.6.1, By: frostice482, ... button", "card: name, version, authors",
    label("card:Amulet"))
check(label("card:lovely-compat-Blindfold"):find("^Blindfold, %(Lovely Mod%)"), "lovely mod card",
    label("card:lovely-compat-Blindfold"))
check(label("config:Amulet") == "Amulet Config button", "config button named for the mod", label("config:Amulet"))
check(r.nodes["card:Amulet"].trans.right.to == "toggle:Amulet", "row: card then checkbox",
    r.nodes["card:Amulet"].trans.right.to)
check(r.nodes["card:Amulet"].trans.down.to == "card:lovely-compat-Blindfold", "down moves to the next mod",
    r.nodes["card:Amulet"].trans.down.to)

-- Other mods toggle straight away.
click("toggle:Amulet")
check(amulet.should_enable == false, "another mod's checkbox toggles on the first press", amulet.should_enable)

-- Blindfold: warn first, switch off on the second press, back on at once.
local m = click("toggle:lovely-compat-Blindfold")
check(m == en.MENU.DISABLE_BLINDFOLD and blindfold.should_enable == true,
    "first press on Blindfold only warns", m)
now = 3
click("toggle:lovely-compat-Blindfold")
check(blindfold.should_enable == false, "second press within the window switches it off", blindfold.should_enable)
click("toggle:lovely-compat-Blindfold")
check(blindfold.should_enable == true, "switching it back on needs no confirmation", blindfold.should_enable)
now = 20
m = click("toggle:lovely-compat-Blindfold")
check(m == en.MENU.DISABLE_BLINDFOLD and blindfold.should_enable == true,
    "the confirmation expires: warns again", m)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
