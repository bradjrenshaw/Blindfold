-- overlays/blinds.lua — the owned blind selection screen, laid out per Brad:
--   row 1: jokers + consumables as ONE row (consumables to the right); the
--          same sell/use/grab behaviors as the play screen (selling jokers and
--          using consumables is legal in this state, and a real tactic)
--   row 2: Reroll Boss (only with the Director's Cut / Retcon voucher)
--   row 3: the blind panels — one column per blind (Small / Big / Boss),
--          left/right swaps panels, and arriving from above lands on the
--          CURRENT blind. All blind details (state, name, score requirement,
--          reward, boss effect) are spoken on the Select button via the
--          existing ProxyBlind; the skip reward (tag) is spoken on Skip.
--   row 4: the Skip buttons, sharing the column key with row 3 — down from a
--          Select lands on its own column's Skip (Boss has none).
--
-- The buttons are the game's own (found in the G.blind_select_opts panel
-- UIBoxes / G.blind_prompt_box); activation clicks them, guarded so only the
-- current blind can be selected or skipped.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxies = require("ui.proxies")
local Play = require("overlays.play")

local M = { id = "blinds" }

local TYPES = { "Small", "Big", "Boss" }
local BOX_KEYS = { Small = "small", Big = "big", Boss = "boss" }

local function find_button(node, button, depth)
    if type(node) ~= "table" or (depth or 0) > 16 then return nil end
    if node.config and node.config.button == button then return node end
    if node.children then
        for _, ch in ipairs(node.children) do
            local hit = find_button(ch, button, (depth or 0) + 1)
            if hit then return hit end
        end
    end
    return nil
end

-- The Select / Skip nodes of one panel, found by STABLE identity (ids), not by
-- config.button: the game's blind_choice_handler strips the button config off
-- non-current panels every frame — they're display-only — but the blinds are
-- fully shown from the start and reviewing them is the point of this row.
local function panel_nodes(type_name)
    local box = G.blind_select_opts and G.blind_select_opts[BOX_KEYS[type_name]]
    if type(box) ~= "table" or not box.get_UIE_by_ID then return nil, nil end
    local sel = box:get_UIE_by_ID("select_blind_button")
    local tag = box:get_UIE_by_ID("tag_" .. type_name)
    local skip = tag and tag.children and tag.children[2] or nil
    return sel, skip
end

local function proxy_label(node)
    return function(ctx)
        local proxy = Factory.create(node)
        local m = proxy and proxy:get_focus_message()
        if m then ctx.message:fragment(m) end
    end
end

-- Select / Skip: the game's own button click, but only for the current blind
-- (the others are display-only, matching native).
local function blind_vtable(node, type_name, is_skip)
    return {
        label = function(ctx)
            local proxy = Proxies.Blind.new(node)
            proxy.force_skip = is_skip or nil
            local m = proxy:get_focus_message()
            if m then ctx.message:fragment(m) end
        end,
        on_click = function(ctx)
            if not (G.GAME and G.GAME.blind_on_deck == type_name) then
                ctx.message:fragment(Message.localized("BLIND.NOT_CURRENT"))
                return
            end
            node:click()
        end,
    }
end

function M:handler()
    if not (G and G.STAGE == G.STAGES.RUN and G.STATES and G.STATE == G.STATES.BLIND_SELECT) then
        return "inactive"
    end
    if G.OVERLAY_MENU then return "sleeping" end
    -- The panels ease in after the state flips; stay engaged-but-quiet until
    -- the current blind's Select button exists.
    local current = G.GAME and G.GAME.blind_on_deck
    if not (current and (panel_nodes(current))) then return "pending" end
    return "active"
end

