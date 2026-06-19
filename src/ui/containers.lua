-- ui/containers.lua — screen-reader "container" announcements (port of
-- SayTheSpire2's FocusContext). The focusable card rows are CardAreas (hand,
-- jokers, consumables, shop, ...). We track the container path to the last
-- focused node and, on each focus change, announce only the containers newly
-- entered since last focus — so moving within a row stays quiet, but moving onto
-- a new row says its name ("Jokers"). Position within the row ("3 of 8") is
-- emitted by the card proxies themselves (see Proxy.card_position).
local require = ...
local Message = require("ui.message")
local Settings = require("settings.registry")

local M = { _last = {} }

local function enabled()
    local v = Settings.value("announce.container.enabled")
    if v ~= nil then return v end
    return true
end

-- A CardArea's container key. area.config.type is 'joker' for BOTH the joker and
-- consumable areas, so identity is resolved by comparing to the live globals.
local function area_key(area)
    if not area or not G then return nil end
    if area == G.hand then return "HAND"
    elseif area == G.jokers then return "JOKERS"
    elseif area == G.consumeables then return "CONSUMABLES"
    elseif area == G.shop_jokers then return "SHOP"
    elseif area == G.shop_vouchers then return "VOUCHERS"
    elseif area == G.shop_booster then return "BOOSTERS"
    elseif area == G.pack_cards then return "PACK"
    elseif area == G.deck then return "DECK"
    elseif area == G.play then return "PLAYED"
    end
    return nil
end

-- The container path (root-first) for a focused node. Cards live in a CardArea;
-- other nodes have no container yet (single-level for now, but the diffing below
-- already handles arbitrary depth for when UI groups are added).
local function path_for(node)
    local keys = {}
    if node and node.area then
        local k = area_key(node.area)
        if k then keys[#keys + 1] = k end
    end
    return keys
end

-- On focus change, return the labels (joined) of containers newly entered since
-- the last focus, or nil. Always updates the tracked path so the next diff is
-- correct, even when the result is suppressed by the setting.
function M.on_focus(node)
    local newp = path_for(node)
    local oldp = M._last
    M._last = newp
    if not enabled() then return nil end

    local diverge, minlen = 1, math.min(#oldp, #newp)
    while diverge <= minlen and oldp[diverge] == newp[diverge] do diverge = diverge + 1 end
    if diverge > #newp then return nil end   -- nothing new entered

    local parts = {}
    for i = diverge, #newp do
        parts[#parts + 1] = Message.localized("CONTAINER." .. newp[i]):resolve()
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

function M.reset() M._last = {} end

return M
