-- ui/factory.lua — picks the right proxy for a focused node (port of
-- SayTheSpire2's ProxyFactory). Dispatch is by Balatro's UI conventions:
-- focus_args.type for widgets, then toggle button, then plain button, else text.
local require = ...
local P = require("ui.proxies")
local Hints = require("api.hints")
local Message = require("ui.message")

local Factory = {}

-- A mod's label / hint written on the node (api/hints) override what we'd
-- guess from its text; read live, so a function label follows its value.
local function apply_hints(proxy, node)
    if not proxy or not (Hints.label(node) or Hints.hint(node)) then return proxy end
    if Hints.label(node) then
        local base = proxy.get_label
        proxy.get_label = function(self)
            local l = Hints.label(node)
            if l then return Message.raw(l) end
            return base(self)
        end
    end
    local base_tip = proxy.get_tooltip
    proxy.get_tooltip = function(self)
        local h = Hints.hint(node)
        local tip = base_tip(self)
        if not h then return tip end
        local t = tip and tip.resolve and tip:resolve()
        return Message.raw(t and t ~= "" and (h .. ". " .. t) or h)
    end
    return proxy
end

local create

function Factory.create(node)
    return apply_hints(create(node), node)
end

function create(node)
    if not node then return nil end

    -- Cards: playing cards (rank/suit identity) vs jokers/consumables (name).
    if node.is and Card and node:is(Card) then
        local base = node.base
        local set = node.ability and node.ability.set
        if (base and base.suit) or set == "Default" or set == "Enhanced" then
            return P.PlayingCard.new(node)
        end
        return P.Joker.new(node)
    end

    local cfg = node.config
    if not cfg then return P.Text.new(node) end

    local ftype = cfg.focus_args and cfg.focus_args.type
    if ftype == "slider" then return P.Slider.new(node) end
    if ftype == "cycle"  then return P.Cycle.new(node) end
    if ftype == "tab"    then return P.Tab.new(node) end

    if cfg.button == "select_text_input" then return P.TextInput.new(node) end
    -- Blind Select buttons: also match by id — the game clears config.button
    -- on non-current panels every frame (they're display-only).
    if cfg.button == "select_blind" or cfg.button == "skip_blind"
        or cfg.id == "select_blind_button" then return P.Blind.new(node) end
    if cfg.button == "cash_out" then return P.CashOut.new(node) end
    if cfg.button == "toggle_button" then return P.Toggle.new(node) end
    if cfg.button then return P.Button.new(node) end

    return P.Text.new(node)
end

return Factory