function M:build(b)
    b:capture_input()

    -- Jokers + consumables, one row.
    local has_jokers = G.jokers and G.jokers.cards and #G.jokers.cards > 0
    local has_cons = G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0
    if has_jokers or has_cons then
        b:start_row("cards",
            Play.container_label(has_jokers and "CONTAINER.JOKERS" or "CONTAINER.CONSUMABLES"))
        if has_jokers then
            for _, card in ipairs(G.jokers.cards) do
                Play.add_card(b, card, G.jokers, { actions = true, grab = true })
            end
        end
        if has_cons then
            for _, card in ipairs(G.consumeables.cards) do
                Play.add_card(b, card, G.consumeables, { actions = true })
            end
        end
        b:end_row()
    end

    -- Reroll Boss, when the voucher grants it (the game's func disables the
    -- button by clearing config.button when it can't fire, which also drops it
    -- from this graph — same as native).
    local reroll = G.blind_prompt_box and G.blind_prompt_box.UIRoot
        and find_button(G.blind_prompt_box.UIRoot, "reroll_boss")
    if reroll then
        b:add_clickable(Id.referenced(reroll, "reroll"),
            proxy_label(reroll),
            function(ctx) reroll:click() end)
    end

    -- The blind columns: every visible panel, current or not (the others read
    -- their state / details but refuse activation). Skips only for blinds not
    -- yet resolved — a Defeated / Skipped panel's skip is meaningless.
    local selects, skips = {}, {}
    local current_idx = 1
    for _, t in ipairs(TYPES) do
        local sel, skip = panel_nodes(t)
        if sel then
            selects[#selects + 1] = { node = sel, type = t }
            if G.GAME and G.GAME.blind_on_deck == t then current_idx = #selects end
            local state = G.GAME and G.GAME.round_resets
                and G.GAME.round_resets.blind_states and G.GAME.round_resets.blind_states[t]
            if skip and state ~= "Defeated" and state ~= "Skipped" then
                skips[#skips + 1] = { node = skip, type = t }
            end
        end
    end
    -- No row label here: the Select buttons name their blind themselves, and a
    -- label would re-announce every time vertical nav re-enters this row
    -- (e.g. up from a Skip).
    if selects[1] then
        b:start_row("blinds", nil, { enter = current_idx })
        for _, e in ipairs(selects) do
            b:add_item(Id.referenced(e.node, "select:" .. e.type), blind_vtable(e.node, e.type))
        end
        b:end_row()
    end
    if skips[1] then
        b:start_row("blinds")
        for _, e in ipairs(skips) do
            b:add_item(Id.referenced(e.node, "skip:" .. e.type), blind_vtable(e.node, e.type, true))
        end
        b:end_row()
    end

    -- Column-accurate wiring on top of the row sugar: vertical movement stays
    -- in its own column (a column with no skip — the Boss — stops instead of
    -- falling to another column's skip), and horizontal movement from a skip
    -- whose neighbor column has no skip climbs to that column's Select (right
    -- from Big's skip reaches the Boss).
    local has_skip = {}
    for _, e in ipairs(skips) do has_skip[e.type] = true end
    local col_of = {}
    for i, s in ipairs(selects) do col_of[s.type] = i end
    for _, s in ipairs(selects) do
        local sel_id = Id.structural("select:" .. s.type)
        if has_skip[s.type] then
            local skip_id = Id.structural("skip:" .. s.type)
            b:connect(sel_id, "down", skip_id)
            b:connect(skip_id, "up", sel_id)
        else
            b:connect(sel_id, "down", nil)
        end
    end
    for _, e in ipairs(skips) do
        local from = Id.structural("skip:" .. e.type)
        local col = col_of[e.type]
        local prev_s, next_s = selects[col - 1], selects[col + 1]
        if prev_s then
            b:connect(from, "left", has_skip[prev_s.type]
                and Id.structural("skip:" .. prev_s.type)
                or Id.structural("select:" .. prev_s.type))
        end
        if next_s then
            b:connect(from, "right", has_skip[next_s.type]
                and Id.structural("skip:" .. next_s.type)
                or Id.structural("select:" .. next_s.type))
        end
    end

    if selects[current_idx] then
        b:set_start(Id.structural("select:" .. selects[current_idx].type))
    end
end

return M
