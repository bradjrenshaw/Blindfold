-- overlays/run_select.lua — Steamodded's New Run screen (its "Galdur" run
-- select, src/utils/run_select.lua), which replaces the vanilla deck/stake
-- cycles unless the player turns on smods' vanilla run select. A paged
-- wizard: each page (Select Deck, Select Stake, plus any a mod adds) shows a
-- grid of choices as face-down cards in CardAreas — invisible to the mirror,
-- which only collects face-up cards — beside a preview of what's selected.
--
-- Layout, top to bottom:
--   1. the New Run / Continue / Challenges tab strip
--   2. the choice grid, one row per rendered row, columns preserved on
--      up/down. Each choice reads its name (or "Locked"), selected state and
--      win sticker / completion; its description (deck effect or unlock
--      requirement, stake effect or what unlocks it) and grid position follow
--      as the deferred readout. Enter selects; Enter on the selected choice
--      advances, as the game's double-click does (on the last page: Play)
--   3. the grid's page cycle (left/right), when the pool spans pages
--   4. the selection summary (the preview pane / stake tower)
--   5. Random, then Previous / Next-or-Play / Last Run and the seed controls
--   6. any other controls (pages mods add with their own settings), Back.
-- Opening the screen starts on the tabs like any menu. A page change swaps
-- the 'run_select' UIBox, which is the sub_identity: the cursor lands on the
-- new page's current selection.
--
-- Vanilla (no Steamodded) never reaches this: the handler needs SMODS and the
-- 'run_select' slot, which only Steamodded's screen builds.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "run_select" }

local function RS()
    return type(SMODS) == "table" and type(SMODS.RunSelect) == "table" and SMODS.RunSelect or nil
end

local function overlay()
    local ov = G and G.OVERLAY_MENU
    return type(ov) == "table" and ov or nil
end

local function part(id)
    local ov = overlay()
    local ok, node = pcall(function()
        return ov and ov.get_UIE_by_ID and ov:get_UIE_by_ID(id) or nil
    end)
    return ok and node or nil
end

-- The current page's UIBox in the 'run_select' slot.
local function page_box()
    local n = part("run_select")
    local o = n and n.config and n.config.object
    return (type(o) == "table" and o.UIRoot) and o or nil
end

local function page_key()
    local R = RS()
    local I = R and R.Internals
    return I and I.pages and I.pages[I.current_page] or nil
end

local function page_def(key)
    local R = RS()
    key = key or page_key()
    return key and R and R.Pages and R.Pages[key] or nil
end

local function choice(key)
    local R = RS()
    local c = R and R.Setup and R.Setup.choices
    return c and c[key]
end

-- Whether `ckey` is chosen on page `pkey` (single choice: the key; a
-- multi-select page: a set of keys).
local function is_chosen(pkey, ckey)
    local c = choice(pkey)
    if type(c) == "table" then return c[ckey] and true or false end
    return c ~= nil and c == ckey
end

local function game_loc(args, misc)
    local ok, s = pcall(localize, args, misc)
    if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" then return s end
    return nil
end

local function name_text(set, key)
    if not (set and key) then return nil end
    return game_loc({ type = "name_text", set = set, key = key })
end

