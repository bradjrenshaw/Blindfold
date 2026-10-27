-- buffers/screen.lua — the "screen" buffer: everything the game is drawing,
-- as text, top to bottom. Every visible UIBox is read in reading order (text
-- lines and controls, the menu mirror's panel walk, controls named by their
-- labels), boxes ordered by where they sit on screen. A review aid for
-- screens Blindfold doesn't know — a mod's panel, an unfamiliar menu — so
-- nothing on screen is out of reach even when it isn't navigable.
--
-- Left out: card areas (the cards themselves; their focus buffers cover
-- them) and boxes attached to a card (its hover popup, use / sell buttons).
-- While an overlay menu is up, only the menu and what it embeds are read:
-- it covers the screen.
local require = ...
local Buffer = require("buffers.buffer")
local MB = require("overlay.message_builder")

local function on_card(box)
    local major = box.role and box.role.major
    return major ~= nil and major.is ~= nil and Card ~= nil and major:is(Card)
end

-- The box this one is drawn inside (nested boxes — tab contents, panels —
-- hang off a node of their host), or nil for a top-level box.
local function host_box(box)
    local major = box.role and box.role.major
    local seen = 0
    while type(major) == "table" and seen < 32 do
        if UIBox and major.is and major:is(UIBox) then return major end
        major = major.UIBox or (major.role and major.role.major)
        seen = seen + 1
    end
    return nil
end

local function top_box(box)
    local b, seen = box, 0
    while seen < 32 do
        local h = host_box(b)
        if not h or h == b then return b end
        b, seen = h, seen + 1
    end
    return b
end

local function shown(box)
    if type(box) ~= "table" or box.REMOVED or not box.UIRoot then return false end
    if box.states and box.states.visible == false then return false end
    if on_card(box) then return false end
    -- Off screen: parked boxes (the shop slid away, the blind select below).
    local t, room = box.VT or box.T, G.ROOM and G.ROOM.T
    if t and room and t.y and t.h then
        if t.y >= room.h or t.y + t.h <= 0 then return false end
    end
    return true
end

local ROW_SLACK = 1

local function visible_boxes()
    local out = {}
    local menu = G.OVERLAY_MENU
    for _, box in ipairs((G.I and G.I.UIBOX) or {}) do
        if shown(box) and (not menu or top_box(box) == menu) then
            out[#out + 1] = box
        end
    end
    -- Reading order: rows top to bottom, each left to right. A row is the
    -- boxes whose tops sit within ROW_SLACK of its first (the blind select's
    -- current blind is raised above its neighbours).
    local function pos(b) local t = b.VT or b.T or {}; return t.y or 0, t.x or 0 end
    table.sort(out, function(a, b) return (pos(a)) < (pos(b)) end)
    local rows, row = {}, nil
    for _, box in ipairs(out) do
        local y = pos(box)
        if not row or y - row.y > ROW_SLACK then
            row = { y = y }
            rows[#rows + 1] = row
        end
        row[#row + 1] = box
    end
    local ordered = {}
    for _, r in ipairs(rows) do
        table.sort(r, function(a, b) return select(2, pos(a)) < select(2, pos(b)) end)
        for _, box in ipairs(r) do ordered[#ordered + 1] = box end
    end
    return ordered
end

local function control_label(Mirror, node)
    local ok, text = pcall(function()
        local m = MB.new()
        Mirror.vtable_for(node).label({ message = m, mods = {} })
        return m:build()
    end)
    return ok and text or nil
end

-- The screen's lines, in order (exposed for the dev server / tests).
local function lines()
    local Mirror = require("overlays.menu_mirror")
    local out = {}
    local function add(s)
        if type(s) ~= "string" then return end
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        -- Rewards drawn as a run of dollar signs ("$$$$+"): say the count.
        s = s:gsub("%$%$+", function(run) return "$" .. #run end)
        if s ~= "" and out[#out] ~= s then out[#out + 1] = s end
    end
    local cache = {}
    local function items_of(box)
        if not cache[box] then
            local ok, items = pcall(Mirror.panel_items, box.UIRoot, { boxes = true })
            cache[box] = ok and items or {}
        end
        return cache[box]
    end
    -- A box another box embeds (tab contents, a panel) reads where its host
    -- embeds it, not in position order.
    local boxes, embedded = visible_boxes(), {}
    for _, box in ipairs(boxes) do
        for _, it in ipairs(items_of(box)) do
            if it.box then embedded[it.box] = true end
        end
    end
    local done = {}
    local function read(box, depth)
        if done[box] or depth > 8 then return end
        done[box] = true
        for _, it in ipairs(items_of(box)) do
            if it.text then add(it.text)
            elseif it.node then add(control_label(Mirror, it.node))
            elseif it.box and shown(it.box) then read(it.box, depth + 1) end
        end
    end
    for _, box in ipairs(boxes) do
        if not embedded[box] then read(box, 0) end
    end
    return out
end

local M = Buffer.new("screen", {
    update = function(self)
        self:repopulate(function()
            if not (G and G.I) then return end
            local ok, list = pcall(lines)
            for _, l in ipairs(ok and list or {}) do self:add(l) end
        end)
    end,
})
M.lines = lines

return M
