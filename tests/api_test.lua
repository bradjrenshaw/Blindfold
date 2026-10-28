-- Harness: the mod-author API (src/docs/mod-api.md). Layer 1, hints in UI
-- definitions: a label / hint replaces or extends what a control reads; a
-- sprite's text is read where text is read; hidden nodes drop out of the
-- text and the mirror walk. Layer 2, the Blindfold table: card_info lines
-- (registered or on the center), the load-order queue, mod buffers with
-- their own labels, announce into the events history; a re-run install (hot
-- reload) keeps registrations without duplicating them.
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

local Factory = ba_require("ui.factory")
local Proxy = ba_require("ui.proxies").Proxy
local Mirror = ba_require("overlays.menu_mirror")
local MB = ba_require("overlay.message_builder")
local Api = ba_require("api.public")
local Buffers = ba_require("buffers.manager")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local function node(cfg, children, uit)
    local n = { config = cfg or {}, children = children or {}, UIT = uit or G.UIT.C,
        states = { visible = true, hover = { can = true } } }
    for _, c in ipairs(n.children) do c.parent = n end
    return n
end
local function text(s) return node({ text = s }, nil, G.UIT.T) end
local function spoken(n)
    local m = MB.new()
    Mirror.vtable_for(n).label({ message = m, mods = {} })
    return m:build()
end

-- ---- Layer 1: hints ------------------------------------------------------
local icon = node({ button = "mymod_reroll", blindfold = "Reroll bonus" }, { node({ object = {} }, nil, G.UIT.O) })
check(spoken(icon):find("^Reroll bonus"), "string hint labels an icon button", spoken(icon))

local bonus = 2
local live = node({ button = "mymod_x", blindfold = {
    label = function() return "Bonus " .. bonus end, hint = "Costs 2 dollars" } }, { text("ignored") })
local s = spoken(live)
check(s:find("^Bonus 2") and s:find("Costs 2 dollars", 1, true) and not s:find("ignored"),
    "function label + hint replace the text", s)
bonus = 3
check(spoken(live):find("^Bonus 3"), "function label is read live", spoken(live))

local p = Factory.create(node({ button = "mymod_y", blindfold = { label = function() error("boom") end } },
    { text("Fallback") }))
check(p:get_label():resolve() == "Fallback", "a failing label falls back to the text", p:get_label():resolve())

local panel = node({}, {
    node({ object = {}, blindfold = { text = "Bonus ready" } }, { text("junk") }, G.UIT.O),
    node({ blindfold = { hidden = true } }, { text("sparkles") }),
    text("Shop"),
})
check(Proxy.static_text(panel) == "Bonus ready Shop", "sprite text read, hidden subtree skipped",
    Proxy.static_text(panel))
local hidden_btn = node({}, { node({ button = "deco", blindfold = { hidden = true } }), node({ button = "real" }) })
local got = Mirror.gather({ hidden_btn })
check(#got == 1 and got[1].config.button == "real", "hidden control left out of the walk", #got)

-- ---- Layer 2: the Blindfold table ------------------------------------------
_G.BlindfoldHost = {}
local said, emitted = {}, {}
local deps = {
    say = function(t, i) said[#said + 1] = { t, i } end,
    emit = function(g, t) emitted[#emitted + 1] = g .. ":" .. t end,
    buffers = Buffers,
}
_G.BLINDFOLD_QUEUE = { function(BF) BF.card_info("queued", function() return "from the queue" end) end }
local BF = {}
Api.install(BF, deps)
check(BF.api_version == 1, "api_version", BF.api_version)
check(#_G.BLINDFOLD_QUEUE == 0, "queue drained at install")

BF.card_info("charge", function(card) return card.ability.charge .. " charges" end)
BF.card_info("broken", function() error("nope") end)
local card = setmetatable({ ability = { charge = 4 }, config = { center = {
    blindfold = { info = function() return { "Center line", "" } end } } } }, Card)
local lines = table.concat(Api.card_lines(card), " | ")
check(lines == "from the queue | 4 charges | Center line", "card lines: registered, then center", lines)
BF.card_info("charge", function() return "replaced" end)
lines = table.concat(Api.card_lines(card), " | ")
check(lines == "from the queue | replaced | Center line", "same id replaces in place", lines)

table.insert(_G.BLINDFOLD_QUEUE, function(B) B.say("late", { interrupt = true }) end)
Api.drain(BF)
check(said[1] and said[1][1] == "late" and said[1][2] == true, "late queue entries run on drain", said[1] and said[1][1])

BF.announce("Bonus triggered")
check(emitted[1] == "mods:Bonus triggered", "announce goes through the events dispatcher", emitted[1])

local n = 1
check(BF.add_buffer{ key = "stats", label = "My Mod", lines = function() return { "Bonus: " .. n } end },
    "add_buffer accepted")
local b = Buffers.get("mod_stats")
b:update()
check(b and b:current_item() == "Bonus: 1" and b.label() == "My Mod", "mod buffer lines and label",
    b and b:current_item())

-- Hot reload: a fresh install keeps registrations, adds the buffer once more
-- to the (fresh) manager, and doesn't duplicate card_info.
Buffers.buffers = {}
local BF2 = {}
Api.install(BF2, deps)
check(Buffers.get("mod_stats") ~= nil, "buffer re-added after reload")
lines = table.concat(Api.card_lines(card), " | ")
check(lines == "from the queue | replaced | Center line", "card_info survives reload, no duplicates", lines)

check(BF.add_buffer{ key = "x" } == false, "bad buffer spec rejected")

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
