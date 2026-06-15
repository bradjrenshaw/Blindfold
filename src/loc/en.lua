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
    },
    STATUS = { ON = "on", OFF = "off" },
    LABELS = { LOCKED = "locked" },
    POSITION = { OF = "{index} of {total}" },

    -- Playing cards and their modifiers.
    CARD = {
        PLAYING   = "{rank} of {suit}",
        DEBUFFED  = "debuffed",
        FACE_DOWN = "face down",
    },
    EDITION = {
        foil = "foil", holographic = "holographic",
        polychrome = "polychrome", negative = "negative",
    },
    SEAL = { GOLD = "gold seal", RED = "red seal", BLUE = "blue seal", PURPLE = "purple seal" },
}
