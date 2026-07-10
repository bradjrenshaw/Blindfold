-- overlays/collection.lua — the collection card screens (Jokers, Tarots,
-- Planets, Spectrals, Vouchers, Editions, Boosters, Decks). The game lays
-- each out as a grid of CardArea rows (jokers: 3 rows of 5) with a page
-- cycle beneath — every such screen fills G.your_collection, which is the
-- detection AND the row source. One overlay row per grid row (left/right
-- with wrap, positions per row), then the rest of the screen's controls
-- (page cycle, Back) in tree order. Undiscovered/locked cards read their
-- hidden state via Proxy.center_hidden — the render is a "?" silhouette.
local require = ...
local Id = require("overlay.id")
local Mirror = require("overlays.menu_mirror")

local M = { id = "collection" }

local function areas()
    local list = {}
    if not (G and type(G.your_collection) == "table") then return list end
    for _, a in ipairs(G.your_collection) do
        if type(a) == "table" and not a.REMOVED and type(a.cards) == "table" then
            list[#list + 1] = a
        end
    end
    return list
end

function M:handler()
    -- G.your_collection LINGERS after the menu closes; the areas' REMOVED
    -- flags (their UIBox teardown) are what say the screen is really up.
    if not (G and type(G.OVERLAY_MENU) == "table") then return "inactive" end
    local rows = areas()
    if #rows == 0 then return "inactive" end
    local total = 0
    for _, a in ipairs(rows) do total = total + #a.cards end
    -- Cards fill via queued events on open / page flip.
    if total == 0 then return "pending" end
    return "active"
end

function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

function M:build(b)
    b:capture_input()

    local shown = {}
    for _, a in ipairs(areas()) do shown[a] = true end

    -- The grid: one row per CardArea row.
    for j, area in ipairs(areas()) do
        if area.cards[1] then
            b:start_row("row" .. j, nil, { wrap = true })
            for _, card in ipairs(area.cards) do
                b:add_item(Id.for_object(card), Mirror.vtable_for(card))
            end
            b:end_row()
        end
    end

    -- Everything else on the screen (page cycle, Back) in tree order, minus
    -- the cards already placed in the grid.
    local i = 0
    for _, n in ipairs(Mirror.gather({ G.OVERLAY_MENU })) do
        if not (n.is and Card and n:is(Card) and n.area and shown[n.area]) then
            i = i + 1
            b:add_item(Id.referenced(n, "r:" .. i), Mirror.vtable_for(n))
        end
    end
end

return M
