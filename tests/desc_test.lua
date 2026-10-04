-- Harness: custom-rendered card bodies through Proxy.card_description —
-- Misprint's range, Blueprint/Brainstorm compatibility, undiscovered gate.
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
_G.localize = function(a)
    if a == "k_mult" then return "Mult" end
    if a == "k_compatible" then return "Compatible" end
    if a == "k_incompatible" then return "Incompatible" end
    return "ERROR"
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

_G.G = { UIT = { T = 1, O = 2, C = 3, R = 4 }, jokers = { cards = {} } }
local Proxy = ba_require("ui.proxies").Proxy

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- Misprint, discovered: one churn snapshot ("+7 Mult" / "+3 rand()" /
-- "+12 #@11D"), then the explanation. Rolled like the render's cyclers, so
-- verify statistically: every draw well-formed and in range, and across many
-- draws all three tail forms appear (deck bottom = Jack of Diamonds).
G.deck = { cards = { { base = { id = 11, suit = "Diamonds" } } } }
math.randomseed(42)
local misprint = {
    ability = { name = "Misprint", set = "Joker", extra = { min = 0, max = 23 } },
    config = { center = { unlocked = true, discovered = true } },
}
local ok_all, seen, numbers_ok = true, {}, true
local sample
for _ = 1, 400 do
    local d = Proxy.card_description(misprint)
    sample = sample or d
    local n, tail = d:match("^%+(%d+) (.+), %+0 to %+23 Mult, random$")
    if not n then ok_all = false; sample = d; break end
    if tonumber(n) < 0 or tonumber(n) > 23 then numbers_ok = false end
    seen[tail] = true
end
check(ok_all, "Misprint: churn snapshot then explanation", sample)
check(numbers_ok, "churn numbers stay in 0..23", sample)
check(seen["Mult"] and seen["rand()"] and seen["#@11D"],
    "all three churn tails appear (incl. the bottom-card glitch)",
    (seen["Mult"] and "Mult " or "") .. (seen["rand()"] and "rand() " or "")
        .. (seen["#@11D"] and "#@11D" or ""))

-- Misprint, undiscovered in the shop: falls to the generic path (the game's
-- own '?' description), never the range.
local hidden = {
    ability = { name = "Misprint", set = "Joker", extra = { min = 0, max = 23 } },
    config = { center = { unlocked = true, discovered = false } },
    generate_UIBox_ability_table = function()
        return { main = { { n = 1, config = { text = "?????" } } } }
    end,
}
check(Proxy.card_description(hidden) == "?????",
    "undiscovered Misprint stays hidden", Proxy.card_description(hidden))

-- Blueprint in the joker row: the compat box's ref-bound text is pre-synced
-- from the live state, so the scrape reads it in place.
local bp_ability = { name = "Blueprint", set = "Joker", blueprint_compat = "compatible" }
local blueprint = {
    ability = bp_ability,
    config = { center = { unlocked = true, discovered = true } },
    generate_UIBox_ability_table = function()
        return { main = {
            { n = 1, config = { text = "Copies ability of Joker to the right" } },
            { n = 3, config = { ref_table = bp_ability, ref_value = "blueprint_compat_ui" } },
        } }
    end,
}
local d = Proxy.card_description(blueprint)
check(d and d:find("Compatible"), "Blueprint speaks Compatible", d)

bp_ability.blueprint_compat = "incompatible"
d = Proxy.card_description(blueprint)
check(d and d:find("Incompatible"), "Blueprint flips to Incompatible", d)

-- No state yet (fresh spawn before Card:update ran): no crash, no stale word.
bp_ability.blueprint_compat = nil
bp_ability.blueprint_compat_ui = nil
d = Proxy.card_description(blueprint)
check(d == "Copies ability of Joker to the right",
    "no compat state yet: description alone", d)

-- Issue #2: the game's builders instantiate live DynaTexts (card names, {E:}
-- parts) that self-register in G.MOVEABLES, drawn and updated every frame
-- until delete_run. Scraping must read their text, then remove them.
local function fake_dynatext(s)
    local o = { strings = { { string = s } } }
    function o:remove()
        for i, v in ipairs(G.MOVEABLES) do
            if v == self then table.remove(G.MOVEABLES, i); break end
        end
        self.REMOVED = true
    end
    G.MOVEABLES[#G.MOVEABLES + 1] = o
    return o
end
local resident = { remove = function() error("pre-existing object removed") end }
G.MOVEABLES = { resident }
local joker = {
    ability = { name = "Joker", set = "Joker" },
    config = { center = { unlocked = true, discovered = true } },
    generate_UIBox_ability_table = function()
        return {
            name = { { n = 2, config = { object = fake_dynatext("Joker") } } },
            main = { { n = 2, config = { object = fake_dynatext("+4 Mult") } } },
            info = { { name = "Foil", { n = 2, config = { object = fake_dynatext("+50 chips") } } } },
        }
    end,
}
d = Proxy.card_description(joker)
check(d == "+4 Mult", "leak: DynaText text still scraped", d)
check(#G.MOVEABLES == 1 and G.MOVEABLES[1] == resident,
    "leak: description build's objects removed, residents kept", #G.MOVEABLES)
local tips = Proxy.card_info_tips(joker)
check(tips[1] and tips[1]:find("+50 chips", 1, true), "leak: keyword tip still scraped", tips[1])
check(#G.MOVEABLES == 1, "leak: keyword-tip build's objects removed", #G.MOVEABLES)
-- A builder that errors midway still gets its partial objects cleaned up.
joker.generate_UIBox_ability_table = function()
    fake_dynatext("half")
    error("boom")
end
Proxy.card_description(joker)
check(#G.MOVEABLES == 1, "leak: failed build's partial objects removed", #G.MOVEABLES)
-- Skip tags: get_uibox_table fills the sprite's cached table the same way.
local tag = { get_uibox_table = function()
    return { ability_UIBox_table = { main = { { n = 2, config = { object = fake_dynatext("Free Rare Joker") } } } } }
end }
d = Proxy.tag_description(tag)
check(d == "Free Rare Joker", "leak: tag description scraped", d)
check(#G.MOVEABLES == 1, "leak: tag build's objects removed", #G.MOVEABLES)
G.MOVEABLES = nil

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
