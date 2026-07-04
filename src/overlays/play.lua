-- overlays/play.lua — the owned in-run play screen: jokers / consumables /
-- played / hand as predictable horizontal rows (up/down switches rows, left/
-- right moves within one), plus a button row (Play hand, sort, Discard).
-- Replaces the game's geometric focus navigation, whose cross-row moves only
-- worked when cards happened to align pixel-wise.
--
-- Immediate mode: build() re-declares everything from live state each tick.
-- Card nodes reuse the proxy layer for their spoken labels (so enhancement /
-- edition / rarity / price and all announce toggles keep working); the deferred
-- description + position follow-up is spoken by core's overlay-result handler,
-- exactly like the legacy focus path.
--
-- Sell (S) / Use (U) are node actions on the joker/consumable nodes. They call
-- the game's FUNCS directly because the native path needs the game's own
-- focused-card button UI, which the owned model doesn't drive. Gated at
-- activation (can_use / can_sell) with spoken feedback; on nodes without the
-- action the key just re-reads the label. Space grabs (pick up / place) on
-- jokers and hand cards; Enter selects hand cards / activates buttons.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Settings = require("settings.registry")

local M = { id = "play" }

-- Row (container) announcement, spoken when vertical navigation enters the
-- row; respects the existing container toggle.
local function container_label(loc_key)
    return function(ctx)
        if Settings.value("announce.container.enabled") == false then return end
        ctx.message:fragment(Message.localized(loc_key))
    end
end

local function loc_label(loc_key)
    return function(ctx) ctx.message:fragment(Message.localized(loc_key)) end
end

local function say(ctx, loc_key)
    ctx.message:fragment(Message.localized(loc_key))
end

-- --- Card reordering (grab: pick up / place) ----------------------------------
--
-- Space on a card picks it up; Space on another card in the same row places it
-- before that one (Brad's model — less confusing than the game's hold-to-drag,
-- and distinct from Enter/select). Space on the carried card again cancels.
-- Works on jokers (scoring order) and the hand (played cards score left-to-
-- right by hand position; the arrangement resets on the next draw). Module
-- state, not graph state: the carry survives rebuilds and row navigation, and
-- is dropped if the carried card leaves its area (sold, played, round over).

local carry = nil   -- { card = Card, area = CardArea }, or nil

local function carry_valid()
    if not carry then return false end
    local card, area = carry.card, carry.area
    if card.REMOVED or card.area ~= area or not area.cards then return false end
    for _, c in ipairs(area.cards) do
        if c == card then return true end
    end
    return false
end

local function card_name(card)
    local ok, name = pcall(function()
        local proxy = Factory.create(card)
        local m = proxy and proxy.get_label and proxy:get_label()
        return m and m:resolve() or nil
    end)
    return (ok and name) or ""
end

local function grab_handler(card, area)
    return function(ctx)
        if not carry_valid() then carry = nil end
        if not carry then
            carry = { card = card, area = area }
            ctx.message:fragment(Message.localized("PLAY.PICKED_UP", { name = card_name(card) }))
            return
        end
        if carry.card == card then
            carry = nil
            say(ctx, "PLAY.PICKUP_CANCELLED")
            return
        end
        if carry.area ~= area then
            say(ctx, "PLAY.CANT_MOVE_HERE")   -- carry kept; navigate back to its row
            return
        end
        -- Move the carried card to sit before this one. Mirrors the engine's
        -- drag-reorder invariant: cards array in order, rank = index, realign
        -- (align_cards sets T.x synchronously, so a play right after scores in
        -- the new order).
        local cards = area.cards
        local from
        for i, c in ipairs(cards) do
            if c == carry.card then from = i; break end
        end
        local moved = table.remove(cards, from)
        local to = #cards + 1
        for i, c in ipairs(cards) do
            if c == card then to = i; break end
        end
        table.insert(cards, to, moved)
        for i, c in ipairs(cards) do c.rank = i end
        area:align_cards()
        carry = nil
        say(ctx, "PLAY.MOVED")
        -- Land the cursor on the card in its new slot; the next tick's focus
        -- announce reads it (name, then position via the deferred follow-up).
        if ctx.controller then
            ctx.controller:suggest_move(Id.for_object(moved))
        end
    end
end

-- --- Cards -------------------------------------------------------------------

