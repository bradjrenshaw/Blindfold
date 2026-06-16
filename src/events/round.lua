-- events/round.lua — announce when the player plays a hand or discards, each
-- with the hands / discards now remaining. The game decrements those counts via
-- a deferred event (ease_hands_played / ease_discard queue an 'immediate'
-- event), so we can't read the new value synchronously. Instead we queue our own
-- 'immediate' event after it and read the count then, announcing only when it
-- actually changed (so a no-op press stays silent).
local require = ...
local Message = require("ui.message")

local M = { say = nil, settings = nil }

local function speak(text)
    if M.say and type(text) == "string" and text ~= "" then M.say(text) end
end
local function loc(key, vars) return Message.localized(key, vars):resolve() end

local function setting(key, default)
    local s = M.settings
    if s and s.value then
        local v = s.value(key)
        if v ~= nil then return v end
    end
    return default
end

local function current(field)
    local cr = G and G.GAME and G.GAME.current_round
    return cr and cr[field]
end

-- Speak `key` (with {count}) once the game's deferred count-update has run.
-- `field` is the current_round counter that drops by one for this action. The
-- decrement lands a frame or two later via the game's own event, so we poll on a
-- non-blocking event and speak the instant the count changes; if it never does
-- (a no-op press), we give up silently after a bounded number of frames.
local function announce(key, field)
    if not setting("round.actions", true) then return end
    if not (G and G.E_MANAGER and Event) then return end
    local before = current(field)
    if type(before) ~= "number" then return end
    local tries = 0
    G.E_MANAGER:add_event(Event({
        trigger = "immediate", blocking = false, blockable = false,
        func = function()
            tries = tries + 1
            local n = current(field)
            if type(n) ~= "number" then return true end
            -- Speak only on a decrease (the action spent a hand/discard); an
            -- increase, e.g. a joker granting a hand, isn't this announcement.
            if n < before then speak(loc(key, { count = n })); return true end
            -- Otherwise keep polling (return false) until the deferred decrement
            -- lands; give up (return true) after a bounded number of frames.
            return tries >= 30
        end,
    }))
end

function M.on_play()
    announce("ROUND.HAND_PLAYED", "hands_left")
end

-- `hook` discards are blind-forced (not a player action); skip those.
function M.on_discard(hook)
    if hook then return end
    announce("ROUND.DISCARDED", "discards_left")
end

return M
