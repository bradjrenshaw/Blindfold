-- loc/en.lua — English source strings (the source of truth for the mod's own
-- words). Other languages live alongside as loc/<code>.lua and are sparse:
-- any key they omit falls back to this table at lookup time. Game-provided text
-- (button captions, option values, card names) is already localized and read raw.
local require = ...

return {
    TYPES = {
        BUTTON   = "button",
        SLIDER   = "slider",
        -- Balatro's option cycles are value adjusters; announce them as sliders
        -- to match what players expect.
        CYCLE    = "slider",
        CHECKBOX = "checkbox",
        TAB      = "tab",
        -- Card kinds.
        CARD     = "card",
        JOKER    = "joker",
        TAROT    = "tarot",
        PLANET   = "planet",
        SPECTRAL = "spectral",
        VOUCHER  = "voucher",
        BOOSTER  = "booster pack",
        TEXT_FIELD = "text field",
    },
    STATUS = { ON = "on", OFF = "off" },
    LABELS = { LOCKED = "locked", EMPTY = "empty" },
    POSITION = { OF = "{index} of {total}" },

    -- Playing cards and their modifiers.
    CARD = {
        PLAYING    = "{rank} of {suit}",
        DEBUFFED   = "debuffed",
        FACE_DOWN  = "face down",
        SELECTED   = "selected",
        DESELECTED = "deselected",
    },
    EDITION = {
        foil = "foil", holographic = "holographic",
        polychrome = "polychrome", negative = "negative",
    },
    SEAL = { GOLD = "gold seal", RED = "red seal", BLUE = "blue seal", PURPLE = "purple seal" },

    -- Input action labels (shown in the future rebinding settings menu).
    INPUT = {
        NAV_UP = "Navigate Up", NAV_DOWN = "Navigate Down",
        NAV_LEFT = "Navigate Left", NAV_RIGHT = "Navigate Right",
        SELECT = "Select / Confirm", BACK = "Back / Deselect",
        PLAY_HAND = "Play Hand", DISCARD = "Discard",
        SHOULDER_LEFT = "Sell / Previous Tab", SHOULDER_RIGHT = "Buy / Use / Next Tab",
        VIEW_DECK = "View Deck", RIGHT_TRIGGER = "Right Trigger",
        RUN_INFO = "Run Info", DEBUG_DUMP = "Debug: Dump Focus",
        BUFFER_NEXT_ITEM = "Buffer: Next Item", BUFFER_PREV_ITEM = "Buffer: Previous Item",
        BUFFER_NEXT = "Buffer: Next Buffer", BUFFER_PREV = "Buffer: Previous Buffer",
    },

    -- Buffer (review-cursor) readouts.
    BUFFER = {
        GAME = "Game",
        NONE = "No buffers",
        EMPTY = "{buffer} buffer is empty",
        CURRENT = "{buffer}, {item}",
    },
    GAME = {
        HANDS    = "Hands left, {count}",
        DISCARDS = "Discards left, {count}",
        MONEY    = "Money, {amount} dollars",
        SCORE    = "Score, {score} of {req}",
        BLIND    = "Blind, {name}",
        ANTE     = "Ante, {ante} of 8",
        ROUND    = "Round, {round}",
    },

    -- Blind select screen (Small / Big / Boss choices).
    BLIND = {
        REQUIREMENT = "score at least {amount}",
        REWARD      = "reward {dollars} dollars",
        SKIP        = "skip",
    },

    -- Spoken hand-scoring sequence.
    SCORING = {
        HAND    = "{name}, {chips} chips, {mult} mult",
        CHIPS   = "{amt} chips",
        MULT    = "plus {amt} mult",
        XMULT   = "times {amt} mult",
        DOLLARS = "{amt} dollars",
        DEBUFF  = "{source} debuffed",
        SOURCE  = "{source}, {effect}",
        TOTAL   = "{chips} chips times {mult} mult equals {score}",
        SCORE   = "{score}",
    },

    -- Settings (the Blindfold tab in the game's Options screen).
    SET = {
        SCORING_ENABLED = "Announce scoring",
        HAND_PREVIEW    = "Announce hand while selecting",
        SCORING_DETAIL  = "Scoring detail",
        DETAIL_FULL     = "Full",
        DETAIL_JOKERS   = "Jokers only",
        DETAIL_SUMMARY  = "Summary",
        KEYBINDS        = "Keybindings",
        ANNOUNCEMENTS   = "Announcements",
        PRESS_KEY       = "Press a key for {action}",
        BOUND           = "{action} bound to {key}",
        CANCELLED       = "Rebinding cancelled",
        ANN_TYPE        = "Announce type",
        ANN_SELECTED    = "Announce selected",
        ANN_DESCRIPTION = "Announce descriptions",
        ANN_TOOLTIP     = "Announce tooltips",
        ANN_EXTRAS      = "Announce option info",
    },
}
