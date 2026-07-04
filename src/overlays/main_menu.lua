-- overlays/main_menu.lua — bespoke owned main menu. The generic flat list was
-- MORE confusing here (Brad): the title screen's spatial layout is its mental
-- model, so this rebuilds it as explicit rows:
--   row 1: the big title card (clickable)
--   row 2: Play, Options, Quit, Collection
--   row 3: Profile, Discord, Twitter, Language (whichever exist)
-- Control discovery and per-control behavior come from the menu mirror
-- (gather / vtable_for); only the layout is bespoke. Unrecognized controls
-- land in a trailing row so nothing the walk finds is ever unreachable.
local require = ...
local Id = require("overlay.id")
local Mirror = require("overlays.menu_mirror")

local M = { id = "main_menu" }

function M:handler()
    if G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU
        and type(G.MAIN_MENU_UI) == "table"
        and G.MAIN_MENU_UI.states and G.MAIN_MENU_UI.states.visible ~= false then
        return "active"
    end
    return "inactive"
end

-- Slot classification: config.button (or id) -> named slot.
local BUTTON_SLOTS = {
    setup_run = "play", start_run = "play",
    options = "options", quit = "quit", your_collection = "collection",
    go_to_discord = "discord", go_to_twitter = "twitter",
    language_selection = "language",
}

local function slot_for(n)
    local c = n.config
    if not c then return nil end
    if c.button and BUTTON_SLOTS[c.button] then return BUTTON_SLOTS[c.button] end
    if c.id == "main_menu_play" then return "play" end
    if c.id == "collection_button" then return "collection" end
    return nil
end

function M:build(b)
    b:capture_input()

    local slots, cards, misc = {}, {}, {}
    for _, n in ipairs(Mirror.gather({ G.MAIN_MENU_UI, G.PROFILE_BUTTON, G.title_top })) do
        if n.is and Card and n:is(Card) then
            cards[#cards + 1] = n
        else
            local key = slot_for(n)
            if not key and n.UIBox and n.UIBox == G.PROFILE_BUTTON then key = "profile" end
            if key and not slots[key] then slots[key] = n else misc[#misc + 1] = n end
        end
    end

    local function id_for(n, key)
        if n.is and Card and n:is(Card) then
            return Id.for_object(n)
        end
        return Id.referenced(n, key or n)
    end

    local function row(entries)
        local any = false
        for _, e in ipairs(entries) do
            if e.node then any = true; break end
        end
        if not any then return end
        b:start_row()
        for _, e in ipairs(entries) do
            if e.node then b:add_item(id_for(e.node, e.key), Mirror.vtable_for(e.node)) end
        end
        b:end_row()
    end

    if cards[1] then
        local entries = {}
        for _, c in ipairs(cards) do entries[#entries + 1] = { node = c } end
        row(entries)
    end
    row({
        { node = slots.play, key = "play" },
        { node = slots.options, key = "options" },
        { node = slots.quit, key = "quit" },
        { node = slots.collection, key = "collection" },
    })
    row({
        { node = slots.profile, key = "profile" },
        { node = slots.discord, key = "discord" },
        { node = slots.twitter, key = "twitter" },
        { node = slots.language, key = "language" },
    })
    if misc[1] then
        local entries = {}
        for _, n in ipairs(misc) do entries[#entries + 1] = { node = n } end
        row(entries)
    end

    if slots.play then b:set_start(Id.referenced(slots.play, "play")) end
end

return M
