-- ui/announce.lua — the announcement-type system (port of SayTheSpire2).
--
-- Each announcement is one semantic piece of a focus message (label, type,
-- status, ...). The Composer orders the announcements an element yields by that
-- element's `announcement_order`, renders each, and joins them with each
-- announcement's suffix + a space (the last suffix is dropped, so no trailing
-- punctuation). A Context carries per-announcement settings resolution; for now
-- it's a stub that returns defaults, leaving the seam for a settings UI later.
local require = ...
local Message = require("ui.message")
local Settings = require("settings.registry")

local function msg(v) return type(v) == "string" and Message.raw(v) or v end

-- One constructor per concept. Each returns { key, suffix, render(ctx)->Message }.
local A = {}
function A.label(label)    return { key = "label",    suffix = ",", render = function() return msg(label) end } end
function A.type(type_key)  return { key = "type",     suffix = ",", render = function() return Message.localized("TYPES." .. string.upper(type_key)) end } end
-- Subtype reads as an adjective before the type (empty suffix → "common joker").
function A.subtype(v)      return { key = "subtype",  suffix = "",  render = function() return msg(v) end } end
function A.status(value)   return { key = "status",   suffix = ",", render = function() return msg(value) end } end
function A.tooltip(text)   return { key = "tooltip",  suffix = "",  render = function() return msg(text) end } end
function A.locked()        return { key = "locked",   suffix = ",", render = function() return Message.localized("LABELS.LOCKED") end } end
function A.position(text)  return { key = "position", suffix = "",  render = function() return msg(text) end } end
-- Card modifiers.
function A.enhancement(v)  return { key = "enhancement", suffix = ",", render = function() return msg(v) end } end
function A.edition(v)      return { key = "edition",     suffix = ",", render = function() return msg(v) end } end
function A.seal(v)         return { key = "seal",        suffix = ",", render = function() return msg(v) end } end
function A.debuff()        return { key = "debuff",      suffix = ",", render = function() return Message.localized("CARD.DEBUFFED") end } end
-- Challenge jokers locked to the left edge (the game's "Pinned" badge).
function A.pinned()        return { key = "pinned",      suffix = ",", render = function() return Message.localized("CARD.PINNED") end } end
function A.selected()      return { key = "selected",    suffix = ",", render = function() return Message.localized("CARD.SELECTED") end } end
function A.description(v)  return { key = "description", suffix = "",  render = function() return msg(v) end } end
-- Secondary help/info text on a control (e.g. an option's explanatory line).
function A.extras(v)       return { key = "extras",      suffix = ",", render = function() return msg(v) end } end
-- A shop item's buy cost.
function A.price(v)        return { key = "price",       suffix = ",", render = function() return msg(v) end } end

-- Per-announcement settings: reads announce.<ann>.<setting> from the registry
-- (e.g. announce.type.enabled). Unregistered keys fall back to the default, so
-- announcements without a toggle stay on.
local Context = {}
Context.__index = Context
function Context.new(element) return setmetatable({ element = element }, Context) end
function Context:resolve_bool(ann_key, setting_key, default)
    local v = Settings.value("announce." .. ann_key .. "." .. setting_key)
    if v ~= nil then return v end
    return default
end

local Composer = {}
function Composer.compose(element, announcements)
    local ctx = Context.new(element)
    local order = element.announcement_order or {}
    local pos = {}
    for i, k in ipairs(order) do pos[k] = i end

    -- Partition declared (keyed by announcement order) vs undeclared (yield order).
    local declared, undeclared = {}, {}
    for _, a in ipairs(announcements) do
        if pos[a.key] and not declared[a.key] then declared[a.key] = a
        else undeclared[#undeclared + 1] = a end
    end

    local sorted = {}
    for _, k in ipairs(order) do if declared[k] then sorted[#sorted + 1] = declared[k] end end
    for _, a in ipairs(undeclared) do sorted[#sorted + 1] = a end

    -- Render, drop disabled/empty.
    local rendered = {}
    for _, a in ipairs(sorted) do
        if ctx:resolve_bool(a.key, "enabled", true) then
            local m = a.render(ctx)
            local text = m and m:resolve() or ""
            if text ~= "" then
                local suffix = ctx:resolve_bool(a.key, "include_suffix", true) and (a.suffix or "") or ""
                rendered[#rendered + 1] = { text = text, suffix = suffix }
            end
        end
    end
    if #rendered == 0 then return Message.empty end

    -- Join: each announcement's suffix sits between it and the next (last dropped).
    local sb = {}
    for i, r in ipairs(rendered) do
        if i > 1 then sb[#sb + 1] = rendered[i - 1].suffix .. " " end
        sb[#sb + 1] = r.text
    end
    return Message.raw(table.concat(sb))
end

return { A = A, Context = Context, Composer = Composer }
