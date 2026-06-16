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

-- True when the subtree under `scope` (excluding the focused `node`) holds
-- another interactive control. Such a `scope` is a shared container, not a
-- caption group, so its static text must not be read as this control's label.
function Proxy.has_other_control(scope, node)
    local found = false
    walk(scope, node, function(n) if not found and node_is_control(n) then found = true end end)
    return found
end

-- Literal caption text (G.UIT.T with a plain config.text, no ref binding).
function Proxy.static_text(node, exclude)
    local parts = {}
    walk(node, exclude, function(n)
        local c = n.config
        if c and n.UIT == G.UIT.T and type(c.text) == "string"
           and c.ref_value == nil and not is_skip(c.text) then
            parts[#parts + 1] = c.text
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
        if c and n.UIT == G.UIT.T and type(c.text) == "string"
           and c.ref_value == nil and not is_skip(c.text) then
            parts[#parts + 1] = c.text
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
            if type(c.text) == "string" then
                if not is_skip(c.text) then parts[#parts + 1] = c.text end
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

-- A card's description text from the game-managed ability_UIBox_table (set on
-- hover at card.lua:4321). Reads, never builds, so no DynaText leak.
function Proxy.card_description(card)
    local t = card and card.ability_UIBox_table
    if type(t) ~= "table" or type(t.main) ~= "table" then return nil end
    local parts = {}
    Proxy.collect_def_text(t.main, parts)
    return #parts > 0 and table.concat(parts, " ") or nil
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
    return Message.maybe_raw(self.override_label or Proxy.static_text(self.node) or Proxy.all_text(self.node))
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
ProxyPlayingCard.announcement_order = { "label", "type", "selected", "enhancement", "edition", "seal", "debuff", "description", "position" }
ProxyPlayingCard.new = ctor(ProxyPlayingCard)
function ProxyPlayingCard:get_label()
    local base = self.node.base
    if not base then return nil end
    local rank = Proxy.loc_str(base.value, "ranks") or tostring(base.value or "")
    local suit = Proxy.loc_str(base.suit, "suits_plural") or tostring(base.suit or "")
    return Message.localized("CARD.PLAYING", { rank = rank, suit = suit })
end
function ProxyPlayingCard:get_focus_announcements()
    local label = self:get_label()
    if not label then return {} end
    local node = self.node
    local anns = { A.label(label), A.type(self.type_key) }
    if node.highlighted then anns[#anns + 1] = A.selected() end
    local c = node.config and node.config.center
    if c and c.set == "Enhanced" and c.key ~= "c_base" then
        local name = Proxy.center_name(c) or c.name
        if name then anns[#anns + 1] = A.enhancement(tostring(name)) end
    end
    local ed = Proxy.edition_word(node)
    if ed then anns[#anns + 1] = A.edition(ed) end
    if node.seal then anns[#anns + 1] = A.seal(Message.localized("SEAL." .. string.upper(tostring(node.seal)))) end
    if node.debuff then anns[#anns + 1] = A.debuff() end
    if node.facing == "back" then anns[#anns + 1] = A.status(Message.localized("CARD.FACE_DOWN")) end
    return anns
end
function ProxyPlayingCard:get_deferred()
    if not Proxy.announce_enabled("description") then return nil end
    return Message.maybe_raw(Proxy.card_description(self.node))
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
ProxyJoker.announcement_order = { "label", "type", "selected", "edition", "debuff", "description", "position" }
ProxyJoker.new = ctor(ProxyJoker)
function ProxyJoker:get_label()
    local c = self.node.config and self.node.config.center
    local name = Proxy.center_name(c)
        or (self.node.ability and self.node.ability.name)
        or (c and c.name)
    return Message.maybe_raw(name and tostring(name))
end
function ProxyJoker:get_focus_announcements()
    local label = self:get_label()
    if not label then return {} end
    local node = self.node
    local anns = { A.label(label) }
    local set = node.ability and node.ability.set
    local tword = set and SET_TO_TYPE[set]
    if tword then anns[#anns + 1] = A.type(tword) end
    if node.highlighted then anns[#anns + 1] = A.selected() end
    local ed = Proxy.edition_word(node)
    if ed then anns[#anns + 1] = A.edition(ed) end
    if node.debuff then anns[#anns + 1] = A.debuff() end
    return anns
end
function ProxyJoker:get_deferred()
    if not Proxy.announce_enabled("description") then return nil end
    return Message.maybe_raw(Proxy.card_description(self.node))
end
function ProxyJoker:poll_value() return self.node.highlighted and true or false end
function ProxyJoker:get_value_message()
    return Message.localized(self.node.highlighted and "CARD.SELECTED" or "CARD.DESELECTED")
end

return {
    Proxy = Proxy,
    Button = ProxyButton, Slider = ProxySlider, Cycle = ProxyCycle,
    Toggle = ProxyToggle, Tab = ProxyTab, Text = ProxyText, TextInput = ProxyTextInput,
    PlayingCard = ProxyPlayingCard, Joker = ProxyJoker,
}
