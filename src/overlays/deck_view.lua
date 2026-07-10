-- overlays/deck_view.lua — the owned deck view (View Deck / deck info), per
-- Brad's layout:
--   row 1: the tab strip (Remaining / Full Deck) as ONE control — left/right
--          switches tabs in place, matching every other game tab
--   row 2: deck name + description ("Red Deck: <effect text>")
--   row 3: totals — Aces / Face cards / Numbered cards, spoken as
--          "Aces, base 4, effective 6" (plain count when unmodified, matching
--          the game's render-effective-only-when-modded), plus the
--          "N drawn face down" note when a flip boss has hidden hand cards
--   row 4: rank tallies, Ace down to 2, same base/effective form
--   rows 5+: one row per suit — the game's own rendered card copies in its
--          order (rank descending; stone cards appear in their dead suit's
--          row, exactly as rendered). Greyed copies (Remaining tab: already
--          drawn from the pile) append "drawn".
--   last: the Back button.
--
-- Tallies are computed with the game's exact rules (view_deck in
-- UI_definitions: stone cards excluded; "effective" counts via is_suit /
-- is_face and non-debuffed ranks). The card rows reuse the copies the game
-- emplaces into its display strips, so what is spoken is what is rendered —
-- including face-up copies of wheel-flipped cards (the view aggregates them;
-- sighted players see the same).
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "deck_view" }

local function overlay_root()
    local ov = G and G.OVERLAY_MENU
    return type(ov) == "table" and ov.UIRoot or nil
end

