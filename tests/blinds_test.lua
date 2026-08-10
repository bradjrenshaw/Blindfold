-- Harness: the run-info BLINDS row overlay through the real dispatcher.
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
-- Whole numbers format bare (plain Lua 5.4 tostring keeps a float's ".0";
-- the game's number_format and LuaJIT do not).
_G.number_format = function(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return tostring(n)
end
_G.get_blind_amount = function() return 300 end

local BLIND_NAMES = { bl_small = "Small Blind", bl_big = "Big Blind", bl_head = "The Head" }
local TAG_NAMES = { tag_double = "Double Tag", tag_juggle = "Juggle Tag" }
_G.localize = function(a, cat)
    if type(a) == "table" then
        if a.set == "Blind" and a.type == "name_text" then return BLIND_NAMES[a.key] end
        if a.set == "Blind" and a.type == "raw_descriptions" then
            return a.key == "bl_head" and { "All Heart cards", "are debuffed" } or {}
        end
        if a.set == "Tag" and a.type == "name_text" then return TAG_NAMES[a.key] end
        return "ERROR"
    end
    if cat == "blind_states" then return a end
    if a == "k_or" then return "or" end
    if a == "b_skip_reward" then return "Skip Reward" end
    return tostring(a)
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

-- Fake game state: red-stake run (Small reward stripped), tags on Small/Big.
-- Panels carry rendered text (state chips etc.), so the mirror's control-less
-- tab fallback surfaces the WHOLE tab as one text item — run_blinds must drop
-- that item (it duplicates the row).
local function panel(ty, tag_key)
    return {
        config = { id = ty, func = "blind_choice_handler", ref_table = { run_info = true } },
        children = {
            { UIT = 1, config = { text = ty .. " state chip text" }, children = {} },
            tag_key and {
                config = { id = "tag_container", ref_table = { key = tag_key } },
                children = {},
            } or nil,
        },
    }
end
_G.UIBox = {}
local tab_contents = {
    UIRoot = { UIT = 5, children = {   -- UIT.ROOT, as real UIRoots carry
        panel("Small", "tag_double"), panel("Big", "tag_juggle"), panel("Boss", nil),
    } },
    is = function(self, k) return k == _G.UIBox end,
}
local tab_strip = {
    UIT = 1,
    config = { focus_args = { type = "tab" } },
    states = { visible = true, hover = { can = true } },
    children = {},
    _label = "Blinds, tab",
}
local back_btn = {
    UIT = 1,
    config = { button = "exit_overlay_menu" },
    states = { visible = true, hover = { can = true } },
    children = {},
    _label = "Back, button",
}
_G.G = {
    UIT = { T = 1, R = 2, C = 3, O = 4, ROOT = 5, B = 6 },
    OVERLAY_MENU = { UIRoot = { children = {
        tab_strip,
        { config = { object = tab_contents } },
        back_btn,
    } } },
    GAME = {
        round_resets = {
            blind_ante = 1,
            blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
            blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_head" },
        },
        starting_params = { ante_scaling = 1 },
        modifiers = { no_blind_reward = { Small = true } },
    },
    P_BLINDS = {
        bl_small = { key = "bl_small", mult = 1, dollars = 3 },
        bl_big = { key = "bl_big", mult = 1.5, dollars = 4 },
        bl_head = { key = "bl_head", mult = 2, dollars = 5 },
    },
}

local D = ba_require("overlay.dispatcher")
local RunBlinds = ba_require("overlays.run_blinds")
D.register(RunBlinds)

local Mirror = ba_require("overlays.menu_mirror")
local MessageM = ba_require("ui.message")
Mirror.vtable_for = function(n)
    return { label = function(ctx)
        ctx.message:fragment(MessageM.raw(n._label or "control"))
    end }
end
local Proxy = ba_require("ui.proxies").Proxy
Proxy.announce_enabled = function() return false end   -- keep tag descriptions off

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- Sanity: the mirror's control-less tab fallback DOES surface the tab root as
-- an item here — the overlay's filter is what keeps it out of the graph.
do
    local raw = Mirror.gather({ G.OVERLAY_MENU })
    local has_root = false
    for _, n in ipairs(raw) do
        if n == tab_contents.UIRoot then has_root = true end
    end
    check(has_root, "gather surfaces the whole-tab fallback item", #raw)
end

-- Fresh open lands on the tab strip.
local res = D.tick(nil)
check(res and res.message == "Blinds, tab", "open lands on the tab strip", res and res.message)

-- Down enters the row on Small: Select renders as Current; the reward line is
-- OMITTED (no_blind_reward.Small); the skip tag closes the readout.
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message ==
    "Small Blind, Current, score at least 300, or Skip Reward: Double Tag",
    "Small: state, score, no reward, tag", res and res.message)

-- Right: Big keeps its reward.
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message ==
    "Big Blind, Upcoming, score at least 450, reward 4 dollars, or Skip Reward: Juggle Tag",
    "Big: reward present with tag", res and res.message)

-- Right: the boss adds its effect text, no tag.
res = D.tick({ kind = "move", dir = "right" })
check(res and res.message ==
    "The Head, Upcoming, All Heart cards are debuffed, score at least 600, reward 5 dollars",
    "Boss: effect text, reward, no tag", res and res.message)

-- Down exits to Back; up returns into the row; up again reaches the strip.
res = D.tick({ kind = "move", dir = "down" })
check(res and res.message == "Back, button", "down exits to Back", res and res.message)
res = D.tick({ kind = "move", dir = "up" })
check(res and res.message and res.message:find("Small Blind") == 1,
    "up from Back re-enters the row", res and res.message)
res = D.tick({ kind = "move", dir = "up" })
check(res and res.message == "Blinds, tab", "up reaches the tab strip", res and res.message)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
