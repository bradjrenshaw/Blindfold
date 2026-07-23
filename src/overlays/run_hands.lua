-- overlays/run_hands.lua — the poker-hands listing (the run info tab and the
-- standalone "current hands" popup) as a real 2D TABLE, after the
-- wotr-access GraphSheet: user feedback found the flattened list confusing.
--
-- Columns mirror the game's row layout (UI_definitions.lua:3042): the hand
-- NAME is the primary cell, then level, chips, mult, played. Navigation
-- semantics ported from the wotr tables:
--   * left/right crossings speak the DESTINATION COLUMN's header, then the
--     cell ("level, lvl.3" — none onto the primary, whose text identifies);
--   * up/down stays in the same column and speaks the DESTINATION ROW's name
--     when off-primary ("Flush, 35") so a column can be walked and compared
--     without full-row readouts;
--   * the name cell's deferred follow-up is the hand's own description (the
--     row's on-demand tooltip, spoken from the game's localization).
-- The tab strip / Back button around the table still come from the mirror's
-- discovery, so tab switching works unchanged.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Mirror = require("overlays.menu_mirror")

local M = { id = "run_hands" }

-- The game's own render order (create_UIBox_current_hands) — visible only.
local HAND_ORDER = {
    "Flush Five", "Flush House", "Five of a Kind", "Straight Flush",
    "Four of a Kind", "Full House", "Flush", "Straight", "Three of a Kind",
    "Two Pair", "Pair", "High Card",
}

local function each_child(children, visit)
    local maxn = 0
    for k in pairs(children) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for i = 1, maxn do
        if children[i] ~= nil then visit(children[i]) end
    end
    for k, v in pairs(children) do
        if type(k) ~= "number" then visit(v) end
    end
end

-- A FULL hands row: carries the hand-tip tooltip AND the played-count '#'
-- column. The simple (name-only) variant used elsewhere stays untouched.
local function has_played_column(node, depth)
    if type(node) ~= "table" or depth > 8 then return false end
    if node.config and node.config.text == "  #" then return true end
    local hit = false
    if node.children then
        each_child(node.children, function(ch)
            hit = hit or has_played_column(ch, depth + 1)
        end)
    end
    return hit
end

local function is_hands_row(node)
    local c = node and node.config
    local tip = c and c.on_demand_tooltip
    if not (tip and tip.filler and tip.filler.func == create_UIBox_hand_tip) then
        return false
    end
    return has_played_column(node, 0)
end

local function tree_has_hands_row(node, depth)
    if type(node) ~= "table" or depth > 30 then return false end
    if is_hands_row(node) then return true end
    -- Tab contents are EMBEDDED UIBoxes behind UIT.O (the deck-view lesson):
    -- descend through their UIRoot or the rows are invisible to this walk.
    local obj = node.config and node.config.object
    if obj and obj.is and UIBox and obj:is(UIBox) and obj.UIRoot then
        if tree_has_hands_row(obj.UIRoot, depth + 1) then return true end
    end
    local hit = false
    if node.children then
        each_child(node.children, function(ch)
            hit = hit or tree_has_hands_row(ch, depth + 1)
        end)
    end
    return hit
end

local function inside_hands_row(node)
    local n, up = node, 0
    while type(n) == "table" and up < 12 do
        if is_hands_row(n) then return true end
        n = n.parent
        up = up + 1
    end
    return false
end

function M:handler()
    local ov = G and G.OVERLAY_MENU
    if type(ov) ~= "table" or not ov.UIRoot then return "inactive" end
    local ok, hit = pcall(tree_has_hands_row, ov.UIRoot, 0)
    return (ok and hit) and "active" or "inactive"
end

-- The OVERLAY_MENU instance: tab round-trips within the same overlay keep the
-- cursor; a fresh open resets it.
function M:sub_identity()
    return tostring(G and G.OVERLAY_MENU)
end

local function game_loc(key, cat)
    local ok, s = pcall(localize, key, cat)
    return (ok and type(s) == "string" and s ~= "" and s ~= "ERROR") and s or nil
end

