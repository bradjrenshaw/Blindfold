-- ui/proxies.lua — proxy elements that wrap Balatro UIElement nodes and turn
-- them into spoken labels. Port of SayTheSpire2's ProxyElement + concrete
-- proxies, adapted to Balatro's UI node graph (see game_src/engine/ui.lua):
--   * G.UIT.T  text node  -> config.text, or dynamic config.ref_table[ref_value]
--   * G.UIT.O  object node -> config.object (DynaText current text = .string)
--   * config.button         -> clickable; config.focus_args.type -> widget role
local require = ...
local class = require("ui.class")
local Element = require("ui.element")
local Message = require("ui.message")
local A = require("ui.announce").A
local Settings = require("settings.registry")
local Cashout = require("events.cashout")

-- ===================== Proxy base + text extraction =====================
local Proxy = class(Element)

function Proxy.init(self, node)
    self.node = node
    self.override_label = nil
end

local SKIP = { ["<"] = true, [">"] = true, [""] = true, ["[UI ERROR]"] = true }
local function is_skip(s) return s == nil or SKIP[s] end

-- Depth-first walk of a UIElement subtree, never descending into `exclude`.
local function walk(node, exclude, visit, depth)
    depth = depth or 0
    if not node or node == exclude or depth > 14 then return end
    visit(node)
    local kids = node.children
    if kids then for _, c in ipairs(kids) do walk(c, exclude, visit, depth + 1) end end
end

-- A node that itself takes focus as an interactive control (mirrors the config
-- side of Controller:is_node_focusable): a real focus widget, a button, or a
-- force_focus node. Funnel wrappers (funnel_from) and decorative buttons
-- (focus_args.type == 'none', e.g. cycle arrows) are not controls.
local function node_is_control(n)
    local c = n.config
    if not c then return false end
    if c.focus_args then
        if c.focus_args.type == "none" or c.focus_args.funnel_from then return false end
        return true
    end
    return (c.button or c.force_focus) and true or false
end
Proxy.node_is_control = node_is_control   -- used by the menu-mirror overlay's tree walk

-- True when the subtree under `scope` (excluding the focused `node`) holds
-- another interactive control. Such a `scope` is a shared container, not a
-- caption group, so its static text must not be read as this control's label.
function Proxy.has_other_control(scope, node)
    local found = false
    walk(scope, node, function(n) if not found and node_is_control(n) then found = true end end)
    return found
end

