-- overlays/packs.lua — the owned booster-pack opening screen (all five pack
-- states: arcana / spectral / standard / buffoon / celestial):
--   row 1: your jokers + consumables (context for the pick; sell/use work)
--   row 2: "Choose N of M" header
--   row 3: the pack's choice cards — Enter picks one (the game's use_card)
--   row 4: your hand, when dealt (tarot/spectral packs deal one for targeting;
--          Enter selects cards exactly like the play screen)
--   row 5: Skip
--
-- Guards spoken instead of silent: a pack tarot that needs hand targets says
-- "Cannot use now" until you've selected them; a buffoon-pack joker with no
-- joker room says "No room"; Skip says "Cannot skip" when the game disallows
-- it (can_skip_booster strips the button config).
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxies = require("ui.proxies").Proxy
local Play = require("overlays.play")

local M = { id = "packs" }

local function say(ctx, loc_key)
    ctx.message:fragment(Message.localized(loc_key))
end

local function in_pack_state()
    local S = G.STATES
    return S and (G.STATE == S.TAROT_PACK or G.STATE == S.SPECTRAL_PACK
        or G.STATE == S.STANDARD_PACK or G.STATE == S.BUFFOON_PACK
        or G.STATE == S.PLANET_PACK)
end

local function find_skip(node, depth)
    if type(node) ~= "table" or (depth or 0) > 16 then return nil end
    local c = node.config
    if c and (c.button == "skip_booster" or c.func == "can_skip_booster") then return node end
    if node.children then
        for _, ch in ipairs(node.children) do
            local hit = find_skip(ch, (depth or 0) + 1)
            if hit then return hit end
        end
    end
    return nil
end

local function skip_node()
    local box = G.booster_pack
    if type(box) ~= "table" or not box.UIRoot then return nil end
    return find_skip(box.UIRoot)
end

-- Enter on a pack card: the game's activation (use_card — can_select_card /
-- can_use_consumeable rewrite every pack button to it), with its gates spoken.
local function pick_click(card)
    return function(ctx)
        if card.ability and card.ability.consumeable then
            if not (card.can_use_consumeable and card:can_use_consumeable()) then
                say(ctx, "PLAY.CANT_USE")   -- e.g. needs hand cards selected
                return
            end
        elseif card.ability and card.ability.set == "Joker" then
            -- can_select_card: jokers need room unless negative-edition.
            local negative = card.edition and card.edition.negative
            if not negative and G.jokers and #G.jokers.cards >= (G.jokers.config.card_limit or 5) then
                say(ctx, "SHOP.NO_ROOM")
                return
            end
        end
        G.FUNCS.use_card({ config = { ref_table = card } })
    end
end

-- The cards deal in one at a time; stay quiet until the count stops moving.
local last_count = -1

function M:handler()
    if not (G and G.STAGE == G.STAGES.RUN and in_pack_state()) then
        last_count = -1
        return "inactive"
    end
    if G.OVERLAY_MENU then return "sleeping" end
    local cards = G.pack_cards and G.pack_cards.cards
    local count = cards and #cards or 0
    if count == 0 or count ~= last_count then
        last_count = count
        return "pending"
    end
    return "active"
end

function M:build(b)
    b:capture_input()

    -- Your property, for pick context.
    Play.property_row(b)

    local pack = G.pack_cards and G.pack_cards.cards or {}

    b:add_label(Id.structural("hdr"), function(ctx)
        ctx.message:fragment(Message.localized("PACK.CHOOSE", {
            choices = tostring(G.GAME and G.GAME.pack_choices or 1),
            count = tostring(#pack),
        }))
    end)

    if pack[1] then
        b:start_row("cards", Play.container_label("CONTAINER.PACK"))
        local total = #pack
        for i, card in ipairs(pack) do
            b:add_item(Id.for_object(card), {
                label = function(ctx)
                    local proxy = Factory.create(card)
                    local m = proxy and proxy:get_focus_message()
                    if m then ctx.message:fragment(m) end
                end,
                on_click = pick_click(card),
                deferred = function()
                    return Proxies.card_deferred(card, i, total)
                end,
            })
        end
        b:end_row()
    end

    -- The hand, when the pack dealt one (tarot / spectral targeting).
    if G.hand and G.hand.cards and #G.hand.cards > 0 then
        b:start_row("cards", Play.container_label("CONTAINER.HAND"), { wrap = true })
        local total = #G.hand.cards
        for i, card in ipairs(G.hand.cards) do
            Play.add_card(b, card, G.hand, { selectable = true }, i, total)
        end
        b:end_row()
    end

    local skip = skip_node()
    if skip then
        b:add_clickable(Id.referenced(skip, "btn:skip"),
            function(ctx)
                local proxy = Factory.create(skip)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end,
            function(ctx)
                if skip.config and skip.config.button then
                    skip:click()
                else
                    say(ctx, "PACK.CANT_SKIP")
                end
            end)
    end

    if pack[1] then
        b:set_start(Id.for_object(pack[1]))
    end
end

return M
