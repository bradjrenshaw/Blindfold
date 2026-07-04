-- overlays/cashout.lua — the owned end-of-round cash-out screen. One real
-- control (the Cash Out button; Enter collects and heads to the shop) with the
-- money breakdown as browsable read-only lines beneath it — blind reward,
-- remaining hands / discards, per-joker and per-tag income, interest — from
-- the events/cashout.lua accumulator (fed by the add_round_eval_row wrap).
-- The dedicated Cash Out buffer still binds on focus for the drill-down view
-- (joker / tag descriptions ride there, not in the list).
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Cashout = require("events.cashout")

local M = { id = "cashout" }

-- The Cash Out button is NOT inside G.round_eval: the game builds it as a
-- separate ANONYMOUS UIBox (common_events.lua:1069 — anchored via config.major
-- = G.round_eval, assigned to no global) — and G.FUNCS.cash_out never removes
-- that box, it only nils the clicked button's config.button. So old rounds'
-- boxes LINGER in the registry with the same id and a dead button. The current
-- round's box is the one whose config.major is the CURRENT G.round_eval (a
-- fresh object every round); the button must still carry config.button.
local cached_btn = nil

local function button_node()
    if cached_btn and not cached_btn.REMOVED
        and cached_btn.config and cached_btn.config.button then
        return cached_btn
    end
    cached_btn = nil
    if type(G.round_eval) ~= "table" then return nil end
    local boxes = G.I and G.I.UIBOX
    if type(boxes) ~= "table" then return nil end
    for _, box in pairs(boxes) do
        if type(box) == "table" and not box.REMOVED and box.get_UIE_by_ID
            and box.config and box.config.major == G.round_eval then
            local ok, hit = pcall(box.get_UIE_by_ID, box, "cash_out_button")
            if ok and hit and not hit.REMOVED and hit.config and hit.config.button then
                cached_btn = hit
                return hit
            end
        end
    end
    return nil
end

function M:handler()
    if not (G and G.STAGE == G.STAGES.RUN and G.STATES and G.STATE == G.STATES.ROUND_EVAL) then
        cached_btn = nil
        return "inactive"
    end
    if G.OVERLAY_MENU then return "sleeping" end
    -- The button is created LAST: pending until the payout animation has
    -- finished building the breakdown.
    if not button_node() then return "pending" end
    return "active"
end

function M:build(b)
    b:capture_input()

    local btn = button_node()
    if btn then
        b:add_clickable(Id.referenced(btn, "btn:cash_out"),
            function(ctx)
                local proxy = Factory.create(btn)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end,
            function(ctx) btn:click() end)
    end

    for i, row in ipairs(Cashout.rows) do
        b:add_label(Id.structural("row:" .. i), function(ctx)
            local ok, s = pcall(Cashout.summary, row)
            if ok and s then ctx.message:fragment(s) end
        end)
    end

    if btn then b:set_start(Id.structural("btn:cash_out")) end
end

return M
