-- overlays/game_over.lua — the end-of-run screens (game over AND win: both are
-- overlay menus built around the same run-summary rows). The generic mirror
-- already handled their BUTTONS, but the summary rows are plain text — not
-- focusable controls — so a blind player got "Start New Run" with the entire
-- run recap (best hand, most played hand, cards played, defeated by, seed...)
-- unreachable. This overlay reads the stats LIVE from G.GAME (mirroring
-- create_UIBox_round_scores_row's data sources) as browsable label rows, and
-- reuses the mirror's discovery + behaviors for the real buttons (New Run /
-- Main Menu / Copy Seed / the win screen's endless option).
--
-- Detection is by CONTENT: both end screens (and only they, during a run)
-- carry a 'poker_hand' summary row.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Mirror = require("overlays.menu_mirror")

local M = { id = "game_over" }

local function end_screen()
    local box = G.OVERLAY_MENU
    if type(box) ~= "table" or not box.get_UIE_by_ID then return nil end
    local ok, hit = pcall(box.get_UIE_by_ID, box, "poker_hand")
    return (ok and hit) and box or nil
end

function M:handler()
    if not (G and G.STAGE == G.STAGES.RUN) then return "inactive" end
    return end_screen() and "active" or "inactive"
end

local function loc_str(key)
    local ok, s = pcall(localize, key)
    return (ok and type(s) == "string") and s or nil
end

local function fmt_number(n)
    if n == nil then return nil end
    local ok, s = pcall(number_format, n)
    return ok and tostring(s) or tostring(n)
end

-- One line per summary stat, from the same sources the game's rows read.
local function stat_lines()
    local lines = {}
    local function add(label, value)
        if type(label) == "string" and value ~= nil and tostring(value) ~= "" then
            lines[#lines + 1] = label .. ", " .. tostring(value)
        end
    end
    local rs = (G.GAME and G.GAME.round_scores) or {}

    if rs.hand then add(loc_str("ph_score_hand"), fmt_number(rs.hand.amt)) end

    -- Most played hand (+ its count).
    do
        local handname, amount = loc_str("k_none") or "none", 0
        pcall(function()
            for _, v in pairs(G.GAME.hand_usage) do
                if v.count > amount then handname, amount = v.order, v.count end
            end
        end)
        if amount > 0 then
            local ok, hn = pcall(localize, handname, "poker_hands")
            if ok and type(hn) == "string" then handname = hn end
            handname = handname .. " (" .. amount .. ")"
        end
        add(loc_str("ph_score_poker_hand"), handname)
    end

    for _, key in ipairs({ "cards_played", "cards_discarded", "cards_purchased",
        "times_rerolled", "new_collection" }) do
        if rs[key] then add(loc_str("ph_score_" .. key), fmt_number(rs[key].amt)) end
    end

    add(loc_str("k_ante"), fmt_number(G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante))
    add(loc_str("k_round"), fmt_number(G.GAME and G.GAME.round))
    pcall(function() add(loc_str("k_seed"), G.GAME.pseudorandom.seed) end)

    -- Loss only: which blind ended the run.
    if not (G.GAME and G.GAME.won) then
        pcall(function()
            local cfg = G.GAME.blind.config.blind
            local name = localize({ type = "name_text", key = cfg.key, set = "Blind" })
            if type(name) == "string" then add(loc_str("k_defeated_by"), name) end
        end)
    end
    return lines
end

function M:build(b)
    b:capture_input()
    local box = end_screen()
    if not box then return end

    b:add_label(Id.structural("hdr"), function(ctx)
        local won = G.GAME and G.GAME.won
        ctx.message:fragment(loc_str(won and "ph_you_win" or "ph_game_over")
            or Message.localized("SCREEN.GAME_OVER"))
    end)

    for i, line in ipairs(stat_lines()) do
        b:add_label(Id.structural("stat:" .. i),
            function(ctx) ctx.message:fragment(line) end)
    end

    -- The screen's real buttons, discovered and driven like the mirror does.
    local controls = Mirror.gather({ box })
    if controls[1] then
        b:start_row("buttons")
        for i, n in ipairs(controls) do
            b:add_item(Id.referenced(n, "btn:" .. i), Mirror.vtable_for(n))
        end
        b:end_row()
    end
    -- No set_start: focus opens on the header (the first node), so the recap
    -- reads top-to-bottom by arrowing down — skippable straight to the
    -- buttons for players who don't care.
end

return M