-- Hardened walk (menu_mirror's rules): the game NILS array entries in
-- children tables (holes stop ipairs dead) and attaches string-keyed extras,
-- and the tab CONTENT lives in a UIBox embedded behind a UIT.O object node —
-- a plain child walk never reaches the suit strips at all. Numeric children
-- in order first, then keyed extras; invisible subtrees skipped (a swapped-
-- out tab's stale content must not contribute areas).
local function collect(node, pred, out, depth, seen)
    if type(node) ~= "table" or (depth or 0) > 30 then return out end
    seen = seen or {}
    if seen[node] then return out end
    seen[node] = true
    if node.states and node.states.visible == false then return out end
    if pred(node) then out[#out + 1] = node end
    local obj = node.config and node.config.object
    if type(obj) == "table" and obj.is and UIBox and obj:is(UIBox) then
        collect(obj.UIRoot, pred, out, (depth or 0) + 1, seen)
    end
    local kids = node.children
    if type(kids) == "table" then
        local maxn = 0
        for k in pairs(kids) do
            if type(k) == "number" and k > maxn then maxn = k end
        end
        for i = 1, maxn do
            if kids[i] ~= nil then
                collect(kids[i], pred, out, (depth or 0) + 1, seen)
            end
        end
        for k, v in pairs(kids) do
            if type(k) ~= "number" then
                collect(v, pred, out, (depth or 0) + 1, seen)
            end
        end
    end
    return out
end

local function tab_nodes()
    local root = overlay_root()
    if not root then return {} end
    return collect(root, function(n)
        return n.config and n.config.button == "change_tab"
    end, {})
end

-- The tab STRIP container (focus_args.type 'tab'): exposed as ONE control
-- whose left/right switches tabs in place — the engine's dpad semantics,
-- shared with every other game tab via the menu mirror's vtable.
local function tab_strip()
    local root = overlay_root()
    if not root then return nil end
    return collect(root, function(n)
        local fa = n.config and n.config.focus_args
        return fa and fa.type == "tab"
    end, {})[1]
end

-- The chosen tab's def rides its ref_table; the Remaining tab is the one
-- created with tab_definition_function_args (deck_info in UI_definitions).
local function remaining_tab_chosen()
    for _, t in ipairs(tab_nodes()) do
        if t.config.chosen then
            local def = t.config.ref_table
            return (def and def.tab_definition_function_args) and true or false
        end
    end
    return false
end

-- The rendered suit strips: CardAreas flagged view_deck, in layout order
-- (Spades, Hearts, Clubs, Diamonds; suits with no cards are absent).
local function suit_areas()
    local root = overlay_root()
    if not root then return {} end
    local hits = collect(root, function(n)
        local o = n.config and n.config.object
        return type(o) == "table" and o.config and o.config.view_deck
            and type(o.cards) == "table"
    end, {})
    local areas = {}
    for _, n in ipairs(hits) do areas[#areas + 1] = n.config.object end
    return areas
end

local function game_loc(key, set)
    local ok, s = pcall(localize, key, set)
    return (ok and type(s) == "string" and s ~= "") and s or tostring(key)
end

-- The game's tally rules, verbatim (view_deck): stone cards never count;
-- Remaining counts cards still in the draw pile plus flip-hidden hand cards.
local function tallies(unplayed_only)
    local t = {
        suits = { Spades = { 0, 0 }, Hearts = { 0, 0 }, Clubs = { 0, 0 }, Diamonds = { 0, 0 } },
        ranks = {}, aces = { 0, 0 }, faces = { 0, 0 }, nums = { 0, 0 }, flipped = 0,
    }
    for i = 2, 14 do t.ranks[i] = { 0, 0 } end
    for _, v in ipairs((G and G.playing_cards) or {}) do
        local counted = v and v.ability and v.ability.name ~= "Stone Card"
            and (not unplayed_only or ((v.area and v.area == G.deck) or v.ability.wheel_flipped))
        if counted then
            if unplayed_only and v.ability.wheel_flipped then t.flipped = t.flipped + 1 end
            local s = v.base and v.base.suit
            if t.suits[s] then t.suits[s][1] = t.suits[s][1] + 1 end
            for suit, tally in pairs(t.suits) do
                local ok, is = pcall(v.is_suit, v, suit)
                if ok and is then tally[2] = tally[2] + 1 end
            end
            local ok, id = pcall(v.get_id, v)
            if ok and type(id) == "number" and t.ranks[id] then
                t.ranks[id][1] = t.ranks[id][1] + 1
                if not v.debuff then t.ranks[id][2] = t.ranks[id][2] + 1 end
                if id >= 11 and id <= 13 then t.faces[1] = t.faces[1] + 1 end
                local okf, face = pcall(v.is_face, v)
                if okf and face then t.faces[2] = t.faces[2] + 1 end
                if id > 1 and id < 11 then
                    t.nums[1] = t.nums[1] + 1
                    if not v.debuff then t.nums[2] = t.nums[2] + 1 end
                end
                if id == 14 then
                    t.aces[1] = t.aces[1] + 1
                    if not v.debuff then t.aces[2] = t.aces[2] + 1 end
                end
            end
        end
    end
    return t
end

-- "Aces, 4" when unmodified; "Aces, base 4, effective 6" when the deck's
-- modifiers change the effective count (the game's blue column).
local function pair_text(label, pair)
    if pair[1] == pair[2] then
        return Message.localized("DECK_VIEW.TALLY", { label = label, count = pair[1] })
    end
    return Message.localized("DECK_VIEW.TALLY_MOD",
        { label = label, base = pair[1], effective = pair[2] })
end

local RANKS_DESC = { 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2 }
local RANK_KEYS = { [14] = "Ace", [13] = "King", [12] = "Queen", [11] = "Jack" }
local function rank_label(id)
    if RANK_KEYS[id] then return game_loc(RANK_KEYS[id], "ranks") end
    return tostring(id)
end

local function proxy_label(node)
    return function(ctx)
        local proxy = Factory.create(node)
        local m = proxy and proxy:get_focus_message()
        if m then ctx.message:fragment(m) end
    end
end

function M:handler()
    if not (G and G.OVERLAY_MENU and G.VIEWING_DECK) then return "inactive" end
    -- Menus rebuild their content on tab clicks; stay quiet until anything
    -- recognizable exists.
    if not tab_strip() and #suit_areas() == 0 then return "pending" end
    return "active"
end

-- A new menu box = a fresh open (the flag alone spans distinct opens).
function M:sub_identity()
    return tostring(G and G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()
    local unplayed = remaining_tab_chosen()

    -- The tab strip: one control, left/right switches Remaining / Full Deck.
    local strip = tab_strip()
    if strip then
        b:add_item(Id.referenced(strip, "tabs"), Mirror.vtable_for(strip))
    end

    -- Deck name + description.
    b:add_label(Id.structural("deck"), function(ctx)
        local back = G.GAME and G.GAME.selected_back
        local name = (back and back.loc_name) and tostring(back.loc_name) or ""
        local desc = ""
        pcall(function()
            local def = back:generate_UI(nil, 0.7, 0.5, G.GAME.challenge)
            local parts = {}
            Proxy.collect_def_text(def, parts)
            desc = table.concat(parts, " ")
        end)
        ctx.message:fragment(Message.localized("DECK_VIEW.NAME_DESC", { name = name, desc = desc }))
    end)

    -- Totals: aces / face cards / numbered cards (+ the face-down note).
    b:start_row("totals", nil, { wrap = true })
    b:add_label(Id.structural("t:aces"), function(ctx)
        ctx.message:fragment(pair_text(game_loc("k_aces"), tallies(unplayed).aces))
    end)
    b:add_label(Id.structural("t:faces"), function(ctx)
        ctx.message:fragment(pair_text(game_loc("k_face_cards"), tallies(unplayed).faces))
    end)
    b:add_label(Id.structural("t:nums"), function(ctx)
        ctx.message:fragment(pair_text(game_loc("k_numbered_cards"), tallies(unplayed).nums))
    end)
    if unplayed and tallies(true).flipped > 0 then
        b:add_label(Id.structural("t:flipped"), function(ctx)
            ctx.message:fragment(Message.localized("DECK_VIEW.FLIPPED",
                { count = tallies(true).flipped }))
        end)
    end
    b:end_row()

    -- Rank tallies, ace down to 2.
    b:start_row("ranks", nil, { wrap = true })
    for _, id in ipairs(RANKS_DESC) do
        b:add_label(Id.structural("r:" .. id), function(ctx)
            ctx.message:fragment(pair_text(rank_label(id), tallies(unplayed).ranks[id]))
        end)
    end
    b:end_row()

    -- One row per rendered suit strip; row label = suit name + its tally.
    for idx, area in ipairs(suit_areas()) do
        local cards = area.cards
        local suit = cards[1] and cards[1].base and cards[1].base.suit
        b:start_row("suit:" .. idx, function(ctx)
            if suit then
                local pair = tallies(unplayed).suits[suit]
                ctx.message:fragment(pair_text(game_loc(suit, "suits_plural"),
                    pair or { #cards, #cards }))
            end
        end, { wrap = true })
        local total = #cards
        for i, c in ipairs(cards) do
            b:add_item(Id.for_object(c), {
                label = function(ctx)
                    local proxy = Factory.create(c)
                    local m = proxy and proxy:get_focus_message()
                    if m then ctx.message:fragment(m) end
                    if c.greyed then
                        ctx.message:fragment(Message.localized("DECK_VIEW.DRAWN"))
                    end
                end,
                deferred = function()
                    return Proxy.card_deferred(c, i, total)
                end,
            })
        end
        b:end_row()
    end

    -- Back.
    local root = overlay_root()
    local back_btn = root and collect(root, function(n)
        return n.config and n.config.button == "exit_overlay_menu"
    end, {})[1]
    if back_btn then
        b:add_clickable(Id.referenced(back_btn, "btn:back"),
            proxy_label(back_btn),
            function(ctx) back_btn:click() end)
    end
end

return M
