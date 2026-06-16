-- ui/factory.lua — picks the right proxy for a focused node (port of
-- SayTheSpire2's ProxyFactory). Dispatch is by Balatro's UI conventions:
-- focus_args.type for widgets, then toggle button, then plain button, else text.
local require = ...
local P = require("ui.proxies")

local Factory = {}

function Factory.create(node)
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
    if cfg.button == "toggle_button" then return P.Toggle.new(node) end
    if cfg.button then return P.Button.new(node) end

    return P.Text.new(node)
end

return Factory
