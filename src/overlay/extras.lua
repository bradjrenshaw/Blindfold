-- overlay/extras.lua — the "Other controls" row for the bespoke gameplay
-- overlays (play, shop, blind select, packs, cash-out). Those overlays list
-- the controls they know by name; anything a mod adds to the screen (a
-- button in the shop, on the HUD, beside the blinds) would be unreachable.
-- Called at the end of an overlay's build, this scans every visible UIBox for
-- controls the overlay didn't list and appends them as a final row (row label
-- "Other controls"), labelled and activated through the menu mirror.
--
-- Left out: controls the overlay already lists (by backing object); the
-- vanilla buttons the gameplay screens reach through their own keys (play,
-- discard, sort, run info, options, next round, reroll, skip, cash out...);
-- buttons on a card's own UIBox (use / sell / buy, reached with U / S /
-- Enter); and the modal overlay menu, which the menu mirror owns.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Proxy = require("ui.proxies").Proxy

local M = {}

local VANILLA = {
    run_info = true, options = true, deck_info = true,
    play_cards_from_highlighted = true, discard_cards_from_highlighted = true,
    sort_hand_value = true, sort_hand_suit = true,
    toggle_shop = true, reroll_shop = true,
    select_blind = true, skip_blind = true, reroll_boss = true,
    cash_out = true, skip_booster = true,
    use_card = true, sell_card = true, buy_from_shop = true,
}

local function on_card(box)
    local major = box.role and box.role.major
    return major ~= nil and major.is ~= nil and Card ~= nil and major:is(Card)
end

-- Controls on screen the builder hasn't listed, in UIBox registration order.
function M.unlisted(b)
    local Mirror = require("overlays.menu_mirror")
    local known = {}
    local function note(row)
        for _, it in ipairs(row.items or {}) do
            if it.id and it.id.ref then known[it.id.ref] = true end
        end
    end
    for _, row in ipairs(b.rows or {}) do note(row) end
    if b.current_row then note(b.current_row) end

    local out, seen = {}, {}
    for _, box in ipairs((G and G.I and G.I.UIBOX) or {}) do
        if type(box) == "table" and not box.REMOVED and box ~= G.OVERLAY_MENU
            and not (box.states and box.states.visible == false) and not on_card(box) then
            local ok, items = pcall(Mirror.gather, { box })
            for _, n in ipairs(ok and items or {}) do
                local c = n.config or {}
                -- Controls only: the walk also yields readable text panels
                -- (a nested box with no controls — the upcoming blinds'
                -- info), which the screens already read or the Screen
                -- buffer covers.
                if not known[n] and not seen[n] and not (n.is and Card and n:is(Card))
                    and Proxy.node_is_control(n)
                    and not (c.button and VANILLA[c.button]) then
                    seen[n] = true
                    out[#out + 1] = n
                end
            end
        end
    end
    return out
end

-- Append the row (no-op when there's nothing extra). Must run in a menu-mode
-- build with no row open.
function M.append(b)
    local ok, list = pcall(M.unlisted, b)
    if not ok or not list[1] then return end
    local Mirror = require("overlays.menu_mirror")
    b:start_row("extras", function(ctx)
        ctx.message:fragment(Message.localized("CONTAINER.OTHER"))
    end)
    for i, n in ipairs(list) do
        b:add_item(Id.referenced(n, "extra:" .. i), Mirror.vtable_for(n))
    end
    b:end_row()
end

return M