-- Literal caption text (G.UIT.T with a plain config.text, no ref binding).
-- config.text can be a NUMBER — the game assigns raw values in places (the
-- run-info poker-hand rows' chips / mult / play counts) — so accept both.
local function literal_text(c)
    local t = c.text
    if type(t) == "number" then return tostring(t) end
    if type(t) == "string" then return t end
    return nil
end

-- A T node is DYNAMIC only when actually ref-BOUND (ref_table AND ref_value);
-- the engine renders config.text whenever ref_table is absent, and some game
-- nodes carry a ref_value as a mere lookup tag (the profile screen's
-- load_button_text) — skipping those read whole buttons as silent.
local function is_ref_bound(c)
    return type(c.ref_table) == "table" and c.ref_value ~= nil
end

function Proxy.static_text(node, exclude)
    local parts = {}
    walk(node, exclude, function(n)
        local c = n.config
        if c and n.UIT == G.UIT.T and not is_ref_bound(c) then
            local t = literal_text(c)
            if t and not is_skip(t) then parts[#parts + 1] = t end
        end
    end)
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Live value text: ref-bound T nodes (slider value) + DynaText objects (cycle
-- current option). Arrow glyphs ('<','>') are skipped.
function Proxy.value_text(node, exclude)
    local parts = {}
    walk(node, exclude, function(n)
        local c = n.config
        if not c then return end
        if n.UIT == G.UIT.T and type(c.ref_table) == "table" and c.ref_value ~= nil then
            local v = c.ref_table[c.ref_value]
            v = v ~= nil and tostring(v) or nil
            if not is_skip(v) then parts[#parts + 1] = v end
        elseif n.UIT == G.UIT.O and c.object and type(c.object.string) == "string"
               and not is_skip(c.object.string) then
            parts[#parts + 1] = c.object.string
        end
    end)
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Some cycles carry a raw option value that isn't meaningful spoken aloud,
-- keyed by the cycle's opt_callback. The stake selector's options are stake
-- levels (1..8); speak the localized stake name ("White Stake") instead.
local CYCLE_VALUE_FORMAT = {
    change_stake = function(v)
        local n = tonumber(v)
        local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
        local center = n and pool and pool[n]
        if center and center.key then
            local ok, name = pcall(localize, { type = "name_text", set = "Stake", key = center.key })
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return tostring(v)
    end,
}

-- A cycle's current option value, read from its args table (current_option_val).
-- Works even for cycles with a custom `mid` (deck/stake selectors) that have no
-- DynaText to read. The cycle's args also carry opt_callback, so a few cycles
-- map their raw value to a friendlier spoken form (see CYCLE_VALUE_FORMAT).
function Proxy.cycle_value(node)
    local val, args
    walk(node, nil, function(n)
        local c = n.config
        if not args and c and type(c.ref_table) == "table" and c.ref_table.current_option_val ~= nil then
            args, val = c.ref_table, c.ref_table.current_option_val
        end
    end)
    if val == nil then return nil end
    local fmt = args and args.opt_callback and CYCLE_VALUE_FORMAT[args.opt_callback]
    return fmt and fmt(val) or tostring(val)
end

-- A few selectors (deck / stake) show an effect description in their preview
-- pane that we skip when reading the value. Re-derive that text from the game's
-- own builders (rather than scraping the live preview subtree), keyed by the
-- cycle's opt_callback. Returns the description string, or nil.
local function deck_description()
    local back = G and G.GAME and G.GAME.viewed_back
    if not back or not back.generate_UI then return nil end
    local ok, def = pcall(function() return back:generate_UI() end)
    if not ok or type(def) ~= "table" then return nil end
    local parts = {}
    Proxy.collect_def_text(def, parts)
    return #parts > 0 and table.concat(parts, " ") or nil
end

local function stake_description()
    local n = G and G.viewed_stake
    local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
    local center = n and pool and pool[n]
    if not center or not center.key then return nil end
    local nodes = {}
    local ok = pcall(localize, { type = "descriptions", key = center.key, set = "Stake", nodes = nodes })
    if not ok then return nil end
    local parts = {}
    Proxy.collect_def_text(nodes, parts)
    return #parts > 0 and table.concat(parts, " ") or nil
end

local CYCLE_DESCRIPTION = {
    change_viewed_back = deck_description,
    change_stake = stake_description,
}

function Proxy.cycle_description(node)
    local args
    walk(node, nil, function(n)
        local c = n.config
        if not args and c and type(c.ref_table) == "table" and c.ref_table.current_option_val ~= nil then
            args = c.ref_table
        end
    end)
    local fn = args and args.opt_callback and CYCLE_DESCRIPTION[args.opt_callback]
    return fn and fn() or nil
end

-- Whether the focused selector's current option is locked. A locked deck still
-- cycles into view but shows its unlock requirement instead of its effect, so we
-- flag the locked state for context. (Stakes on the selector are all
-- selectable, so there's nothing to flag.)
local function deck_locked()
    local back = G and G.GAME and G.GAME.viewed_back
    local center = back and back.effect and back.effect.center
    return center ~= nil and not center.unlocked
end

local CYCLE_LOCKED = {
    change_viewed_back = deck_locked,
}

function Proxy.cycle_locked(node)
    local args
    walk(node, nil, function(n)
        local c = n.config
        if not args and c and type(c.ref_table) == "table" and c.ref_table.current_option_val ~= nil then
            args = c.ref_table
        end
    end)
    local fn = args and args.opt_callback and CYCLE_LOCKED[args.opt_callback]
    return fn and fn() or false
end

-- Static + value combined (generic fallback label).
function Proxy.all_text(node)
    local s, v = Proxy.static_text(node), Proxy.value_text(node)
    if s and v then return s .. " " .. v end
    return s or v
end

-- For controls whose caption sits in a sibling branch above the focused node
-- (sliders, cycles, toggles): climb ancestors and read static text from
-- outside the focused subtree.
function Proxy.label_above(node, max_up)
    max_up = max_up or 4
    local cur, up = node.parent, 0
    while cur and up < max_up do
        -- Don't climb into a container shared with other controls — its text
        -- belongs to those siblings, not to us (e.g. the deck cycle would
        -- otherwise grab the "Seeded Run" / "Play" captions from the ROOT).
        if Proxy.has_other_control(cur, node) then break end
        local t = Proxy.static_text(cur, node)
        if t then return t end
        cur, up = cur.parent, up + 1
    end
    return nil
end

-- First descendant flagged config.chosen (the selected tab/choice).
function Proxy.find_chosen(node, depth)
    depth = depth or 0
    if not node or depth > 14 then return nil end
    if node.config and node.config.chosen then return node end
    if node.children then
        for _, c in ipairs(node.children) do
            local r = Proxy.find_chosen(c, depth + 1)
            if r then return r end
        end
    end
    return nil
end

-- ----- Card helpers (shared by the playing-card and joker proxies) -----

-- Localized game string via the engine's localize(), guarded. `cat` is the misc
-- category, e.g. 'ranks' or 'suits_singular'.
function Proxy.loc_str(key, cat)
    if key == nil then return nil end
    local ok, s = pcall(localize, key, cat)
    if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" then return s end
    return nil
end

-- The localized display name of a center (joker/consumable/enhancement), from
-- G.localization.descriptions[set][key].name. Nil if absent.
function Proxy.center_name(center)
    local d = G and G.localization and G.localization.descriptions
    local set = d and center and center.set and d[center.set]
    local entry = set and center.key and set[center.key]
    return entry and entry.name
end

-- The card's edition as a localized Message (foil/holographic/polychrome/
-- negative), or nil when it has no edition.
local EDITION_KEY = { foil = "foil", holo = "holographic", polychrome = "polychrome", negative = "negative" }
function Proxy.edition_word(node)
    local e = node.edition
    if not e then return nil end
    local t = e.type
        or (e.foil and "foil") or (e.holo and "holo")
        or (e.polychrome and "polychrome") or (e.negative and "negative")
    local k = t and EDITION_KEY[t]
    return k and Message.localized("EDITION." .. k) or nil
end

-- A card's price for the price announcement. Buyable shop items (shop cards,
-- vouchers, booster packs) read their buy cost ("5 dollars", or "free" when a
-- coupon zeroes it). Your own jokers / consumables read their sell value on
-- every screen — it's always visible and some effects depend on it.
function Proxy.card_cost(card)
    if not card or not G then return nil end
    local area = card.area
    if area == G.shop_jokers or area == G.shop_vouchers or area == G.shop_booster then
        local cost = card.cost
        if type(cost) ~= "number" then return nil end
        if cost <= 0 then return Message.localized("SHOP.FREE") end
        return Message.localized("SHOP.COST", { cost = cost })
    end
    if area == G.jokers or area == G.consumeables then
        local sell = card.sell_cost
        if type(sell) == "number" and sell > 0 then
            return Message.localized("SHOP.SELL", { cost = sell })
        end
    end
    return nil
end

-- A joker's rarity, as a "subtype" announcement (common / uncommon / rare /
-- legendary). center.rarity is 1..4; non-jokers (no rarity) yield nil.
local JOKER_RARITY = { "COMMON", "UNCOMMON", "RARE", "LEGENDARY" }
function Proxy.joker_rarity(card)
    local c = card and card.config and card.config.center
    local r = c and c.rarity
    local key = type(r) == "number" and JOKER_RARITY[r]
    return key and Message.localized("RARITY." .. key) or nil
end

-- Collection secrecy, mirroring Card:generate_UIBox_ability_table's own type
-- flip (card.lua:714-724): a locked center reads "locked", an undiscovered
-- Joker/Edition/consumable/Voucher/Booster reads "Not discovered" — the
-- render is a "?" silhouette, so the name must not speak. Cards in your OWN
-- joker/consumable areas are exempt, exactly like the game.
function Proxy.center_hidden(card)
    local center = card and card.config and card.config.center
    if not center then return nil end
    if center.unlocked == false and not card.bypass_lock then return "LOCKED" end
    if not card.bypass_discovery_center and not center.discovered
        and card.ability and (card.ability.set == "Joker" or card.ability.set == "Edition"
            or card.ability.consumeable or card.ability.set == "Voucher"
            or card.ability.set == "Booster")
        and not (G and (card.area == G.jokers or card.area == G.consumeables)) then
        return "NOT_DISCOVERED"
    end
    return nil
end

-- A card's position ("3 of 8"), for the position announcement. With explicit
-- index/total the caller decides the unit (an owned overlay's ROW, which may
-- span several CardAreas); the default is the card's own CardArea order.
function Proxy.card_position(card, index, total)
    if index and total then
        return Message.localized("POSITION.OF", { index = index, total = total })
    end
    local area = card and card.area
    if not area or type(area.cards) ~= "table" then return nil end
    local idx
    for i, c in ipairs(area.cards) do if c == card then idx = i; break end end
    if not idx then return nil end
    return Message.localized("POSITION.OF", { index = idx, total = #area.cards })
end

-- Sell info for a card the player owns (jokers / consumables — nothing else
-- is sellable): its sell value, or "cannot sell" for an eternal — spoken
-- INSTEAD of a value, like the game's greyed-out sell button. Face down the
-- value is hidden (the game itself shows "?") but "cannot sell" still reads:
-- the greyed button is visible on a flipped card, and probing with S would
-- otherwise SELL a non-eternal (S works mid-blind too).
function Proxy.card_sell_message(card)
    if not (G and card and (card.area == G.jokers or card.area == G.consumeables)) then return nil end
    if card.ability and card.ability.eternal then
        return Message.localized("CARD.CANT_SELL"):resolve()
    end
    if card.facing == "back" then return nil end
    local cost = card.sell_cost
    if type(cost) ~= "number" then return nil end
    return Message.localized("CARD.SELL", { amount = cost }):resolve()
end

-- Deferred follow-up for a focused card: its description (gated by the
-- descriptions toggle), THEN its sell info, THEN its position (gated by the
-- position toggle). Description guards face-down cards via card_description
-- (no identity leak; position still reads).
-- index/total override the position's unit (see card_position).
function Proxy.card_deferred(card, index, total)
    local parts = {}
    if Proxy.announce_enabled("description") then
        local d = Proxy.card_description(card)
        if d then parts[#parts + 1] = d end
    end
    local sell = Proxy.card_sell_message(card)
    if sell then parts[#parts + 1] = sell end
    if Proxy.announce_enabled("position") then
        local p = Proxy.card_position(card, index, total)
        if p then parts[#parts + 1] = p:resolve() end
    end
    if #parts == 0 then return nil end
    return Message.raw(table.concat(parts, ", "))
end

-- Hover tooltip text from config.tooltip / config.on_demand_tooltip
-- ({ title, text = {lines} }). The data is right in config, so nothing needs
-- building. (Card ability descriptions are a separate, dynamic case.)
function Proxy:get_tooltip()
    local cfg = self.node and self.node.config
    local tip = cfg and (cfg.tooltip or cfg.on_demand_tooltip)
    if type(tip) ~= "table" then return nil end
    local parts = {}
    if type(tip.title) == "string" and tip.title ~= "" then parts[#parts + 1] = tip.title end
    local function add(text)
        if type(text) == "string" then
            if text ~= "" then parts[#parts + 1] = text end
        elseif type(text) == "table" then
            if text.ref_table and text.ref_value ~= nil then
                local v = text.ref_table[text.ref_value]
                if v ~= nil then parts[#parts + 1] = tostring(v) end
            else
                for _, line in ipairs(text) do add(line) end
            end
        end
    end
    add(tip.text)
    if #parts == 0 then return nil end
    return Message.raw(table.concat(parts, ". "))
end

-- Static caption text of an ancestor as an ordered list (vs static_text which
-- joins). Used to separate a control's label (first item) from trailing help
-- text (the rest).
function Proxy.static_text_list(node, exclude)
    local parts = {}
    walk(node, exclude, function(n)
        local c = n.config
        if c and n.UIT == G.UIT.T and not is_ref_bound(c) then
            local t = literal_text(c)
            if t and not is_skip(t) then parts[#parts + 1] = t end
        end
    end)
    return parts
end

-- The nearest ancestor (climbing) that carries caption text outside the focused
-- subtree, plus that text as an ordered list. For a captioned control with help
-- text, list[1] is the label and list[2..] are the info lines.
function Proxy.captioned_scope(node, max_up)
    max_up = max_up or 4
    local cur, up = node.parent, 0
    while cur and up < max_up do
        if Proxy.has_other_control(cur, node) then return nil, {} end
        local list = Proxy.static_text_list(cur, node)
        if #list > 0 then return cur, list end
        cur, up = cur.parent, up + 1
    end
    return nil, {}
end

-- Walk a raw UI *definition* tree (the { n, config, nodes } form returned by
-- generate_card_ui, not a built UIElement tree) collecting text: T-node text /
-- ref values and DynaText current strings.
function Proxy.collect_def_text(node, parts, depth)
    depth = depth or 0
    if type(node) ~= "table" or depth > 16 then return end
    if node.n ~= nil or node.config ~= nil then
        local c = node.config
        if c then
            local lit = (type(c.text) == "string" and c.text)
                or (type(c.text) == "number" and tostring(c.text)) or nil
            if lit then
                if not is_skip(lit) then parts[#parts + 1] = lit end
            elseif type(c.ref_table) == "table" and c.ref_value ~= nil then
                local v = c.ref_table[c.ref_value]
                if v ~= nil and not is_skip(tostring(v)) then parts[#parts + 1] = tostring(v) end
            end
            local o = c.object
            if o then
                local s
                if type(o.strings) == "table" then
                    local fs = o.focused_string or 1
                    s = o.strings[fs] and o.strings[fs].string
                end
                if type(s) ~= "string" then s = type(o.string) == "string" and o.string or nil end
                if type(s) == "string" and not is_skip(s) then parts[#parts + 1] = s end
            end
        end
        if node.nodes then for _, ch in ipairs(node.nodes) do Proxy.collect_def_text(ch, parts, depth + 1) end end
    else
        for _, ch in ipairs(node) do Proxy.collect_def_text(ch, parts, depth + 1) end
    end
end

-- A card's description text. The game caches it in card.ability_UIBox_table but
-- only rebuilds that on hover, which lags behind the animated cursor — so for
-- scaling jokers (e.g. Ceremonial Dagger's mult) it goes stale. Rebuild it fresh
-- here via the card's own builder so the values are always current, falling back
-- to the cached table for non-Card sources (e.g. tag sprites in the cash-out).
function Proxy.card_description(card)
    if not card then return nil end
    -- Never describe a face-down card — that would reveal its hidden identity.
    if card.facing == "back" then return nil end
    local t
    if type(card.generate_UIBox_ability_table) == "function" then
        local ok, res = pcall(function() return card:generate_UIBox_ability_table() end)
        if ok then t = res end
    end
    t = t or card.ability_UIBox_table
    if type(t) ~= "table" or type(t.main) ~= "table" then return nil end
    local parts = {}
    Proxy.collect_def_text(t.main, parts)
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- A card's keyword "hover tips": the related-concept boxes the game builds
-- alongside the description (ability_UIBox_table.info — each entry is a row-list
-- describing a referenced enhancement / edition / seal / sticker / etc.).
-- Rebuilt fresh (same reason as card_description); returns a list of strings.
-- Keyword tips from an already-built ability_UIBox_table (its .info boxes). Each
-- box carries its keyword's localized name (desc_nodes.name in generate_card_ui)
-- — prepend it: "Foil, +50 chips". Works for any ability table (cards, tags...).
function Proxy.table_info_tips(t)
    if type(t) ~= "table" or type(t.info) ~= "table" then return {} end
    local tips = {}
    for _, box in ipairs(t.info) do
        local parts = {}
        Proxy.collect_def_text(box, parts)
        local desc = #parts > 0 and table.concat(parts, " ") or nil
        if desc then
            local name = type(box.name) == "string" and box.name ~= "" and box.name or nil
            tips[#tips + 1] = name and Message.localized("CARD.TIP", { name = name, desc = desc }):resolve() or desc
        end
    end
    return tips
end

function Proxy.card_info_tips(card)
    if not card or card.facing == "back" then return {} end          -- hide face-down identity
    if type(card.generate_UIBox_ability_table) ~= "function" then return {} end
    local ok, t = pcall(function() return card:generate_UIBox_ability_table() end)
    return ok and Proxy.table_info_tips(t) or {}
end

-- Detail lines for this element's review buffer (the depth offloaded from the
-- concise focus announcement). Default: its tooltip text, if any. Card and blind
-- proxies override to add descriptions + keyword tips. Not gated by the
-- announcement toggles — the buffer is always the full-detail view.
function Proxy:fill_buffer(buf)
    local tip = self:get_tooltip()
    if type(tip) == "table" and tip.resolve then
        local s = tip:resolve()
        if s and s ~= "" then buf:add(s) end
    end
end

-- Secondary help/info text on a control (default: none). Sliders/cycles/toggles
-- override to surface their info lines.
function Proxy:get_extras() return nil end

-- Deferred announcement spoken after the focus message once it becomes
-- available (default: none). Card proxies use it for descriptions, which the
-- game only populates one frame after focus.
function Proxy:get_deferred() return nil end

-- Whether an announcement type is enabled (announce.<key>.enabled in settings),
-- defaulting on. Used for announcements that don't pass through the composer.
function Proxy.announce_enabled(key)
    local v = Settings.value("announce." .. key .. ".enabled")
    if v ~= nil then return v end
    return true
end

-- Default focus message: label, type, status, extras, tooltip (ordered by the
-- element's announcement_order). Silent when there's no meaningful label.
function Proxy:get_focus_announcements()
    local label = self:get_label()
    local status = self:get_status()
    -- Stay silent only when there's truly nothing — a value control with a value
    -- but no label (e.g. the deck selector) should still announce.
    if not label and not status then return {} end
    local anns = {}
    if label then anns[#anns + 1] = A.label(label) end
    if self.type_key then anns[#anns + 1] = A.type(self.type_key) end
    if status then anns[#anns + 1] = A.status(status) end
    local extras = self:get_extras()
    if extras then anns[#anns + 1] = A.extras(extras) end
    local tip = self:get_tooltip()
    if tip then anns[#anns + 1] = A.tooltip(tip) end
    return anns
end

-- Reactive value (slider/cycle/checkbox/tab): poll_value returns the current
-- changeable value as a comparable scalar (nil = nothing to track);
-- get_value_message is what we speak when it changes. The focus tick polls
-- these every frame because Balatro's UI has no change events.
function Proxy:poll_value() return nil end
function Proxy:get_value_message() return self:get_status() end

-- Small helper so each concrete proxy's `.new` is one line.
local function ctor(cls)
    return function(node)
        local self = setmetatable({}, cls)
        Proxy.init(self, node)
        return self
    end
end

-- ===================== Concrete proxies =====================

local ProxyButton = class(Proxy)
ProxyButton.type_key = "button"
ProxyButton.new = ctor(ProxyButton)
function ProxyButton:get_label()
    -- Unlock All (profile screen) is a two-press confirm: the first press
    -- shows the achievements warning (spoken by the mirror's click) and arms
    -- the overlay's infotip slot (config.set). Read the armed state so the
    -- second press is announced as a confirm, not a repeat.
    if self.node.config and self.node.config.button == "unlock_all" then
        local ok, armed = pcall(function()
            local slot = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID
                and G.OVERLAY_MENU:get_UIE_by_ID("overlay_menu_infotip")
            return slot and slot.config and slot.config.set
        end)
        if ok and armed then return Message.localized("MENU.CONFIRM_UNLOCK") end
    end
    -- Delete/Reset Profile's confirm arms differently: the invisible
    -- "Select again to confirm" line (id warning_text) turns WHITE.
    if self.node.config and self.node.config.button == "delete_profile" then
        local ok, armed = pcall(function()
            local w = self.node.UIBox and self.node.UIBox:get_UIE_by_ID("warning_text")
            return w and w.config and w.config.colour == G.C.WHITE
        end)
        if ok and armed then
            local base = Proxy.all_text(self.node)
            return Message.localized("MENU.CONFIRM_ACTION", { action = base or "" })
        end
    end
    -- The reroll button renders "Reroll $ {reroll_cost}", which reads as
    -- "reroll dollar 5". Speak the cost number-first ("5 dollars") instead.
    if self.node.config and self.node.config.button == "reroll_shop" then
        local cr = G and G.GAME and G.GAME.current_round
        local cost = cr and cr.reroll_cost
        if type(cost) == "number" then return Message.localized("SHOP.REROLL", { cost = cost }) end
    end
    -- all_text (static + ref-bound/DynaText values), not just static, so other
    -- buttons with a live value still read it.
    return Message.maybe_raw(self.override_label or Proxy.all_text(self.node))
end

local ProxySlider = class(Proxy)
ProxySlider.type_key = "slider"
ProxySlider.new = ctor(ProxySlider)
function ProxySlider:get_label() return Message.maybe_raw(self.override_label or Proxy.label_above(self.node)) end
function ProxySlider:get_status() return Message.maybe_raw(Proxy.value_text(self.node)) end
function ProxySlider:poll_value() return Proxy.value_text(self.node) end
function ProxySlider:get_extras()
    local _, list = Proxy.captioned_scope(self.node)
    if #list <= 1 then return nil end
    local extra = {}
    for i = 2, #list do extra[#extra + 1] = list[i] end
    return Message.raw(table.concat(extra, ". "))
end

local ProxyCycle = class(Proxy)
ProxyCycle.type_key = "cycle"
ProxyCycle.new = ctor(ProxyCycle)
function ProxyCycle:get_label() return Message.maybe_raw(self.override_label or Proxy.label_above(self.node)) end
function ProxyCycle:get_status() return Message.maybe_raw(Proxy.cycle_value(self.node) or Proxy.value_text(self.node)) end
function ProxyCycle:poll_value() return Proxy.cycle_value(self.node) or Proxy.value_text(self.node) end
function ProxyCycle:get_extras()
    local _, list = Proxy.captioned_scope(self.node)
    if #list <= 1 then return nil end
    local extra = {}
    for i = 2, #list do extra[#extra + 1] = list[i] end
    return Message.raw(table.concat(extra, ". "))
end
-- Flag a locked option (e.g. a locked deck) after the value. The locked state
-- itself is always announced — knowing a deck is locked matters even with
-- descriptions off — while the requirement text rides along as the description.
function ProxyCycle:get_focus_announcements()
    local anns = Proxy.get_focus_announcements(self)
    if Proxy.cycle_locked(self.node) then anns[#anns + 1] = A.locked() end
    return anns
end
-- Deck / stake selectors carry an effect description in their preview pane.
-- Speak it after the value on focus (deferred), and again whenever the option
-- changes, so cycling reveals each deck's / stake's effect. Gated by the
-- "Announce descriptions" setting.
function ProxyCycle:get_deferred()
    if not Proxy.announce_enabled("description") then return nil end
    return Message.maybe_raw(Proxy.cycle_description(self.node))
end
function ProxyCycle:get_value_message()
    local name = Proxy.cycle_value(self.node) or Proxy.value_text(self.node)
    if not name then return nil end
    local out = name
    if Proxy.cycle_locked(self.node) then
        local lk = Message.localized("LABELS.LOCKED"):resolve()
        if lk and lk ~= "" then out = out .. ", " .. lk end
    end
    if Proxy.announce_enabled("description") then
        local desc = Proxy.cycle_description(self.node)
        if desc then out = out .. ". " .. desc end
    end
    return Message.raw(out)
end

local ProxyToggle = class(Proxy)
ProxyToggle.type_key = "checkbox"
ProxyToggle.new = ctor(ProxyToggle)
function ProxyToggle:scope()
    -- Focus funnels onto the toggle button; its caption lives on the funnel_to
    -- container that wraps both label and button.
    local fa = self.node.config and self.node.config.focus_args
    return (fa and fa.funnel_to) or self.node
end
function ProxyToggle:get_label()
    return Message.maybe_raw(self.override_label or Proxy.static_text(self:scope()) or Proxy.label_above(self.node))
end
function ProxyToggle:get_status()
    -- create_toggle stores the bound boolean at args.ref_table[args.ref_value],
    -- where args is the focused button's config.ref_table.
    local args = self.node.config and self.node.config.ref_table
    if type(args) == "table" and type(args.ref_table) == "table" and args.ref_value ~= nil then
        local on = args.ref_table[args.ref_value]
        return Message.localized(on and "STATUS.ON" or "STATUS.OFF")
    end
    return nil
end
function ProxyToggle:poll_value()
    local args = self.node.config and self.node.config.ref_table
    if type(args) == "table" and type(args.ref_table) == "table" and args.ref_value ~= nil then
        return args.ref_table[args.ref_value]
    end
    return nil
end
function ProxyToggle:get_extras()
    -- create_toggle wraps the toggle + its info lines in a 2-child container;
    -- the focused button funnels to the inner toggle, whose sibling is the info.
    local fa = self.node.config and self.node.config.focus_args
    local inner = fa and fa.funnel_to
    local wrapper = inner and inner.parent
    if not (wrapper and wrapper.children and #wrapper.children == 2) then return nil end
    local sib = (wrapper.children[1] == inner and wrapper.children[2])
             or (wrapper.children[2] == inner and wrapper.children[1])
    return sib and Message.maybe_raw(Proxy.static_text(sib, nil)) or nil
end

local ProxyTab = class(Proxy)
ProxyTab.type_key = "tab"
ProxyTab.new = ctor(ProxyTab)
function ProxyTab:get_label()
    local chosen = Proxy.find_chosen(self.node)
    local t = chosen and (Proxy.static_text(chosen) or Proxy.all_text(chosen))
    return Message.maybe_raw(t)
end
function ProxyTab:poll_value()
    local chosen = Proxy.find_chosen(self.node)
    return chosen and (Proxy.static_text(chosen) or Proxy.all_text(chosen)) or nil
end
function ProxyTab:get_value_message() return self:get_label() end

-- Generic focusable element (force_focus info nodes, unrecognized controls).
local ProxyText = class(Proxy)
ProxyText.type_key = nil
ProxyText.new = ctor(ProxyText)
function ProxyText:get_label() return Message.maybe_raw(self.override_label or Proxy.all_text(self.node)) end

-- Text input field (create_text_input, button='select_text_input'). Reads its
-- prompt + current value rather than the raw per-letter nodes. The args table
-- (with .text, .ref_table/.ref_value, .prompt_text) is on the inner rows.
local function textinput_args(node)
    local found
    walk(node, nil, function(n)
        local c = n.config
        if not found and c and type(c.ref_table) == "table"
           and type(c.ref_table.text) == "table" and c.ref_table.ref_value ~= nil then
            found = c.ref_table
        end
    end)
    return found
end

local ProxyTextInput = class(Proxy)
ProxyTextInput.type_key = "text_field"
ProxyTextInput.new = ctor(ProxyTextInput)
function ProxyTextInput:get_label()
    local args = textinput_args(self.node)
    return Message.maybe_raw(self.override_label or (args and args.prompt_text and tostring(args.prompt_text)))
end
function ProxyTextInput:get_status()
    local args = textinput_args(self.node)
    if not args or type(args.ref_table) ~= "table" then return nil end
    local val = args.ref_table[args.ref_value]
    if type(val) == "string" and val ~= "" then return Message.raw(val) end
    return Message.localized("LABELS.EMPTY")
end
function ProxyTextInput:poll_value()
    local args = textinput_args(self.node)
    if not args or type(args.ref_table) ~= "table" then return nil end
    return args.ref_table[args.ref_value]
end

-- Playing card: identity is rank + suit (card.base), with enhancement / edition
-- / seal / debuff as modifiers. (Ability descriptions are a later pass.)
local ProxyPlayingCard = class(Proxy)
ProxyPlayingCard.type_key = "card"
-- Position rides the deferred follow-up (card_deferred), AFTER the description.
ProxyPlayingCard.announcement_order = { "label", "type", "selected", "enhancement", "edition", "seal", "debuff", "price" }
ProxyPlayingCard.new = ctor(ProxyPlayingCard)
-- Collection modifier cards (the seals / enhancements screens) are built on
-- the EMPTY card front — no rank or suit renders. Their identity is the
-- modifier itself: the enhancement center's name, the seal, or the edition.
-- Returns the label message plus which announcement slot it absorbed (that
-- slot is skipped in get_focus_announcements to avoid an echo).
local function faceless_identity(node)
    local base = node.base
    if base and base.value and base.value ~= "" and base.suit and base.suit ~= "" then
        return nil
    end
    local c = node.config and node.config.center
    if c and c.set == "Enhanced" and c.key ~= "c_base" then
        local name = Proxy.center_name(c) or c.name
        if name then return Message.maybe_raw(tostring(name)), "enhancement" end
    end
    if node.seal then
        return Message.localized("SEAL." .. string.upper(tostring(node.seal))), "seal"
    end
    local ed = Proxy.edition_word(node)
    if ed then return Message.maybe_raw(ed), "edition" end
    return nil
end

function ProxyPlayingCard:get_label()
    local node = self.node
    -- Stone cards render NO rank or suit — the draw skips the front face
    -- entirely (card.lua: `ability.effect ~= 'Stone Card'`) and the game
    -- treats them as rankless/suitless. Read the enhancement name instead.
    if node.ability and node.ability.effect == "Stone Card" then
        local name = Proxy.center_name(node.config and node.config.center)
        return Message.maybe_raw(name and tostring(name) or "Stone Card")
    end
    local fl = faceless_identity(node)
    if fl then return fl end
    local base = node.base
    if not base then return nil end
    local rank = Proxy.loc_str(base.value, "ranks") or tostring(base.value or "")
    local suit = Proxy.loc_str(base.suit, "suits_plural") or tostring(base.suit or "")
    return Message.localized("CARD.PLAYING", { rank = rank, suit = suit })
end
function ProxyPlayingCard:get_focus_announcements()
    local node = self.node
    -- Face down: the identity is hidden, so never reveal rank/suit/modifiers —
    -- just say it's a face-down card (selection still useful; position deferred).
    if node.facing == "back" then
        local anns = { A.label(Message.localized("CARD.FACE_DOWN")), A.type(self.type_key) }
        if node.highlighted then anns[#anns + 1] = A.selected() end
        -- Cerulean Bell's forced card is visibly raised even when face down.
        if node.ability and node.ability.forced_selection then
            anns[#anns + 1] = A.status(Message.localized("CARD.FORCED"))
        end
        return anns
    end
    local label = self:get_label()
    if not label then return {} end
    local anns = { A.label(label), A.type(self.type_key) }
    if node.highlighted then anns[#anns + 1] = A.selected() end
    if node.ability and node.ability.forced_selection then
        anns[#anns + 1] = A.status(Message.localized("CARD.FORCED"))
    end
    -- A faceless card's label already carries one modifier; skip that slot.
    local _, consumed = faceless_identity(node)
    local c = node.config and node.config.center
    -- Stone's enhancement IS the label (rankless/suitless), so don't repeat it.
    if c and c.set == "Enhanced" and c.key ~= "c_base"
        and consumed ~= "enhancement"
        and not (node.ability and node.ability.effect == "Stone Card") then
        local name = Proxy.center_name(c) or c.name
        if name then anns[#anns + 1] = A.enhancement(tostring(name)) end
    end
    local ed = Proxy.edition_word(node)
    if ed and consumed ~= "edition" then anns[#anns + 1] = A.edition(ed) end
    if node.seal and consumed ~= "seal" then
        anns[#anns + 1] = A.seal(Message.localized("SEAL." .. string.upper(tostring(node.seal))))
    end
    if node.debuff then anns[#anns + 1] = A.debuff() end
    local price = Proxy.card_cost(node)
    if price then anns[#anns + 1] = A.price(price) end
    return anns
end
function ProxyPlayingCard:get_deferred()
    return Proxy.card_deferred(self.node)        -- description (guarded) then position
end
function ProxyPlayingCard:fill_buffer(buf)
    local desc = Proxy.card_description(self.node)         -- both guard face-down
    if desc then buf:add(desc) end
    for _, tip in ipairs(Proxy.card_info_tips(self.node)) do buf:add(tip) end
    local pos = Proxy.card_position(self.node)
    if pos then buf:add(pos:resolve()) end
end
-- Selecting/deselecting (highlighting) a card re-announces just the new state.
function ProxyPlayingCard:poll_value() return self.node.highlighted and true or false end
function ProxyPlayingCard:get_value_message()
    return Message.localized(self.node.highlighted and "CARD.SELECTED" or "CARD.DESELECTED")
end

-- Joker / consumable / voucher / booster: localized name + kind + edition.
-- (Ability description text is the next pass.)
local SET_TO_TYPE = {
    Joker = "joker", Tarot = "tarot", Planet = "planet",
    Spectral = "spectral", Voucher = "voucher", Booster = "booster",
}
local ProxyJoker = class(Proxy)
-- Position rides the deferred follow-up (card_deferred), AFTER the description.
ProxyJoker.announcement_order = { "label", "subtype", "type", "selected", "edition", "debuff", "pinned", "price" }
ProxyJoker.new = ctor(ProxyJoker)

-- The win-stake sticker (collection jokers: the badge for the best stake
-- won with that joker). card.sticker is a stake colour from G.sticker_map;
-- speak the localized stake name ("Gold Stake sticker"). Drawn on card
-- BACKS too, so face-down cards keep it.
local function win_sticker(node)
    if type(node.sticker) ~= "string" then return nil end
    local name = node.sticker
    pcall(function()
        for i, colour in ipairs(G.sticker_map or {}) do
            if colour == node.sticker then
                local center = G.P_CENTER_POOLS.Stake[i]
                local ok, s = pcall(localize,
                    { type = "name_text", set = "Stake", key = center.key })
                if ok and type(s) == "string" and s ~= "" then name = s end
                break
            end
        end
    end)
    return A.status(Message.localized("CARD.WIN_STICKER", { stake = name }))
end

-- What a face-down card legitimately shows, so a flipped joker (Amber Acorn)
-- reads with the same tells a sighted player gets and nothing more:
--   * geometry — Wee Joker is 0.7-scale, Square Joker is square (the game
--     only resizes them once discovered, so the gate rides along free);
--   * a mismatched back — copy_card omits the deck's bypass_back, so Ankh /
--     Invisible Joker copies wear the red deck's back, a tell only when the
--     run's deck isn't red.
-- Editions are NOT visible (their shaders only draw on the front face), and
-- the game hides the sell price ("?"), so neither is spoken.
local function face_down_label(node)
    local parts = { Message.localized("CARD.FACE_DOWN"):resolve() }
    local T = node.T
    if T and G and G.CARD_W and G.CARD_H then
        if T.w < G.CARD_W * 0.85 then
            parts[#parts + 1] = Message.localized("CARD.TELL_SMALL"):resolve()
        elseif math.abs(T.h - T.w) < 0.001 then
            parts[#parts + 1] = Message.localized("CARD.TELL_SQUARE"):resolve()
        end
    end
    if not node.playing_card and not (node.params and node.params.bypass_back) then
        local deck = G and G.GAME and G.GAME.selected_back
        local key = deck and deck.effect and deck.effect.center and deck.effect.center.key
        if key and key ~= "b_red" then
            parts[#parts + 1] = Message.localized("CARD.TELL_RED_BACK"):resolve()
        end
    end
    return Message.raw(table.concat(parts, ", "))
end

function ProxyJoker:get_label()
    local hidden = Proxy.center_hidden(self.node)
    if hidden then return Message.localized("LABELS." .. hidden) end
    if self.node.facing == "back" then return face_down_label(self.node) end
    local c = self.node.config and self.node.config.center
    local name = Proxy.center_name(c)
        or (self.node.ability and self.node.ability.name)
        or (c and c.name)
    return Message.maybe_raw(name and tostring(name))
end
function ProxyJoker:get_focus_announcements()
    local node = self.node
    -- Locked / undiscovered (collection): a "?" silhouette renders — just
    -- the hidden state and the set's type word (the silhouette art is
    -- per-set, so the type is visible).
    local hidden = Proxy.center_hidden(node)
    if hidden then
        local anns = { A.label(Message.localized("LABELS." .. hidden)) }
        local set = node.ability and node.ability.set
        local tword = set and SET_TO_TYPE[set]
        if tword then anns[#anns + 1] = A.type(tword) end
        return anns
    end
    -- Face down: identity hidden — no name, rarity, edition or price. The
    -- type word stays (the row already tells you it's a joker) and so does
    -- the selection state, mirroring the face-down playing-card readout.
    if node.facing == "back" then
        local anns = { A.label(face_down_label(node)) }
        local set = node.ability and node.ability.set
        local tword = set and SET_TO_TYPE[set]
        if tword then anns[#anns + 1] = A.type(tword) end
        if node.highlighted then anns[#anns + 1] = A.selected() end
        -- Pinned stays spoken face down: the card visibly never leaves the
        -- left edge, so its position is public knowledge either way.
        if node.pinned then anns[#anns + 1] = A.pinned() end
        local sticker = win_sticker(node)
        if sticker then anns[#anns + 1] = sticker end
        return anns
    end
    local label = self:get_label()
    if not label then return {} end
    local anns = { A.label(label) }
    local rar = Proxy.joker_rarity(node)
    if rar then anns[#anns + 1] = A.subtype(rar) end
    local set = node.ability and node.ability.set
    local tword = set and SET_TO_TYPE[set]
    if tword then anns[#anns + 1] = A.type(tword) end
    if node.highlighted then anns[#anns + 1] = A.selected() end
    local ed = Proxy.edition_word(node)
    if ed then anns[#anns + 1] = A.edition(ed) end
    if node.debuff then anns[#anns + 1] = A.debuff() end
    if node.pinned then anns[#anns + 1] = A.pinned() end
    local sticker = win_sticker(node)
    if sticker then anns[#anns + 1] = sticker end
    local price = Proxy.card_cost(node)
    if price then anns[#anns + 1] = A.price(price) end
    return anns
end
function ProxyJoker:get_deferred()
    return Proxy.card_deferred(self.node)        -- description then position
end
function ProxyJoker:fill_buffer(buf)
    local desc = Proxy.card_description(self.node)
    if desc then buf:add(desc) end
    for _, tip in ipairs(Proxy.card_info_tips(self.node)) do buf:add(tip) end
    local sell = Proxy.card_sell_message(self.node)
    if sell then buf:add(sell) end
    local pos = Proxy.card_position(self.node)
    if pos then buf:add(pos:resolve()) end
end
function ProxyJoker:poll_value() return self.node.highlighted and true or false end
function ProxyJoker:get_value_message()
    return Message.localized(self.node.highlighted and "CARD.SELECTED" or "CARD.DESELECTED")
end

-- Blind select screen: the Select and Skip buttons are the only focusable nodes,
-- but each blind panel also shows the blind name, score requirement, reward,
-- effect, and (for Small/Big) a skip tag. The Select button carries the blind
-- config in config.ref_table; the Skip button carries its Tag. Read those for an
-- accurate readout instead of scraping the panel.
local BLIND_TYPES = { Small = true, Big = true, Boss = true }

local function blind_panel_type(node)
    local cur, up = node, 0
    while cur and up < 8 do
        local c = cur.config
        if c and c.id and BLIND_TYPES[c.id] then return c.id end
        cur, up = cur.parent, up + 1
    end
    return nil
end

local function blind_name(cfg)
    if not cfg or not cfg.key then return nil end
    local ok, n = pcall(localize, { type = "name_text", key = cfg.key, set = "Blind" })
    if ok and type(n) == "string" and n ~= "" then return n end
    return cfg.name
end

local function blind_requirement(cfg)
    if not cfg or type(get_blind_amount) ~= "function" then return nil end
    local ok, amt = pcall(function()
        local rr = G.GAME and G.GAME.round_resets
        local ante = (rr and (rr.blind_ante or rr.ante)) or 1
        local scaling = (G.GAME and G.GAME.starting_params and G.GAME.starting_params.ante_scaling) or 1
        return get_blind_amount(ante) * (cfg.mult or 1) * scaling
    end)
    if not ok or type(amt) ~= "number" then return nil end
    local okf, s = pcall(number_format, amt)
    return Message.localized("BLIND.REQUIREMENT", { amount = (okf and s) or tostring(amt) }):resolve()
end

local function blind_effect(cfg)
    if not cfg or not cfg.key then return nil end
    local hand = G.GAME and G.GAME.current_round and G.GAME.current_round.most_played_poker_hand
    local vars = { (hand and Proxy.loc_str(hand, "poker_hands")) or "" }
    local ok, lines = pcall(localize, { type = "raw_descriptions", key = cfg.key, set = "Blind", vars = vars })
    if not ok or type(lines) ~= "table" then return nil end
    local parts = {}
    for _, ln in ipairs(lines) do if type(ln) == "string" and ln ~= "" then parts[#parts + 1] = ln end end
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Exported for the blinds collection gallery (works on raw P_BLINDS entries).
Proxy.blind_name = blind_name
Proxy.blind_effect = blind_effect

-- A skip tag's description, via the game's own builder (mirrors a card's
-- ability_UIBox_table). get_uibox_table populates it with the right loc vars.
local function tag_description(tag)
    if type(tag) ~= "table" or type(tag.get_uibox_table) ~= "function" then return nil end
    local ok, sprite = pcall(function() return tag:get_uibox_table() end)
    if not ok or type(sprite) ~= "table" then return nil end
    return Proxy.card_description(sprite)
end
-- Exported for the tags collection gallery.
Proxy.tag_description = tag_description

local ProxyBlind = class(Proxy)
ProxyBlind.new = ctor(ProxyBlind)
function ProxyBlind:blind_cfg()
    local c = self.node.config
    if c and c.button == "select_blind" and type(c.ref_table) == "table" then return c.ref_table end
    local ty = blind_panel_type(self.node)
    local rr = G and G.GAME and G.GAME.round_resets
    local key = ty and rr and rr.blind_choices and rr.blind_choices[ty]
    return key and G.P_BLINDS and G.P_BLINDS[key] or nil
end
function ProxyBlind:get_focus_announcements()
    -- force_skip: the game strips config.button off non-current panels every
    -- frame (blind_choice_handler), so a disabled Skip node can't be routed by
    -- its button; the blinds overlay flags it explicitly.
    if self.force_skip or (self.node.config and self.node.config.button == "skip_blind") then
        return self:skip_announcements()
    end
    return self:select_announcements()
end
function ProxyBlind:select_announcements()
    local cfg = self:blind_cfg()
    local anns = {}
    local name = blind_name(cfg)
    if name then anns[#anns + 1] = A.label(name) end
    anns[#anns + 1] = A.type("button")
    -- Action + requirement + reward go in status (always on); effect is gated.
    local parts = {}
    -- State word from the SEMANTIC table, localized here: the button's display
    -- text binds loc_blind_states, which Game:update only refreshes a frame
    -- AFTER blind_states changes (game.lua:2641) — reading it at panel
    -- creation said "Upcoming" for the now-current blind.
    local action
    local ty = blind_panel_type(self.node)
    local st = ty and G and G.GAME and G.GAME.round_resets
        and G.GAME.round_resets.blind_states and G.GAME.round_resets.blind_states[ty]
    if st then
        local ok, w = pcall(localize, st, "blind_states")
        if ok and type(w) == "string" and w ~= "" then action = w end
    end
    action = action or Proxy.value_text(self.node)
    if action then parts[#parts + 1] = action end
    local req = blind_requirement(cfg)
    if req then parts[#parts + 1] = req end
    if cfg and type(cfg.dollars) == "number" and cfg.dollars > 0 then
        parts[#parts + 1] = Message.localized("BLIND.REWARD", { dollars = tostring(cfg.dollars) }):resolve()
    end
    if #parts > 0 then anns[#anns + 1] = A.status(table.concat(parts, ", ")) end
    if Proxy.announce_enabled("description") then
        local eff = blind_effect(cfg)
        if eff then anns[#anns + 1] = A.description(eff) end
    end
    return anns
end
function ProxyBlind:skip_announcements()
    local anns = {}
    local name = blind_name(self:blind_cfg())
    if name then anns[#anns + 1] = A.label(name) end
    anns[#anns + 1] = A.type("button")
    local parts = { Message.localized("BLIND.SKIP"):resolve() }
    local tag = self.node.config and self.node.config.ref_table
    if type(tag) == "table" then
        local tname
        if tag.key then
            local ok, n = pcall(localize, { type = "name_text", key = tag.key, set = "Tag" })
            if ok and type(n) == "string" and n ~= "" then tname = n end
        end
        tname = tname or tag.name
        if tname then parts[#parts + 1] = tname end
    end
    anns[#anns + 1] = A.status(table.concat(parts, ", "))
    if Proxy.announce_enabled("description") and type(tag) == "table" then
        local td = tag_description(tag)
        if td then anns[#anns + 1] = A.description(td) end
    end
    return anns
end
-- Buffer detail: the skip tag's keyword tips (e.g. the Foil tip when the tag
-- grants a foil joker) — these aren't in the focus readout. The tag's own
-- description already rides the focus message (gated).
function ProxyBlind:fill_buffer(buf)
    local c = self.node.config
    if c and c.button == "skip_blind" and type(c.ref_table) == "table"
       and type(c.ref_table.get_uibox_table) == "function" then
        local ok, sprite = pcall(function() return c.ref_table:get_uibox_table() end)
        local t = ok and type(sprite) == "table" and sprite.ability_UIBox_table or nil
        for _, tip in ipairs(Proxy.table_info_tips(t)) do buf:add(tip) end
    end
end

-- Cash-out screen: the only focusable node is the Cash Out button (it snaps to
-- focus when the round-eval finishes). Focus speaks just the total; the money
-- breakdown (events/cashout.lua) is browsable per source in the Cash Out buffer.
local ProxyCashOut = class(Proxy)
ProxyCashOut.new = ctor(ProxyCashOut)
function ProxyCashOut:get_focus_announcements()
    -- Concise: just the total. The per-source breakdown lives in the Cash Out
    -- buffer (browsable, with joker/tag drill-down) via fill_buffer.
    local anns = { A.label(Message.localized("CASHOUT.LABEL")) }
    local total = (G and G.GAME and G.GAME.current_round and G.GAME.current_round.dollars) or Cashout.total
    if type(total) == "number" then
        anns[#anns + 1] = A.status(Message.localized("CASHOUT.TOTAL", { dollars = total }))
    end
    return anns
end
-- Buffer: one item per money source. Each joker/tag drills into its DESCRIPTION
-- (the "why" of the payout) — but not its keyword tips (foil, enhancements, ...),
-- which are scoring/edition info and don't contribute to the cash-out money.
function ProxyCashOut:fill_buffer(buf)
    for _, row in ipairs(Cashout.rows or {}) do
        buf:add(Cashout.summary(row))
        if row.card then
            local d = Proxy.card_description(row.card)
            if d then buf:add(d) end
        elseif type(row.tag) == "table" and type(row.tag.get_uibox_table) == "function" then
            local ok, sprite = pcall(function() return row.tag:get_uibox_table() end)
            if ok and type(sprite) == "table" then
                local d = Proxy.card_description(sprite)
                if d then buf:add(d) end
            end
        end
    end
end

return {
    Proxy = Proxy,
    Button = ProxyButton, Slider = ProxySlider, Cycle = ProxyCycle,
    Toggle = ProxyToggle, Tab = ProxyTab, Text = ProxyText, TextInput = ProxyTextInput,
    PlayingCard = ProxyPlayingCard, Joker = ProxyJoker, Blind = ProxyBlind,
    CashOut = ProxyCashOut,
}