local function strip_arrows(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s*<%s*", ""):gsub("%s*>%s*$", "")
    return s ~= "" and s or nil
end

-- --- Choices -------------------------------------------------------------------

-- The card a selection area shows on top (decks stack ten deep; the top one
-- carries the win sticker).
local function top_card(area)
    local cards = area and area.cards
    return type(cards) == "table" and cards[#cards] or nil
end

local function area_sticker(area)
    for _, c in ipairs(area and area.cards or {}) do
        if type(c.sticker) == "string" then return c.sticker end
    end
    return nil
end

-- (unlocked, won) for a stake chip, by the stake page's own rule (wins and
-- unlocks are per selected deck).
local function stake_state(key)
    local pd = page_def("stake_choice")
    local stake = G.P_STAKES and G.P_STAKES[key]
    if not (pd and pd.is_stake_unlocked and stake) then return true, false end
    local ok, unlocked, won = pcall(pd.is_stake_unlocked, stake)
    if not ok then return true, false end
    return unlocked and true or false, won and true or false
end

-- What a locked stake chip's hover says: "Win with this deck on Red Stake".
local function locked_stake_text(key)
    local stake = G.P_STAKES and G.P_STAKES[key]
    local applied = stake and stake.applied_stakes or {}
    local s = game_loc("run_select_locked_stake_message") or ""
    for i, v in ipairs(applied) do
        s = s .. (name_text("Stake", v) or v)
            .. (i < #applied and (game_loc("run_select_locked_stake_and") or " ") or "")
    end
    return s ~= "" and s or nil
end

local function is_locked(card)
    if card.params and card.params.stake then return card.params.stake_chip_locked and true or false end
    local center = card.config and card.config.center
    return center ~= nil and center.unlocked == false
end

local function choice_key(card)
    if card.params and card.params.stake then return card.params.stake end
    local center = card.config and card.config.center
    return center and center.key
end

local function card_name(card, pkey)
    if card.params and card.params.stake then
        if card.params.stake_chip_locked then
            return game_loc("run_select_locked_stake") or Message.localized("LABELS.LOCKED"):resolve()
        end
        return name_text("Stake", card.params.stake)
    end
    local center = card.config and card.config.center
    if center and center.set == "Back" then
        if center.unlocked == false then return game_loc("k_locked") end
        return name_text("Back", center.key)
    end
    -- A mod's page: face-up cards read like any card; otherwise by name.
    if card.facing ~= "back" then
        local proxy = Factory.create(card)
        local m = proxy and proxy.get_label and proxy:get_label()
        local s = m and m:resolve()
        if s and s ~= "" then return s end
    end
    local pd = page_def(pkey)
    return name_text(pd and pd.type or (center and center.set), center and center.key)
end

local function card_description(card)
    if card.params and card.params.stake then
        if card.params.stake_chip_locked then return locked_stake_text(card.params.stake) end
        return Proxy.stake_text(card.params.stake)
    end
    local center = card.config and card.config.center
    if center and center.set == "Back" then return Proxy.back_text(center) end
    if card.facing ~= "back" then return Proxy.card_description(card) end
    return nil
end

-- --- Page cycle ----------------------------------------------------------------

-- The grid's page cycler: two arrow buttons sharing one pass_through table.
local function cycler_parts(items)
    local prev, nxt
    for _, n in ipairs(items) do
        local c = n.config
        if c and c.button == "cycler_default" and type(c.pass_through) == "table" then
            if (c.direction or 0) < 0 then prev = prev or n else nxt = nxt or n end
        end
    end
    return prev, nxt
end

local function cycler_page(arrow)
    local pl = arrow and arrow.config.pass_through.page_label
    return (pl and tonumber(pl.page)) or 1, pl and pl.text
end

-- --- Selection summary -----------------------------------------------------------

local function selected_text(pkey)
    local pd = page_def(pkey)
    if not pd then return nil end
    local c = choice(pkey)
    if pd.selected_text then
        local ok, s = pcall(pd.selected_text, pd, c)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    if type(c) == "string" then return name_text(pd.type, c) end
    return nil
end

-- What the preview pane / stake tower shows for the current page.
local function summary()
    local pd, pkey = page_def(), page_key()
    if not pd then return nil end
    local parts = {}
    if pd.automatic_preview then
        parts[#parts + 1] = selected_text(pkey) or game_loc("run_select_nothing")
    end
    if pd.include_deck_preview then parts[#parts + 1] = selected_text("deck_choice") end
    if pd.include_stake_tower then parts[#parts + 1] = name_text("Stake", choice("stake_choice")) end
    if not parts[1] then return nil end
    parts[#parts + 1] = Message.localized("CARD.SELECTED"):resolve()
    return table.concat(parts, ", ")
end

-- --- Overlay -------------------------------------------------------------------

local entry_box = nil    -- the page showing when the screen opened

function M:handler()
    if not RS() or not overlay() or not page_box() then
        entry_box = nil
        return "inactive"
    end
    entry_box = entry_box or page_box()
    return "active"
end

function M:sub_identity()
    return tostring(overlay()) .. "|" .. tostring(page_box())
end

-- The page title ("Select Deck"): spoken entering the grid from the tabs,
-- and as the result of any press that changes the page (the cursor then
-- lands on the new page's selection, which doesn't say which page it is).
local function page_title(ctx)
    local t = page_key() and game_loc("run_select_" .. page_key())
    if t then ctx.message:fragment(Message.raw(t)) end
end

-- Run a press; if it changed the page, say the new page's title.
local function pressing(ctx, fn)
    local before = page_box()
    pcall(fn)
    local after = page_box()
    if after and after ~= before then page_title(ctx) end
end

local function choice_vtable(area, pkey, index, total)
    return {
        label = function(ctx)
            local card = top_card(area)
            if not card then return end
            local name = card_name(card, pkey)
            if name then ctx.message:fragment(Message.raw(name)) end
            local key = choice_key(card)
            if key and is_chosen(pkey, key) then
                ctx.message:fragment(Message.localized("CARD.SELECTED"))
            end
            if card.params and card.params.stake and not card.params.stake_chip_locked then
                local _, won = stake_state(card.params.stake)
                if won then ctx.message:fragment(Message.localized("MENU.COMPLETED")) end
            end
            local sticker = area_sticker(area)
            if sticker then
                ctx.message:fragment(Message.localized("CARD.WIN_STICKER",
                    { stake = Proxy.sticker_stake_name(sticker) }))
            end
        end,
        deferred = function()
            local card = top_card(area)
            if not card then return nil end
            local parts = {}
            if Proxy.announce_enabled("description") then
                local d = card_description(card)
                if d then parts[#parts + 1] = d end
            end
            if Proxy.announce_enabled("position") then
                parts[#parts + 1] = Message.localized("POSITION.OF",
                    { index = index, total = total }):resolve()
            end
            return #parts > 0 and table.concat(parts, ", ") or nil
        end,
        on_click = function(ctx)
            local card = top_card(area)
            if not card then return end
            if is_locked(card) then
                ctx.message:fragment(Message.localized("LABELS.LOCKED"))
                return
            end
            local key = choice_key(card)
            local was = key and is_chosen(pkey, key)
            pressing(ctx, function() card:click() end)
            -- Clicking the chosen card advances (the page swap is titled
            -- above; a run start announces itself); a new choice confirms.
            if not was and key and is_chosen(pkey, key) then
                ctx.message:fragment(Message.localized("CARD.SELECTED"))
            end
        end,
    }
end

-- The choice grid in its rendered rows; returns the selected choice's id
-- (the landing spot on a fresh page) or the first one.
local function build_grid(b, pd, pkey, page_no)
    local R = RS()
    local areas = R.Internals.select_areas or {}
    local cols = (pd.grid_size and pd.grid_size[2]) or #areas
    local amount = pd.amount or #areas
    local total = type(pd.pool) == "table" and #pd.pool or #areas
    local rows, start, first = {}, nil, nil
    for i = 1, #areas do
        local card = top_card(areas[i])
        if card then
            local r = math.floor((i - 1) / cols) + 1
            rows[r] = rows[r] or {}
            local id = Id.referenced(card, "grid:" .. i)
            local index = (page_no - 1) * amount + i
            rows[r][#rows[r] + 1] = { id = id, vt = choice_vtable(areas[i], pkey, index, total) }
            first = first or id
            local key = choice_key(card)
            if not start and key and is_chosen(pkey, key) then start = id end
        end
    end
    local ordered = {}
    for r = 1, #areas do if rows[r] then ordered[#ordered + 1] = rows[r] end end
    for r, row in ipairs(ordered) do
        b:start_row("grid_row:" .. r, r == 1 and page_title or nil)
        for _, item in ipairs(row) do b:add_item(item.id, item.vt) end
        b:end_row()
    end
    -- True columns: up/down keeps the column (clamped to a shorter row).
    for r = 1, #ordered - 1 do
        local a, z = ordered[r], ordered[r + 1]
        for c, item in ipairs(a) do
            b:connect(item.id, "down", z[math.min(c, #z)].id)
        end
        for c, item in ipairs(z) do
            b:connect(item.id, "up", a[math.min(c, #a)].id)
        end
    end
    return start or first
end

local function nav_vtable(node, text_field)
    local vt = Mirror.vtable_for(node)
    local click = vt.on_click
    if click then
        vt.on_click = function(ctx) pressing(ctx, function() click(ctx) end) end
    end
    vt.label = function(ctx)
        local R = RS()
        local s = strip_arrows(R and R.Internals[text_field])
        if s then ctx.message:fragment(Message.raw(s)) end
        ctx.message:fragment(Message.localized("TYPES.BUTTON"))
    end
    return vt
end

function M:build(b)
    b:capture_input()
    local pd, pkey = page_def(), page_key()
    if not pd then return end
    local items = Mirror.gather({ overlay() })

    local tabs, rest = {}, {}
    local random, prev, nxt, back
    for _, n in ipairs(items) do
        local c = n.config or {}
        local fa = c.focus_args
        local obj = c.object
        if fa and fa.set_button_pip then
            -- a gamepad button-hint icon, not a control
        elseif n.is and Card and n:is(Card) then
            -- grid / preview / tower cards: the grid is built separately
        elseif obj and obj.is and CardArea and obj:is(CardArea) then
            -- a selection area's snap wrapper
        elseif c.button == "cycler_default" then
            -- the page cycle, built as one control
        elseif fa and fa.type == "tab" then
            tabs[#tabs + 1] = n
        elseif c.button == "random_type" then
            random = n
        elseif c.id == "previous_selection" then
            prev = n
        elseif c.id == "next_selection" then
            nxt = n
        elseif c.id == "overlay_menu_back_button" then
            back = n
        else
            rest[#rest + 1] = n
        end
    end

    -- 1. Tabs.
    for i, n in ipairs(tabs) do
        b:add_item(Id.referenced(n, "tab:" .. i), Mirror.vtable_for(n))
    end

    -- 2. The grid. Opening the screen (switching to the New Run tab) starts
    -- on the tabs like any menu; a page change (Next / Previous) lands on
    -- the new page's current selection.
    local cyc_prev, cyc_next = cycler_parts(items)
    local page_no = cycler_page(cyc_prev or cyc_next)
    if type(pd.pool) == "table" then
        local start = build_grid(b, pd, pkey, page_no)
        if start and (page_box() ~= entry_box or not tabs[1]) then b:set_start(start) end
    end

    -- 3. Page cycle.
    if cyc_prev or cyc_next then
        local any = cyc_prev or cyc_next
        b:add_item(Id.referenced(any, "pager"), {
            label = function(ctx)
                local _, text = cycler_page(any)
                if text then ctx.message:fragment(Message.raw(text)) end
                ctx.message:fragment(Message.localized("TYPES.CYCLE"))
            end,
            on_horizontal_adjust = function(ctx, sign)
                local arrow = sign > 0 and cyc_next or cyc_prev
                if arrow then pcall(function() arrow:click() end) end
                local _, text = cycler_page(any)
                if text then ctx.message:fragment(Message.raw(text)) end
            end,
        })
    end

    -- 4. Selection summary.
    if summary() then
        b:add_label(Id.structural("summary"), function(ctx)
            local s = summary()
            if s then ctx.message:fragment(Message.raw(s)) end
        end)
    end

    -- 5. Random, then the navigation bar.
    if random then
        local vt = Mirror.vtable_for(random)
        local click = vt.on_click
        vt.on_click = function(ctx)
            if click then click(ctx) end
            local s = summary()
            if s then ctx.message:fragment(Message.raw(s)) end
        end
        b:add_item(Id.referenced(random, "random"), vt)
    end
    if prev and prev.config.button then
        b:add_item(Id.referenced(prev, "nav:prev"), nav_vtable(prev, "previous_button_text"))
    end
    if nxt then
        b:add_item(Id.referenced(nxt, "nav:next"), nav_vtable(nxt, "next_button_text"))
    end

    -- 6. Everything else in reading order (Last Run, seed toggle / field /
    -- paste, a mod page's own settings), then Back.
    for i, n in ipairs(rest) do
        b:add_item(Id.referenced(n, "m:" .. i), Mirror.vtable_for(n))
    end
    if back then
        b:add_item(Id.referenced(back, "btn:back"), Mirror.vtable_for(back))
    end
end

return M
