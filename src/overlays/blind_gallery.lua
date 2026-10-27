-- overlays/blind_gallery.lua — the Blinds AND Tags collection galleries:
-- sprites embedded behind UIT.O nodes the menu mirror cannot reach (its
-- collector only descends CardArea/UIBox objects) — both screens used to
-- read as just a Back button. Blinds: 30 chips, rows of five; Tags: 24
-- sprites, rows of six — matching each screen's visual matrix. Every item
-- reads its name (or "Not discovered": the render is the "?" sprite) with
-- the effect description as the deferred follow-up.
--
-- Steamodded rebuilds both pages: each blind is a stand-in Card (a blank
-- base card wearing the blind's sprite, with config.blind) inside paged
-- G.your_collection CardAreas, and the tags page sits in a nested UIBox
-- that swaps per page. The walk finds items in all three places.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "blind_gallery" }

-- The gallery sprites (blind chips or tag sprites), in tree order (= the
-- game's sorted order).
local function is_item(o)
    return type(o) == "table" and type(o.config) == "table"
        and (o.config.blind ~= nil or o.config.tag ~= nil)
end

local function sprites()
    local out = {}
    local ov = G and G.OVERLAY_MENU
    if type(ov) ~= "table" or not ov.UIRoot then return out end
    local walk
    walk = function(n, depth)
        if type(n) ~= "table" or depth > 24 then return end
        local o = n.config and n.config.object
        if is_item(o) then
            out[#out + 1] = o
        elseif type(o) == "table" and o.is and CardArea and o:is(CardArea) then
            for _, c in ipairs(o.cards or {}) do
                if is_item(c) then out[#out + 1] = c end
            end
        elseif type(o) == "table" and o.UIRoot then
            walk(o.UIRoot, depth + 1)
        end
        local kids, maxn = n.children, 0
        if type(kids) ~= "table" then return end
        for k in pairs(kids) do
            if type(k) == "number" and k > maxn then maxn = k end
        end
        for k = 1, maxn do
            if kids[k] ~= nil then walk(kids[k], depth + 1) end
        end
        for k, v in pairs(kids) do
            if type(k) ~= "number" then walk(v, depth + 1) end
        end
    end
    walk(ov.UIRoot, 0)
    return out
end

function M:handler()
    if not (G and type(G.OVERLAY_MENU) == "table") then return "inactive" end
    if not sprites()[1] then return "inactive" end
    return "active"
end

function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

local function chip_vtable(sp)
    return {
        label = function(ctx)
            local cfg = sp.config or {}
            if cfg.blind then
                if not cfg.blind.discovered then
                    ctx.message:fragment(Message.localized("LABELS.NOT_DISCOVERED"))
                    return
                end
                local name = Proxy.blind_name(cfg.blind)
                if name then ctx.message:fragment(Message.raw(name)) end
            elseif cfg.tag then
                -- Undiscovered tags render the "?" sprite (hide_ability).
                if cfg.tag.hide_ability then
                    ctx.message:fragment(Message.localized("LABELS.NOT_DISCOVERED"))
                    return
                end
                local ok, name = pcall(localize,
                    { type = "name_text", key = cfg.tag.key, set = "Tag" })
                if ok and type(name) == "string" and name ~= "" then
                    ctx.message:fragment(Message.raw(name))
                end
            end
        end,
        deferred = function()
            local cfg = sp.config or {}
            if not Proxy.announce_enabled("description") then return nil end
            local desc
            if cfg.blind and cfg.blind.discovered then
                desc = Proxy.blind_effect(cfg.blind)
            elseif cfg.tag and not cfg.tag.hide_ability then
                desc = Proxy.tag_description(cfg.tag)
            end
            return desc and Message.raw(desc) or nil
        end,
    }
end

function M:build(b)
    b:capture_input()
    local list = sprites()
    -- Row width matches each screen's matrix: blinds 5 across, tags 6.
    local per_row = (list[1] and list[1].config and list[1].config.tag) and 6 or 5
    local i, row_n = 1, 0
    while i <= #list do
        row_n = row_n + 1
        b:start_row("row" .. row_n, nil, { wrap = true })
        for j = i, math.min(i + per_row - 1, #list) do
            b:add_item(Id.for_object(list[j]), chip_vtable(list[j]))
        end
        b:end_row()
        i = i + per_row
    end
    -- Whatever else the mirror reaches (Back; Steamodded's page cycle) —
    -- minus the stand-in cards already listed above.
    local r = 0
    for _, n in ipairs(Mirror.gather({ G.OVERLAY_MENU })) do
        if not is_item(n) then
            r = r + 1
            b:add_item(Id.referenced(n, "r:" .. r), Mirror.vtable_for(n))
        end
    end
end

return M
