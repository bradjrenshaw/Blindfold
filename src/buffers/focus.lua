-- buffers/focus.lua — review buffers that bind to the focused element and hold
-- its detailed info, so the focus announcement stays concise while the depth
-- (description + keyword tips) is browsable on demand (Ctrl + arrows). Port of
-- SayTheSpire2's per-entity buffers. One buffer per kind: card (playing card),
-- joker, consumable, and a generic ui buffer for everything else.
--
-- Binding is cheap: focus only stores the entity and clears stale contents; the
-- expensive population (which rebuilds the card's ability table for description
-- and keyword tips) happens lazily in update(), i.e. only when the user actually
-- browses into the buffer.
local require = ...
local Buffer = require("buffers.buffer")
local Manager = require("buffers.manager")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy

-- The element's own focus readout (what you heard on focus) — the buffer header.
local function header(entity)
    local proxy = Factory.create(entity)
    local m = proxy and proxy:get_focus_message()
    local s = m and m:resolve() or ""
    return s ~= "" and s or nil
end

-- Detail for a focused card: header, description, then each keyword tip.
local function card_detail(buf, card)
    local h = header(card); if h then buf:add(h) end
    local desc = Proxy.card_description(card)
    if desc then buf:add(desc) end
    for _, tip in ipairs(Proxy.card_info_tips(card)) do buf:add(tip) end
end

-- Detail for a generic UI element: header + any tooltip text.
local function ui_detail(buf, node)
    local proxy = Factory.create(node)
    if not proxy then return end
    local h = proxy:get_focus_message()
    local hs = h and h:resolve() or ""
    if hs ~= "" then buf:add(hs) end
    local tip = proxy.get_tooltip and proxy:get_tooltip()
    if type(tip) == "table" and tip.resolve then
        local ts = tip:resolve()
        if ts and ts ~= "" then buf:add(ts) end
    end
end

local function make(key, detail)
    -- Disabled until something of this kind is focused; bind_focus enables it.
    local b = Buffer.new(key, { enabled = false })
    b.bound = nil
    b.update = function(self)
        self:repopulate(function()
            if self.bound and not self.bound.REMOVED then detail(self, self.bound) end
        end)
    end
    -- Cheap: just remember the entity and drop stale contents; populate later.
    b.bind = function(self, entity)
        if self.bound ~= entity then
            self.bound = entity
            self.contents = {}
            self.position = 1
        end
    end
    return b
end

local M = {}
M.card = make("card", card_detail)
M.joker = make("joker", card_detail)
M.consumable = make("consumable", card_detail)
M.ui = make("ui", ui_detail)
local ALL = { M.card, M.joker, M.consumable, M.ui }

-- The buffer that should hold a focused node's detail (mirrors the factory's
-- card dispatch). Non-cards fall to the generic ui buffer.
local function route(node)
    if node.is and Card and node:is(Card) then
        local base = node.base
        local set = node.ability and node.ability.set
        if (base and base.suit) or set == "Default" or set == "Enhanced" then return M.card end
        if set == "Joker" then return M.joker end
        return M.consumable
    end
    return M.ui
end

-- On focus: bind the node into its buffer, then make ONLY that focus buffer
-- reachable and auto-focus it (silently) — so e.g. focusing a joker makes the
-- joker buffer current, ready to browse. The game buffer stays always-enabled.
function M.bind_focus(node)
    if not node then return end
    local target = route(node)
    target:bind(node)
    for _, fb in ipairs(ALL) do Manager.set_enabled(fb, fb == target) end
    Manager.set_current(target)
end

return M
