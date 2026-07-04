-- overlays/shop.lua — the owned shop screen:
--   row 1: your jokers + consumables (one row; sell/use/grab as everywhere)
--   row 2: the main shelf (G.shop_jokers) — Enter buys; U on a consumable
--          buys AND uses it immediately (no slot needed)
--   row 3: the ante's voucher + the booster packs — Enter redeems / opens
--   row 4: Next Round, Reroll
-- Empty shop rows keep a placeholder ("empty") instead of vanishing, so a
-- redeemed voucher slot reads as empty rather than disappearing confusingly.
--
-- Activation drives the game's own FUNCS with a synthesized e (they only read
-- e.config.ref_table / e.config.id): buy_from_shop for wares ('buy_and_use'
-- id for U), use_card for vouchers and boosters (the game's can_redeem /
-- can_open rewrite their buttons to use_card). Affordability is the game's
-- rule — cost > dollars - bankrupt_at — spoken instead of silently ignored,
-- and buy pre-checks G.FUNCS.check_for_buy_space so "No room" is spoken too.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxies = require("ui.proxies").Proxy
local Play = require("overlays.play")

local M = { id = "shop" }

local function say(ctx, loc_key)
    ctx.message:fragment(Message.localized(loc_key))
end

local function can_afford(card)
    local cost = card.cost or 0
    if cost <= 0 then return true end
    return cost <= (G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0)
end

local function proxy_label(node)
    return function(ctx)
        local proxy = Factory.create(node)
        local m = proxy and proxy:get_focus_message()
        if m then ctx.message:fragment(m) end
    end
end

-- --- Ware actions --------------------------------------------------------------

-- After an action removes a ware, propose where focus goes: the next item in
-- its row (then the previous), then the other sale rows, then Next Round.
-- Without this, the reconciler's reference-following tracks the bought card
-- into YOUR property row — technically correct, never what a shopper wants.
--
-- The suggestion is QUEUED on the game's event queue, not applied instantly:
-- the purchase (and for buy-and-use, the consumable's whole effect) runs as
-- queued events, and an instant suggestion re-focused and announced the next
-- ware in the same breath as the action. Queued, it fires after the purchase
-- events — and if a use animation is running (the shop reports pending), it
-- simply sits until the shop reactivates.
local function suggest_next(ctx, card)
    if not ctx.controller then return end
    local ctrl = ctx.controller
    local target
    local area = card.area
    if area and area.cards then
        local idx
        for i, c in ipairs(area.cards) do
            if c == card then idx = i; break end
        end
        if idx then
            local nxt = area.cards[idx + 1] or area.cards[idx - 1]
            if nxt then target = Id.for_object(nxt) end
        end
    end
    if not target then
        for _, a in ipairs({ G.shop_jokers, G.shop_vouchers, G.shop_booster }) do
            if a ~= area and type(a) == "table" and a.cards then
                for _, c in ipairs(a.cards) do
                    if c ~= card then
                        target = Id.for_object(c)
                        break
                    end
                end
            end
            if target then break end
        end
    end
    target = target or Id.structural("btn:next_round")
    if G and G.E_MANAGER and Event then
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            func = function()
                ctrl:suggest_move(target)
                return true
            end,
        }))
    else
        ctrl:suggest_move(target)
    end
end

local function buy_click(card)
    return function(ctx)
        if not can_afford(card) then
            say(ctx, "SHOP.CANT_AFFORD")
            return
        end
        local ok, space = pcall(G.FUNCS.check_for_buy_space, card)
        if ok and space == false then
            say(ctx, "SHOP.NO_ROOM")
            return
        end
        G.FUNCS.buy_from_shop({ config = { ref_table = card } })
        say(ctx, "SHOP.BOUGHT")
        suggest_next(ctx, card)
    end
end

local function buy_and_use(card)
    return function(ctx)
        if not can_afford(card) then
            say(ctx, "SHOP.CANT_AFFORD")
            return
        end
        if not (card.can_use_consumeable and card:can_use_consumeable()) then
            say(ctx, "PLAY.CANT_USE")
            return
        end
        G.FUNCS.buy_from_shop({ config = { ref_table = card, id = "buy_and_use" } })
        say(ctx, "SHOP.BOUGHT_USED")
        suggest_next(ctx, card)
    end
end

-- Vouchers and boosters: the game's own activation is use_card (can_redeem /
-- can_open rewrite the button); redeem announces, opening a pack announces
-- itself via the screen change. Only the redeem suggests a next focus —
-- opening a booster leaves the shop, and a stale suggestion would yank the
-- cursor when we return.
local function use_card_click(card, spoken_key, suggest)
    return function(ctx)
        if not can_afford(card) then
            say(ctx, "SHOP.CANT_AFFORD")
            return
        end
        G.FUNCS.use_card({ config = { ref_table = card } })
        if spoken_key then say(ctx, spoken_key) end
        if suggest then suggest_next(ctx, card) end
    end
end

local function add_ware(b, card, pos_index, pos_total)
    local vtable = {
        label = function(ctx)
            local proxy = Factory.create(card)
            local m = proxy and proxy:get_focus_message()
            if m then ctx.message:fragment(m) end
        end,
        -- Position counted over the ROW (voucher + packs share one), not the
        -- backing CardArea.
        deferred = function()
            return Proxies.card_deferred(card, pos_index, pos_total)
        end,
    }
    if card.area == G.shop_vouchers then
        vtable.on_click = use_card_click(card, "SHOP.REDEEMED", true)
    elseif card.area == G.shop_booster then
        vtable.on_click = use_card_click(card, nil, false)
    else
        vtable.on_click = buy_click(card)
        if card.ability and card.ability.consumeable then
            vtable.on_use = buy_and_use(card)
        end
    end
    b:add_item(Id.for_object(card), vtable)