-- Hand descriptions localize to a table of lines.
local function hand_description(name)
    local ok, d = pcall(localize, name, "poker_hand_descriptions")
    if not ok then return nil end
    if type(d) == "string" then return d end
    if type(d) == "table" then
        local parts = {}
        for _, line in ipairs(d) do
            if type(line) == "string" then parts[#parts + 1] = line end
        end
        return #parts > 0 and table.concat(parts, " ") or nil
    end
    return nil
end

local HEADERS = { "RUNINFO.COL_LEVEL", "RUNINFO.COL_CHIPS", "RUNINFO.COL_MULT", "RUNINFO.COL_PLAYED" }
local function header(col)   -- crossing label for columns 1..4; none for 0
    if col < 1 then return nil end
    return function(ctx) ctx.message:fragment(Message.localized(HEADERS[col])) end
end

local function text_label(s)
    return function(ctx) ctx.message:fragment(Message.raw(s)) end
end

function M:build(b)
    b:capture_input()
    local ov = G and G.OVERLAY_MENU
    if not ov then return end

    -- Everything else on the screen (tab strip, Back), via the mirror's
    -- discovery — minus the hand rows the table replaces.
    local others = {}
    local ok, gathered = pcall(Mirror.gather, { ov })
    if ok then
        for _, n in ipairs(gathered) do
            if not (type(n) == "table" and n.UIT and inside_hands_row(n)) then
                others[#others + 1] = n
            end
        end
    end
    local other_ids = {}
    for i, n in ipairs(others) do
        other_ids[i] = Id.referenced(n, "o:" .. i)
        b:add_node(other_ids[i], Mirror.vtable_for(n))
    end

    -- The table: one row per visible hand, in the game's render order.
    local rows = {}
    for _, name in ipairs(HAND_ORDER) do
        local h = G.GAME and G.GAME.hands and G.GAME.hands[name]
        if h and h.visible then
            local disp = game_loc(name, "poker_hands") or name
            local cells = {}
            cells[0] = Id.structural("h:" .. name)
            b:add_node(cells[0], {
                label = text_label(disp),
                deferred = function()
                    local d = hand_description(name)
                    return d and Message.raw(d) or nil
                end,
            })
            local values = {
                (game_loc("k_level_prefix") or "lvl.") .. tostring(h.level),
                tostring(h.chips),
                tostring(h.mult),
                tostring(h.played),
            }
            for col = 1, 4 do
                cells[col] = Id.structural("h:" .. name .. ":c" .. col)
                b:add_node(cells[col], { label = text_label(values[col]) })
            end
            -- Horizontal: crossings speak the destination column's header.
            for col = 0, 3 do
                b:connect(cells[col], "right", cells[col + 1], header(col + 1))
                b:connect(cells[col + 1], "left", cells[col], header(col))
            end
            rows[#rows + 1] = { cells = cells, name = disp }
        end
    end

    -- Vertical: same column, destination row named when off-primary.
    for i = 1, #rows - 1 do
        local a, z = rows[i], rows[i + 1]
        for col = 0, 4 do
            b:connect(a.cells[col], "down", z.cells[col], col > 0 and text_label(z.name) or nil)
            b:connect(z.cells[col], "up", a.cells[col], col > 0 and text_label(a.name) or nil)
        end
    end

    -- Stitch: first other (the tab strip) sits above the table, the rest
    -- (Back) below; every table column exits vertically at the table's ends.
    local top, below = other_ids[1], other_ids[2]
    if #rows > 0 then
        local first, last = rows[1], rows[#rows]
        if top then
            b:connect(top, "down", first.cells[0])
            for col = 0, 4 do b:connect(first.cells[col], "up", top) end
        end
        if below then
            b:connect(below, "up", last.cells[0])
            for col = 0, 4 do b:connect(last.cells[col], "down", below) end
        end
        b:set_start(first.cells[0])
    end
    for i = 2, #other_ids - 1 do
        b:connect(other_ids[i], "down", other_ids[i + 1])
        b:connect(other_ids[i + 1], "up", other_ids[i])
    end
    if not rows[1] and other_ids[1] then b:set_start(other_ids[1]) end
end

return M
