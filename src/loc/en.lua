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
    -- Joker rarity, announced as a subtype ("common joker").
    RARITY = { COMMON = "common", UNCOMMON = "uncommon", RARE = "rare", LEGENDARY = "legendary" },
    POSITION = { OF = "{index} of {total}" },

    -- Screen / state names (announced on a screen transition).
    SCREEN = {
        PLAYING      = "Playing",
        SHOP         = "Shop",
        BLIND_SELECT = "Blind select",
        CASH_OUT     = "Cash out",
        PACK         = "Booster pack",
        GAME_OVER    = "Game over",
        MAIN_MENU    = "Main menu",
        MENU         = "Menu",
    },

    -- Spoken names for icon-only game buttons (menu mirror).
    MENU = {
        DISCORD = "Discord",
        TWITTER = "Twitter",
    },

    -- Container / region names (announced when focus enters a new card row).
    CONTAINER = {
        HAND        = "Hand",
        JOKERS      = "Jokers",
        CONSUMABLES = "Consumables",
        VOUCHERS    = "Vouchers",
        PACKS       = "Packs",
        DECK        = "Deck",
        PLAYED      = "Played",
        SHOP        = "Shop",
        SHOP_GOODS  = "Vouchers and packs",
        PACK        = "Pack",
    },

    -- Booster-pack opening screen.
    PACK = {
        CHOOSE    = "Choose {choices} of {count}",
        CANT_SKIP = "Cannot skip",
    },

    -- Playing cards and their modifiers.
    CARD = {
        PLAYING    = "{rank} of {suit}",
        DEBUFFED   = "debuffed",
        FACE_DOWN  = "face down",
        SELECTED   = "selected",
        DESELECTED = "deselected",
        TIP        = "{name}, {desc}",   -- keyword hover tip: "Foil, +50 chips"
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
        ROW_START = "Row Start", ROW_END = "Row End",
        SELECT = "Select / Activate", GRAB = "Pick Up / Place",
        BACK = "Back / Deselect",
        PLAY_HAND = "Play Hand", DISCARD = "Discard",
        SELL = "Sell", USE = "Use",
        TAB_LEFT = "Previous Tab", TAB_RIGHT = "Next Tab",
        VIEW_DECK = "View Deck", RIGHT_TRIGGER = "Right Trigger",
        RUN_INFO = "Run Info", DEBUG_DUMP = "Debug: Dump Focus",
        BUFFER_NEXT_ITEM = "Buffer: Next Item", BUFFER_PREV_ITEM = "Buffer: Previous Item",
        BUFFER_NEXT = "Buffer: Next Buffer", BUFFER_PREV = "Buffer: Previous Buffer",
    },

    -- Buffer (review-cursor) readouts.
    BUFFER = {
        GAME = "Game",
        CARD = "Card",
        JOKER = "Joker",
        CONSUMABLE = "Consumable",
        CASHOUT = "Cash out",
        UI = "UI",
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
        NOT_CURRENT = "Not the current blind",
    },

    -- The owned play screen (overlays/play.lua): its button row, card
    -- activation feedback, and the Use / Sell action cells.
    PLAY = {
        PLAY_HAND   = "Play hand",
        DISCARD     = "Discard",
        SORT_RANK   = "Sort by rank",
        SORT_SUIT   = "Sort by suit",
        SORTED_RANK = "Sorted by rank",
        SORTED_SUIT = "Sorted by suit",
        NO_CARDS    = "No cards selected",
        NO_DISCARDS = "No discards remaining",
        CANT_SELECT = "Cannot select",
        PICKED_UP   = "Picked up, {name}",
        PICKUP_CANCELLED = "Cancelled",
        MOVED       = "Moved",
        CANT_MOVE_HERE = "Cannot place here",
        USED        = "Used",
        CANT_USE    = "Cannot use now",
        NEEDS_TARGETS = "Requires selected hand cards",
        SOLD        = "Sold",
        CANT_SELL   = "Cannot sell",
    },

    -- In-round play / discard feedback.
    ROUND = {
        HAND_PLAYED = "Hand played, {count} hands remaining",
        DISCARDED   = "Discarded, {count} discards remaining",
    },

    -- Shop prices (buy cost on shop items; sell value on your cards in the
    -- shop) and the owned shop screen's feedback.
    SHOP = {
        COST = "{cost} dollars",
        FREE = "free",
        SELL = "sell {cost} dollars",
        REROLL = "Reroll, {cost} dollars",
        CANT_AFFORD = "Cannot afford",
        NO_ROOM     = "No room",
        BOUGHT      = "Bought",
        BOUGHT_USED = "Bought and used",
        REDEEMED    = "Redeemed",
        EMPTY       = "empty",
    },

    -- End-of-round cash-out screen. Browsable per-source breakdown lives in the
    -- Cash Out buffer; each joker/tag drills into its description + keyword tips.
    CASHOUT = {
        LABEL         = "Cash out",
        TOTAL         = "{dollars} dollars",
        ROW           = "{label}, {dollars} dollars",      -- jokers / tags (by name)
        BLIND_ROW     = "Blind reward, {dollars} dollars",
        SAVED         = "Saved by Mr. Bones",
        HANDS_ROW     = "Remaining hands, {count}, {dollars} dollars",
        DISCARDS_ROW  = "Remaining discards, {count}, {dollars} dollars",
        INTEREST_ROW  = "Interest, {dollars} dollars, {rate} per 5 dollars up to {max}",
        JOKER         = "Joker",
        TAG           = "Tag",
    },

    -- Spoken hand-scoring sequence.
    SCORING = {
        HAND    = "{name}, {chips} chips, {mult} mult",
        HAND_LEVEL = "{name} upgraded to level {level}, {chips} chips, {mult} mult",
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
        ROUND_ACTIONS   = "Announce plays and discards",
        KEYBINDS        = "Keybindings",
        ANNOUNCEMENTS   = "Announcements",
        PRESS_KEY       = "Press a key or controller button for {action}",
        BOUND           = "{action} bound to {key}",
        CANCELLED       = "Rebinding cancelled",
        ANN_TYPE        = "Announce type",
        ANN_SUBTYPE     = "Announce rarity",
        ANN_SELECTED    = "Announce selected",
        ANN_DESCRIPTION = "Announce descriptions",
        ANN_TOOLTIP     = "Announce tooltips",
        ANN_EXTRAS      = "Announce option info",
        ANN_POSITION    = "Announce position",
        ANN_CONTAINER   = "Announce container",
        ANN_SCREEN      = "Announce screen changes",
    },
}