end

-- A shop row: its wares, or a spoken placeholder when the area exists but is
-- sold out.
local function ware_row(b, areas, row_label_key, empty_key)
    local any_area = false
    local total = 0
    for _, area in ipairs(areas) do
        if type(area) == "table" and area.cards then
            any_area = true
            total = total + #area.cards
        end
    end
    if not any_area then return end
    b:start_row("cards", Play.container_label(row_label_key))
    if total > 0 then
        local i = 0
        for _, area in ipairs(areas) do
            if type(area) == "table" and area.cards then
                for _, card in ipairs(area.cards) do
                    i = i + 1
                    add_ware(b, card, i, total)
                end
            end
        end
    else
        b:add_label(Id.structural("empty:" .. row_label_key),
            function(ctx) say(ctx, empty_key) end)
    end
    b:end_row()
end

-- --- Buttons -------------------------------------------------------------------

local function next_round_node()
    local box = G.shop
    if type(box) ~= "table" or not box.get_UIE_by_ID then return nil end
    return box:get_UIE_by_ID("next_round_button")
end

-- The reroll button has no id; it's the next sibling of the Next Round button.
local function reroll_node()
    local nr = next_round_node()
    local parent = nr and nr.parent
    return parent and parent.children and parent.children[2] or nil
end

-- --- Overlay contract ------------------------------------------------------------

-- Initial-load gate: the Next Round button exists almost immediately, but the
-- game's loader waits for the shop box to finish easing in and THEN populates
-- every ware area synchronously in one event (game.lua:3090-3170, ending in
-- its own snap_to) — so "any ware exists" IS the fully-loaded state, no
-- timing heuristics. Settles once per visit: buying / rerolling changes the
-- counts and must not re-gate (it would fight the buy flow's focus
-- suggestions). The wait cap covers the pathological case of a loaded save
-- whose shop was already completely sold out.
local MAX_WAIT = 300       -- ~5s
local settled = false
local waited = 0

local function ware_total()
    local t = 0
    for _, a in ipairs({ G.shop_jokers, G.shop_vouchers, G.shop_booster }) do
        if type(a) == "table" and a.cards then t = t + #a.cards end
    end
    return t
end

function M:handler()
    if not (G and G.STAGE == G.STAGES.RUN and G.STATES) then
        settled, waited = false, 0
        return "inactive"
    end
    local st = G.STATE
    if st == G.STATES.SHOP then
        if G.OVERLAY_MENU then return "sleeping" end
        -- The shop UI eases in after the state flips.
        if not next_round_node() then return "pending" end
        if not settled then
            waited = waited + 1
            if ware_total() == 0 and waited < MAX_WAIT then return "pending" end
            settled = true
        end
        return "active"
    end
    -- Opening a pack leaves the shop state and comes back: keep the position
    -- (and the settled flag — the shop content didn't reload).
    if st == G.STATES.TAROT_PACK or st == G.STATES.SPECTRAL_PACK or st == G.STATES.STANDARD_PACK
        or st == G.STATES.BUFFOON_PACK or st == G.STATES.PLANET_PACK then
        return "sleeping"
    end
    -- Using a consumable FROM the shop flips the state to PLAY_TAROT and back
    -- (use_card records the origin in G.TAROT_INTERRUPT). Reporting inactive
    -- here cleared the cursor cache mid-animation — the "focus jumps around
    -- when using something" bug. Engaged-but-quiet keeps the position AND any
    -- pending focus suggestion (buy-and-use) through the animation.
    if st == G.STATES.PLAY_TAROT and G.TAROT_INTERRUPT == G.STATES.SHOP then
        return "pending"
    end
    settled, waited = false, 0
    return "inactive"
end

function M:build(b)
    b:capture_input()

    -- Your property, one row (as on blind select).
    Play.property_row(b)

    -- The shelf, then voucher + packs together.
    ware_row(b, { G.shop_jokers }, "CONTAINER.SHOP", "SHOP.EMPTY")
    ware_row(b, { G.shop_vouchers, G.shop_booster }, "CONTAINER.SHOP_GOODS", "SHOP.EMPTY")

    -- Buttons.
    local nr, rr = next_round_node(), reroll_node()
    b:start_row("buttons", nil, { wrap = true })
    if nr then
        b:add_clickable(Id.referenced(nr, "btn:next_round"),
            proxy_label(nr),
            function(ctx) nr:click() end)
    end
    if rr then
        b:add_clickable(Id.referenced(rr, "btn:reroll"),
            function(ctx)
                local cost = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost
                ctx.message:fragment(Message.localized("SHOP.REROLL", { cost = tostring(cost or "?") }))
            end,
            function(ctx)
                -- can_reroll strips the button config when unaffordable.
                if rr.config and rr.config.button then
                    rr:click()
                else
                    say(ctx, "SHOP.CANT_AFFORD")
                end
            end)
    end
    b:end_row()

    -- Land on the shelf (or the first thing after it).
    local shelf = G.shop_jokers and G.shop_jokers.cards and G.shop_jokers.cards[1]
    if shelf then
        b:set_start(Id.for_object(shelf))
    elseif nr then
        b:set_start(Id.structural("btn:next_round"))
    end
end

return M