-- selectable: hand cards toggle highlight through the game's own click
-- semantics (Enter). Jokers / consumables are NOT selectable in controller HID
-- mode (CardArea:can_highlight only allows the hand); their Enter re-reads the
-- label. grab (Space) reorders within the row; sell/use are S / U node actions.
-- pos_index/pos_total: the card's position within its ROW (which may span
-- several CardAreas on some screens) — spoken in the deferred follow-up
-- instead of the CardArea-relative position, so "2 of 3" always matches what
-- left/right actually walks.
local function add_card(b, card, area, opts, pos_index, pos_total)
    local vtable = {
        label = function(ctx)
            local proxy = Factory.create(card)
            local m = proxy and proxy:get_focus_message()
            if m then ctx.message:fragment(m) end
        end,
    }
    if pos_index and pos_total then
        vtable.deferred = function()
            return Proxy.card_deferred(card, pos_index, pos_total)
        end
    end
    if opts and opts.selectable then
        vtable.on_click = function(ctx)
            local before = not not card.highlighted
            card:click()
            if (not not card.highlighted) ~= before then
                say(ctx, card.highlighted and "CARD.SELECTED" or "CARD.DESELECTED")
            else
                say(ctx, "PLAY.CANT_SELECT")
            end
        end
    end
    if opts and opts.grab then
        vtable.on_grab = grab_handler(card, area)
    end
    if opts and opts.actions then
        vtable.on_sell = function(ctx)
            if card.can_sell_card and card:can_sell_card() then
                G.FUNCS.sell_card({ config = { ref_table = card } })
                say(ctx, "PLAY.SOLD")
            else
                say(ctx, "PLAY.CANT_SELL")
            end
        end
        if card.ability and card.ability.consumeable then
            vtable.on_use = function(ctx)
                if card.can_use_consumeable and card:can_use_consumeable() then
                    G.FUNCS.use_card({ config = { ref_table = card } })
                    say(ctx, "PLAY.USED")
                elseif type(card.ability.consumeable) == "table"
                    and card.ability.consumeable.max_highlighted then
                    -- Targeting tarots are only usable while selecting a hand
                    -- with the right number of cards highlighted (the game's
                    -- rule) — say WHY instead of a bare "cannot use".
                    say(ctx, "PLAY.NEEDS_TARGETS")
                else
                    say(ctx, "PLAY.CANT_USE")
                end
            end
        end
    end
    b:add_item(Id.for_object(card), vtable)
end

-- All card rows share the row key so up/down preserves the position in the row.
local function card_row(b, area, loc_key, opts)
    if not area or not area.cards or #area.cards == 0 then return end
    b:start_row("cards", container_label(loc_key), { wrap = opts and opts.wrap })
    local total = #area.cards
    for i, card in ipairs(area.cards) do
        add_card(b, card, area, opts, i, total)
    end
    b:end_row()
end

-- Shared with other in-run overlays (blind select / shop / packs): the card
-- node builder (labels via proxies, select/grab/sell/use behaviors — including
-- the shared grab carry, so a pickup works identically across screens) and the
-- gated container row label.
M.add_card = add_card
M.container_label = container_label

