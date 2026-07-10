-- overlays/challenges.lua — the challenge list + description screen, in
-- Brad's order (the game renders these as two side-by-side columns, which
-- read bottom-heavy in flat tree order):
--   1. the completed tally ("You've completed X of 20...")
--   2. the description AREA: "Select a Challenge..." until one is chosen;
--      then the challenge's starting cards, its Rules/Restrictions/Deck tab
--      strip, and the Play button. Card runs group into left/right ROWS by
--      their CardArea — the Deck tab is four per-suit strips, so it reads
--      one row per suit instead of a 52-item vertical crawl.
--   3. the page cycle
--   4. the numbered challenge list ("3, The Omelette, button, completed" —
--      the number and the green check live in sibling columns the plain
--      button label misses; locked rows read "Locked" and refuse activation:
--      the game gives them config.button = the STRING 'nil', which would
--      error if clicked)
--   5. Back.
-- Selecting a challenge changes sub_identity (the swapped-in description
-- box), so the cursor lands on the description immediately.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "challenges" }

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

-- The swapped-in UIBox behind a Moveable slot ('challenge_list' /
-- 'challenge_area'), or nil while it's still the bare placeholder Moveable.
local function part_box(id)
    local n = part(id)
    local o = n and n.config and n.config.object
    return (type(o) == "table" and o.UIRoot) and o or nil
end

local function game_loc(key)
    local ok, s = pcall(localize, key)
    return (ok and type(s) == "string") and s or ""
end

-- "X of 20 completed", computed with the game's own tally rules.
local function completed_tally()
    local comp, tot = 0, #(G.CHALLENGES or {})
    local prof = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    local done = prof and prof.challenge_progress and prof.challenge_progress.completed or {}
    for _, v in ipairs(G.CHALLENGES or {}) do
        if v.id and done[v.id] then comp = comp + 1 end
    end
    local ok, s = pcall(localize, { type = "variable", key = "challenges_completed", vars = { comp, tot } })
    if ok and type(s) == "string" and s ~= "" then return s end
    return comp .. "/" .. tot
end

-- The green completion check sits in a sibling column of the button's row.
local function is_completed(btn)
    local row, up = btn, 0
    while row and up < 5 and not (G.UIT and row.UIT == G.UIT.R) do
        row, up = row.parent, up + 1
    end
    if not row then return false end
    local found = false
    local function scan(n, depth)
        if found or type(n) ~= "table" or (depth or 0) > 6 then return end
        if n.config and n.config.colour == G.C.GREEN then found = true; return end
        for _, ch in pairs(n.children or {}) do scan(ch, (depth or 0) + 1) end
    end
    scan(row, 0)
    return found
end

-- A list row's button: number (sibling column, via label_above), the game's
-- own label ("The Omelette, button" / "Locked, button"), completion state.
local function list_button_vtable(btn)
    return {
        label = function(ctx)
            local num = Proxy.label_above(btn)
            if num and num ~= "" then ctx.message:fragment(Message.raw(num)) end
            local proxy = Factory.create(btn)
            local m = proxy and proxy:get_focus_message()
            if m then ctx.message:fragment(m) end
            if is_completed(btn) then
                ctx.message:fragment(Message.localized("MENU.COMPLETED"))
            end
        end,
        on_click = function(ctx)
            local b = btn.config and btn.config.button
            if b and b ~= "nil" then
                btn:click()
            else
                ctx.message:fragment(Message.raw(game_loc("k_locked")))
            end
        end,
    }
end

function M:handler()
    if not (overlay() and part("challenge_list")) then return "inactive" end
    -- The list page swaps in via a queued event on open.
    if not part_box("challenge_list") then return "pending" end
    return "active"
end

-- A different description box (a challenge picked / cleared) = fresh open:
-- the cursor lands on the description.
function M:sub_identity()
    return tostring(overlay()) .. "|" .. tostring(part_box("challenge_area"))
end

-- A text panel pushed by the mirror's collect (a controls-free nested box:
-- the rules/restrictions tab content).
local function is_text_root(node)
    local c = node.config
    return node.UIT and G.UIT and node.UIT == G.UIT.ROOT
        and not (c and (c.button or c.focus_args))
        and not (node.is and Card and node:is(Card))
end

