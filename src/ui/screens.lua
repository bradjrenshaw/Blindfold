-- ui/screens.lua — derive a logical "screen" from Balatro's state and announce
-- transitions. The game has no Screen abstraction: it's an overlay slot
-- (G.OVERLAY_MENU, modal), a flat run state machine (G.STATE within
-- G.STAGE==RUN), and a coarse stage (main menu). We poll a cheap screen id each
-- frame; on a change we reset the container FocusContext (so row names
-- re-announce on the new screen) and speak the screen's title.
local require = ...
local Message = require("ui.message")
local Settings = require("settings.registry")

local M = { say = nil, containers = nil, _last = nil }

local function enabled()
    local v = Settings.value("announce.screen.enabled")
    if v ~= nil then return v end
    return true
end

-- Collapse the run state machine to a stable screen key. Transient phases
-- (hand played / drawing / new round / using a consumable) fold into PLAYING so
-- they don't churn the screen between turns; pack-opening variants fold to PACK.
local function run_state_key()
    local S, st = G.STATES, G.STATE
    if not S then return nil end
    -- An open pack wins regardless of G.STATE: reloading a mid-pack save can
    -- leave the state at SHOP while the restored pack is on screen.
    if type(G.pack_cards) == "table" and not G.pack_cards.REMOVED then return "PACK" end
    if st == S.SHOP then return "SHOP"
    elseif st == S.BLIND_SELECT then return "BLIND_SELECT"
    elseif st == S.ROUND_EVAL then return "CASH_OUT"
    elseif st == S.GAME_OVER then return "GAME_OVER"
    elseif st == S.TAROT_PACK or st == S.SPECTRAL_PACK or st == S.STANDARD_PACK
        or st == S.BUFFOON_PACK or st == S.PLANET_PACK then return "PACK"
    elseif st == S.SELECTING_HAND or st == S.HAND_PLAYED or st == S.DRAW_TO_HAND
        or st == S.NEW_ROUND or st == S.PLAY_TAROT then return "PLAYING"
    end
    return nil
end

-- Cheap per-frame id. Overlays (modal) win and are identified by their UIBox
-- object, so a different overlay is a different screen. Returns nil for
-- unmapped/transient screens (keep the last real one).
local function screen_id()
    if not G then return nil end
    local ov = G.OVERLAY_MENU
    if type(ov) == "table" then return ov end
    local stages = G.STAGES
    if stages then
        if G.STAGE == stages.RUN then
            local k = run_state_key()
            if k then return "RUN_" .. k end
        elseif G.STAGE == stages.MAIN_MENU then
            return "MAIN_MENU"
        end
    end
    return nil
end

-- Run screens whose own contents already announce them, so the screen title
-- would just duplicate: the play screen is oriented by its card rows (Hand /
-- Jokers / ...), and cash-out by the Cash Out button. These reset the container
-- context on entry but speak no title.
local SILENT = { PLAYING = true, CASH_OUT = true }

-- Title for a changed screen. Returns nil for silent screens. Overlay menus
-- are owned by the menu mirror (which announces the focused control), so only
-- our own TAGGED sub-screens speak a name; game overlays get no scraped title
-- (the old first_text scrape read tab labels as titles and doubled the
-- mirror's announcements).
local function screen_title(id)
    if type(id) == "table" then
        if id.blindfold_title_key then return Message.localized(id.blindfold_title_key) end
        return nil
    elseif id == "MAIN_MENU" then
        return Message.localized("SCREEN.MAIN_MENU")
    elseif type(id) == "string" then
        local key = id:sub(5)                              -- strip "RUN_"
        if SILENT[key] then return nil end
        return Message.localized("SCREEN." .. key)
    end
    return nil
end

-- Poll once per frame (called from BA.focus_tick before the focus pass, so the
-- container reset lands before the new screen's first focus announcement).
function M.tick()
    local id = screen_id()
    if id == nil or id == M._last then return end
    local first = (M._last == nil)
    M._last = id
    if M.containers then pcall(M.containers.reset) end
    if first or not enabled() then return end   -- don't announce the boot baseline
    if M.say then
        local title = screen_title(id)
        local s = title and title:resolve() or ""
        if s ~= "" then M.say(s) end
    end
end

function M.reset() M._last = nil end

return M