-- The player's jokers + consumables as ONE row (consumables to the right) —
-- shared by the blind select, shop, and pack overlays. Positions here are
-- deliberately per AREA (the proxy default), not per row: jokers and
-- consumables have separate slot capacities, so "joker 5 of 5" telling you
-- you're at the rightmost joker is the information that matters (Brad).
function M.property_row(b)
    local jokers = (G.jokers and G.jokers.cards) or {}
    local cons = (G.consumeables and G.consumeables.cards) or {}
    if #jokers + #cons == 0 then return end
    b:start_row("cards",
        container_label(#jokers > 0 and "CONTAINER.JOKERS" or "CONTAINER.CONSUMABLES"))
    for _, card in ipairs(jokers) do
        add_card(b, card, G.jokers, { actions = true, grab = true })
    end
    for _, card in ipairs(cons) do
        add_card(b, card, G.consumeables, { actions = true })
    end
    b:end_row()
end

-- --- Play / discard ------------------------------------------------------------
--
-- Shared by the button-row nodes AND the direct X / C key handlers (wired in
-- core via Input.handlers). Returns a loc key to announce, or nil (fired — the
-- round/scoring hooks speak the feedback — or not applicable in this state,
-- which stays silent like the native buttons).

function M.do_play()
    if not (G and G.STATES and G.STATE == G.STATES.SELECTING_HAND) then return nil end
    if not (G.hand and G.hand.highlighted and #G.hand.highlighted > 0) then
        return "PLAY.NO_CARDS"
    end
    if G.play and G.play.cards[1] then return nil end   -- mid-play; the FUNCS would no-op
    G.FUNCS.play_cards_from_highlighted()
    return nil
end

function M.do_discard()
    if not (G and G.STATES and G.STATE == G.STATES.SELECTING_HAND) then return nil end
    if not (G.hand and G.hand.highlighted and #G.hand.highlighted > 0) then
        return "PLAY.NO_CARDS"
    end
    -- The game FUNCS itself does NOT check discards_left; guard here.
    local cr = G.GAME and G.GAME.current_round
    if not cr or (cr.discards_left or 0) <= 0 then
        return "PLAY.NO_DISCARDS"
    end
    G.FUNCS.discard_cards_from_highlighted()
    return nil
end

local function on_play(ctx)
    local err = M.do_play()
    if err then say(ctx, err) end
end

local function on_discard(ctx)
    local err = M.do_discard()
    if err then say(ctx, err) end
end

local function sort_click(func_key, spoken_key)
    return function(ctx)
        if G.FUNCS and G.FUNCS[func_key] then G.FUNCS[func_key]() end
        say(ctx, spoken_key)
    end
end

-- --- Overlay contract --------------------------------------------------------

function M:handler()
    if not (G and G.STAGE and G.STAGES and G.STAGE == G.STAGES.RUN) then return "inactive" end
    -- A game menu on top (options, run info, ...): keep the cache, yield input.
    if G.OVERLAY_MENU then return "sleeping" end
    local S, st = G.STATES, G.STATE
    if not S then return "inactive" end
    -- Active ONLY while the hand is stable and selectable. Every other in-round
    -- state is a card-churning animation: the scoring cascade (HAND_PLAYED),
    -- the redraw (DRAW_TO_HAND — SELECTING_HAND is entered by an event queued
    -- BEHIND the draws, so waking there means the hand is full and positions
    -- read right), consumable use (PLAY_TAROT), and the round outro
    -- (NEW_ROUND). Announcing survivors mid-churn read wrong positions and
    -- random landings; pending keeps us engaged but silent, and the single
    -- wake announce lands on settled state.
    if st == S.SELECTING_HAND then
        -- Waking from an animation: the card set changed underneath us, so a
        -- reconciled landing would depend on what happened to the old cursor —
        -- inconsistent. Bump the generation instead: the dispatcher treats it
        -- as a fresh open and focus always lands on the start node (the first
        -- hand card). A menu round-trip (sleeping) still preserves position.
        if self._churning then
            self._churning = false
            self._generation = (self._generation or 0) + 1
        end
        return "active"
    end
    if st == S.HAND_PLAYED or st == S.DRAW_TO_HAND or st == S.PLAY_TAROT
        or st == S.NEW_ROUND then
        self._churning = true
        return "pending"
    end
    -- Opening a pack mid-round: the pack UI is game-driven (legacy layer);
    -- sleep so the hand position survives until the pack closes.
    if st == S.TAROT_PACK or st == S.SPECTRAL_PACK or st == S.STANDARD_PACK
        or st == S.BUFFOON_PACK or st == S.PLANET_PACK then
        return "sleeping"
    end
    return "inactive"
end

-- A new generation per animation wake = a fresh open (cursor to start node).
function M:sub_identity()
    return tostring(self._generation or 0)
end

function M:build(b)
    b:capture_input()
    card_row(b, G.jokers, "CONTAINER.JOKERS", { actions = true, grab = true })
    card_row(b, G.consumeables, "CONTAINER.CONSUMABLES", { actions = true })
    card_row(b, G.play, "CONTAINER.PLAYED", nil)
    card_row(b, G.hand, "CONTAINER.HAND", { selectable = true, wrap = true, grab = true })

    b:start_row("buttons", nil, { wrap = true })
    b:add_clickable(Id.structural("btn:play"), loc_label("PLAY.PLAY_HAND"), on_play)
    b:add_clickable(Id.structural("btn:sort_rank"), loc_label("PLAY.SORT_RANK"),
        sort_click("sort_hand_value", "PLAY.SORTED_RANK"))
    b:add_clickable(Id.structural("btn:sort_suit"), loc_label("PLAY.SORT_SUIT"),
        sort_click("sort_hand_suit", "PLAY.SORTED_SUIT"))
    b:add_clickable(Id.structural("btn:discard"), loc_label("PLAY.DISCARD"), on_discard)
    b:end_row()

    -- Land on the hand, not the top-left joker.
    if G.hand and G.hand.cards and G.hand.cards[1] then
        b:set_start(Id.for_object(G.hand.cards[1]))
    end
end

return M