-- Flatten a text panel into its rendered rows: EVERY visually distinct line
-- is its own item — the "Custom Rules" / "Game Modifiers" headers, then each
-- rule, each modifier (Brad). A node is one LINE when no deeper row beneath
-- it carries text; colored fragments within a row stay joined.
local function kids_of(n)
    local kids, maxn = {}, 0
    for k in pairs(n.children or {}) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for k = 1, maxn do
        if n.children[k] ~= nil then kids[#kids + 1] = n.children[k] end
    end
    for k, v in pairs(n.children or {}) do
        if type(k) ~= "number" then kids[#kids + 1] = v end
    end
    return kids
end

local function has_text(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 then return false end
    local c = n.config
    if c and n.UIT == G.UIT.T
        and (type(c.text) == "string" or type(c.text) == "number") then
        return true
    end
    if c and type(c.object) == "table" and type(c.object.string) == "string" then
        return true
    end
    for _, ch in ipairs(kids_of(n)) do
        if has_text(ch, (depth or 0) + 1) then return true end
    end
    return false
end

local function has_deeper_text_row(n, depth)
    if type(n) ~= "table" or (depth or 0) > 8 then return false end
    for _, ch in ipairs(kids_of(n)) do
        if type(ch) == "table" then
            if ch.UIT == G.UIT.R and has_text(ch) then return true end
            if has_deeper_text_row(ch, (depth or 0) + 1) then return true end
        end
    end
    return false
end

local function collect_lines(node, out, depth)
    if type(node) ~= "table" or (depth or 0) > 8 then return end
    if not has_deeper_text_row(node) then
        if has_text(node) then
            local ok, t = pcall(Proxy.all_text, node)
            if ok and type(t) == "string" and t ~= "" then out[#out + 1] = t end
        end
        return
    end
    for _, ch in ipairs(kids_of(node)) do
        collect_lines(ch, out, (depth or 0) + 1)
    end
end

local function text_lines(root)
    local lines = {}
    collect_lines(root, lines, 0)
    if lines[1] then return lines end
    local ok, t = pcall(Proxy.all_text, root)
    if ok and type(t) == "string" and t ~= "" then return { t } end
    return {}
end

-- Emit gathered items: consecutive Cards from the SAME CardArea become one
-- left/right row when it's a view_deck strip (the Deck tab's four suits);
-- text panels expand to one label per rendered line. Returns the first
-- emitted id (the fresh-open landing after picking a challenge).
local function emit_items(b, items, prefix)
    local first = nil
    local function mark(id)
        if not first then first = id end
        return id
    end
    local i, n = 1, #items
    while i <= n do
        local node = items[i]
        if node.is and Card and node:is(Card) and node.area then
            local area = node.area
            b:start_row(prefix .. "area" .. tostring(area), nil, { wrap = true })
            while i <= n do
                local m = items[i]
                if not (m.is and Card and m:is(Card) and m.area == area) then break end
                b:add_item(mark(Id.referenced(m, prefix .. i)), Mirror.vtable_for(m))
                i = i + 1
            end
            b:end_row()
        elseif is_text_root(node) then
            for j, line in ipairs(text_lines(node)) do
                b:add_label(mark(Id.structural(prefix .. i .. ":" .. j)), function(ctx)
                    ctx.message:fragment(Message.raw(line))
                end)
            end
            i = i + 1
        else
            b:add_item(mark(Id.referenced(node, prefix .. i)), Mirror.vtable_for(node))
            i = i + 1
        end
    end
    return first
end

function M:build(b)
    b:capture_input()

    -- 1. Completed tally.
    b:add_label(Id.structural("tally"), function(ctx)
        ctx.message:fragment(Message.raw(completed_tally()))
    end)

    -- 2. Description area (or the select-a-challenge instruction). Reorder
    -- the game's tree: tabs + tab content first, then the challenge's
    -- starting jokers/consumables/vouchers as a VERTICAL list (they render
    -- above the tabs but read better below them — Brad), Play last.
    local area = part_box("challenge_area")
    local area_items = area and Mirror.gather({ area }) or {}
    if area_items[1] then
        local start_cards, play_btn, rest = {}, nil, {}
        for _, node in ipairs(area_items) do
            if node.is and Card and node:is(Card)
                and not (node.area and node.area.config and node.area.config.view_deck) then
                start_cards[#start_cards + 1] = node
            elseif node.config and node.config.button == "start_challenge_run" then
                play_btn = node
            else
                rest[#rest + 1] = node
            end
        end
        -- Land on the description (its tab strip) when a challenge is
        -- picked, not back up at the tally.
        local first = emit_items(b, rest, "d:")
        if first then b:set_start(first) end
        for i, c in ipairs(start_cards) do
            b:add_item(Id.referenced(c, "s:" .. i), Mirror.vtable_for(c))
        end
        if play_btn then
            b:add_item(Id.referenced(play_btn, "play"), Mirror.vtable_for(play_btn))
        end
    else
        b:add_label(Id.structural("placeholder"), function(ctx)
            local text
            if area then
                local ok, t = pcall(Proxy.all_text, area.UIRoot)
                text = ok and t or nil
            end
            if not text or text == "" then text = game_loc("ph_select_challenge") end
            if text ~= "" then ctx.message:fragment(Message.raw(text)) end
        end)
    end

    -- 3. Page cycle. Its generic label climbs to the neighboring completed
    -- tally (already its own item at the top); read just the page value.
    local pager = part("challenge_page")
    if pager then
        local vt = Mirror.vtable_for(pager)
        vt.label = function(ctx)
            local v = Proxy.cycle_value(pager)
            if v then ctx.message:fragment(Message.raw(v)) end
            ctx.message:fragment(Message.localized("TYPES.CYCLE"))
        end
        b:add_item(Id.referenced(pager, "pager"), vt)
    end

    -- 4. The challenge list.
    local list = part_box("challenge_list")
    if list then
        for i, btn in ipairs(Mirror.gather({ list })) do
            b:add_item(Id.referenced(btn, "c:" .. i), list_button_vtable(btn))
        end
    end

    -- 5. Back.
    local back = part("overlay_menu_back_button")
    if back then
        b:add_item(Id.referenced(back, "btn:back"), Mirror.vtable_for(back))
    end
end

return M
