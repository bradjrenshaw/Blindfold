-- events/round.lua — announce when the player plays a hand or discards, each
-- with the hands / discards now remaining. The game decrements those counts via
-- a deferred event (ease_hands_played / ease_discard queue an 'immediate'
-- event), so we can't read the new value synchronously. Instead we queue our own
-- 'immediate' event after it and read the count then, announcing only when it
-- actually changed (so a no-op press stays silent).
local require = ...
local Message = require("ui.message")
local Factory = require("ui.factory")

local M = { say = nil, settings = nil }

local function card_name(card)
    local ok, name = pcall(function()
        local proxy = Factory.create(card)
        local m = proxy and proxy.get_label and proxy:get_label()
        return m and m:resolve() or nil
    end)
    return (ok and name) or nil
end

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

-- ---- Boss-blind effects that are rendered but otherwise silent ----
-- These are not gated behind round.actions: they're involuntary state
-- changes, and the animation is their only other signal.

-- The Hook's forced discard: name the stolen cards (sighted players watch
-- them fly out). Called from core's wrap BEFORE the game's discard runs,
-- while the victims still sit in G.hand.highlighted; the count announcement
-- above stays skipped for hook discards.
function M.on_hook_discard()
    local highlighted = G and G.hand and G.hand.highlighted
    if type(highlighted) ~= "table" or #highlighted == 0 then return end
    local names = {}
    for _, c in ipairs(highlighted) do
        local n = card_name(c)
        if n and n ~= "" then names[#names + 1] = n end
    end
    if #names == 0 then return end
    speak(loc("ROUND.HOOK_DISCARD", { cards = table.concat(names, ", ") }))
end

-- Crimson Heart moves its debuff to a random joker on every draw (the X
-- visibly jumps). `before` maps card -> its debuff flag prior to the move;
-- only the newly debuffed joker is spoken (the old one recovering is
-- implied).
function M.on_joker_debuffs(before)
    for _, c in ipairs((G and G.jokers and G.jokers.cards) or {}) do
        if c.debuff and before[c] == false then
            local n = card_name(c)
            if n and n ~= "" then speak(loc("ROUND.JOKER_DEBUFFED", { name = n })) end
        end
    end
end

-- The Ox: playing your most-played hand drains the money counter to $0.
function M.on_blind_hand(blind, check)
    if check or not blind then return end
    if blind.name == "The Ox" and blind.triggered then
        speak(loc("ROUND.OX"))
    end
end

-- The Tooth: $1 pulses away per played card as each one juices.
function M.on_blind_played(blind)
    if blind and blind.name == "The Tooth" and blind.triggered then
        local n = (G and G.play and G.play.cards and #G.play.cards) or 0
        if n > 0 then speak(loc("ROUND.TOOTH", { amount = n })) end
    end
end

return M
