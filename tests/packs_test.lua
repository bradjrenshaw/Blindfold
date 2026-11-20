-- Harness: the packs overlay's lifecycle gates — the close-animation window
-- (pack on screen, state already flipped back) must cede the screen and
-- refuse picks (a use_card fired there crashes the game at
-- button_callbacks.lua:2298; user crash report).
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
_G.localize = function(v) return tostring(v) end

local Packs = ba_require("overlays.packs")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local tarot = { ability = { set = "Tarot" } }
_G.G = {
    STAGES = { RUN = 2 }, STAGE = 2,
    STATES = { SELECTING_HAND = 1, SHOP = 5, BLIND_SELECT = 7, TAROT_PACK = 9,
        PLANET_PACK = 10, SPECTRAL_PACK = 15, STANDARD_PACK = 17, BUFFOON_PACK = 18 },
    STATE = 9,
    GAME = { pack_choices = 1 },
    pack_cards = { cards = { tarot } },
}

-- Deal-in: pending until the card count holds still, then active.
local v
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "open pack settles to active", v)
check(Packs.pick_allowed() == true, "pick allowed while the pack is live", Packs.pick_allowed())

-- The last pick closes the pack: from the pick until it is gone the overlay
-- stays engaged but quiet, so the card the cursor would land on (the picked
-- one leaves the area at once) is not read out as if it were another choice.
local Graph = ba_require("overlay.graph")
local function pick_first()
    local b = Graph.new()
    Packs:build(b)
    local first = G.pack_cards.cards[1]
    b:build().nodes[first].vtable.on_click({ message = { fragment = function() end } })
end
local used = 0
local function planet() return { ability = { set = "Planet", consumeable = {} },
    can_use_consumeable = function() return true end } end
G.FUNCS = { use_card = function(e)
    used = used + 1
    -- What the game does synchronously: the card leaves, the pack slides away.
    table.remove(G.pack_cards.cards, 1)
    G.CONTROLLER.locks.use = true
    G.booster_pack.alignment.offset.py = 0
end }
G.CONTROLLER = { locks = {} }
G.booster_pack = { alignment = { offset = {} } }
G.pack_cards.cards = { planet(), planet(), planet() }
G.GAME.pack_choices = 1
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "a one-choice pack, settled", v)
pick_first()
check(used == 1, "the pick went through", used)
v = Packs:handler()
check(v == "pending", "after the last pick: engaged but quiet", v)
G.CONTROLLER.locks.use = false        -- the use finished; the pack is on its way out
check(Packs:handler() == "pending", "still quiet while the pack slides away", "?")
G.booster_pack = nil                  -- torn down, state not yet restored
check(Packs:handler() == "pending", "and until the state flips back", "?")
G.STATE = G.STATES.SHOP
G.pack_cards.REMOVED = true
check(Packs:handler() == "inactive", "then it stands down", "?")
G.pack_cards.REMOVED = nil
G.STATE = G.STATES.TAROT_PACK

-- A "choose 2" pack: the first pick leaves a choice, so the overlay stays
-- active and the card the cursor lands on is read; the second pick closes it.
G.booster_pack = { alignment = { offset = {} } }
G.pack_cards.cards = { planet(), planet(), planet() }
G.GAME.pack_choices = 2
for _ = 1, 20 do v = Packs:handler() end
pick_first()
check(Packs:handler() == "active", "a pick with choices left stays active", Packs:handler())
G.CONTROLLER.locks.use = false
G.booster_pack.alignment.offset.py = nil   -- the pack came back for the next pick
G.GAME.pack_choices = 1
check(Packs:handler() == "active", "and stays active for the second choice", "?")
pick_first()
check(Packs:handler() == "pending", "the second (last) pick goes quiet", "?")

-- A last pick that did not close the pack after all (it is back in place,
-- the use lock released): not quiet forever.
G.CONTROLLER.locks.use = false
G.booster_pack.alignment.offset.py = nil
check(Packs:handler() == "active", "a pack that came back is active again", "?")
G.pack_cards.cards = { tarot }
G.GAME.pack_choices = 1

-- The close window: state flipped back to blind select (tag pack), pack area
-- still on screen. Cede AND refuse picks.
G.STATE = G.STATES.BLIND_SELECT
v = Packs:handler()
check(v == "inactive", "close-to-blinds cedes the screen", v)
check(Packs.pick_allowed() == false, "no picks into the teardown", Packs.pick_allowed())

-- Same once the area is torn down, whatever the state says.
G.STATE = G.STATES.TAROT_PACK
G.pack_cards.REMOVED = true
check(Packs.pick_allowed() == false, "no picks on a removed area", Packs.pick_allowed())
G.pack_cards.REMOVED = nil

-- The reload bounce (state stuck at SHOP with the pack up) is still claimed
-- and repaired: the handler puts the state back to what the contents imply.
G.STATE = G.STATES.SHOP
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "SHOP bounce is still claimed", v)
check(G.STATE == G.STATES.TAROT_PACK, "and the state is repaired from contents", G.STATE)
check(G.GAME.PACK_INTERRUPT == G.STATES.SHOP, "PACK_INTERRUPT restored for the close path", G.GAME.PACK_INTERRUPT)

-- Steamodded: every pack opens in SMODS_BOOSTER_OPENED. Claimed like the
-- vanilla pack states, and the reload repair restores THAT state (a vanilla
-- one would skip Steamodded's pack handling).
G.STATES.SMODS_BOOSTER_OPENED = 999
G.STATES.SMODS_REDEEM_VOUCHER = 998
G.STATE = 999
G.GAME.PACK_INTERRUPT = nil
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "Steamodded pack state is claimed", v)
check(Packs.pick_allowed() == true, "and picks are allowed", Packs.pick_allowed())
G.STATE = G.STATES.SHOP
for _ = 1, 20 do v = Packs:handler() end
check(G.STATE == 999, "reload repair restores Steamodded's pack state", G.STATE)

local States = ba_require("ui.states")
check(States.is_voucher_redeem(998) and not States.is_pack(998), "voucher redeem is its own state", States.is_pack(998))

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
