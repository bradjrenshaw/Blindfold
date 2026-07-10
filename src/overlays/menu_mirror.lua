-- overlays/menu_mirror.lua — the generic owned overlay for the game's native
-- menus. Instead of hand-writing an overlay per menu, it wraps a live UIBox
-- (the main menu's, or whatever G.OVERLAY_MENU holds) and re-presents its
-- interactive controls as ONE FLAT VERTICAL LIST in tree (reading) order —
-- per Brad: no mixed rows-and-singles geometry, up/down is the only movement.
--
-- Labels come from the existing proxy layer (which already reads every native
-- control type: buttons, toggles, tabs, cycles incl. deck/stake, sliders, text
-- inputs), so all of its coverage work applies unchanged. Acting goes through
-- the nodes' own machinery:
--   Enter       -> UIElement:click() (self-contained: FUNCS dispatch, choice
--                  groups, one_press, back-button stack handling — ui.lua:965)
--   left/right  -> value adjust on sliders (G.FUNCS.slider_descreet, the same
--                  call the engine's dpad path makes), cycles (click the arrow
--                  children), and tab strips (click the prev/next choice)
--   [ / ]       -> not handled here: they fall through to the engine's
--                  shoulder handling, which resolves tabs via the overlay's
--                  own tab_shoulders id — no native focus needed
--
-- CardAreas embedded in a menu (deck view, collection) are inlined: their
-- cards become list items, labeled by the card proxies; the deferred
-- description follow-up comes from core's overlay-result handler as usual.
--
-- One UIBox = one screen generation: sub_identity is the UIBox object, so a
-- tab switch or sub-screen swap behaves as a fresh open (focus to the first
-- control). Node identity within a generation is positional (structural key =
-- list index) + the UIElement ref for tier-1 recovery.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy

-- The engine's dynamic focusability gates (Controller:is_node_focusable,
-- controller.lua:1082): a control must be hoverable and visible. Without these
-- the walk picks up decorative nodes the engine itself would never focus —
-- e.g. button-hint pips, whose focus_args carry only a gamepad button.
-- Deliberately NOT checked: `under_overlay` — it is sampled at DRAW time
-- (node.lua:92) and flip-flops per frame for elements of nested UIBoxes, which
-- churned the settle signature into a permanent "pending" (silent, keys
-- swallowed). Our walk is already scoped to the overlay's own tree, which is
-- the situation that flag exists to approximate.
local function focusable_state(node)
    if node.REMOVED then return false end
    local st = node.states
    if not st then return false end
    if st.visible == false then return false end
    return st.hover and st.hover.can and true or false
end

-- The engine's card rule (controller.lua:1090): face-down cards are only
-- focusable in the hand/jokers. Excludes decorative face-down piles (the
-- run-setup deck preview) while keeping deck-view / collection cards.
local function card_focusable(card)
    if not focusable_state(card) then return false end
    return card.facing == "front" or card.area == G.hand or card.area == G.jokers
end

-- Children iteration that survives what the game does to children tables:
-- remove_group NILS array entries (holes stop ipairs dead, hiding every later
-- sibling), and several funcs attach STRING-KEYED children (children.alert).
-- Numeric keys are visited in order first, then keyed extras.
local function each_child(children, visit)
    local maxn = 0
    for k in pairs(children) do
        if type(k) == "number" and k > maxn then maxn = k end
    end
    for i = 1, maxn do
        if children[i] ~= nil then visit(children[i]) end
    end
    for k, v in pairs(children) do
        if type(k) ~= "number" then visit(v) end
    end
end

-- The game's label-colon-value stat rows (the profile's "Wins : 12", the
-- Continue tab's Round/Ante/Money/Best Hand/Seed): columns whose middle cell
-- is a literal ': ' text node. Pure renders, not controls — invisible to the
-- mirror without this.
local function is_stat_row(node)
    if not (G.UIT and node.UIT == G.UIT.R and type(node.children) == "table") then
        return false
    end
    for _, col in pairs(node.children) do
        if type(col) == "table" and type(col.children) == "table" then
            for _, t in pairs(col.children) do
                if type(t) == "table" and t.config and t.config.text == ": " then
                    return true
                end
            end
        end
    end
    return false
end

-- Depth-first, reading-order collection of interactive nodes. The outermost
-- control wins — no descent inside one (a tab strip's inner choice buttons are
-- reached by adjusting the strip, not as separate items). Embedded objects are
-- entered: CardAreas inline their focusable cards, and nested UIBoxes — how
-- the game embeds ALL tab contents (create_tabs' tab_contents object) and
-- panels like the deck/stake column — are walked through their UIRoot.
local function collect(node, out, depth, seen)
    if type(node) ~= "table" or (depth or 0) > 30 then return end
    if seen[node] then return end
    seen[node] = true
    if node.states and node.states.visible == false then return end

    if Proxy.node_is_control(node) then
        if focusable_state(node) then out[#out + 1] = node end
        return
    end

    -- Progress bars (challenge unlocked/completed counts, collection
    -- progress) are pure renders with their reading inside as text — surface
    -- each as a readable item.
    if node.config and node.config.progress_bar then
        out[#out + 1] = node
        return
    end

    -- Label-colon-value stat rows, same treatment.
    if is_stat_row(node) then
        out[#out + 1] = node
        return
    end

    local obj = node.config and node.config.object
    if obj and obj.is then
        if CardArea and obj:is(CardArea) then
            for _, card in ipairs(obj.cards or {}) do
                if card_focusable(card) then out[#out + 1] = card end
            end
            return
        end
        if UIBox and obj:is(UIBox) then
            local before = #out
            collect(obj.UIRoot, out, (depth or 0) + 1, seen)
            -- A nested box that yielded NO items is a pure information panel
            -- (e.g. the locked Challenges tab's explanation text): surface
            -- its text as one readable item instead of an "empty" screen.
            if #out == before and obj.UIRoot then
                local okt, text = pcall(Proxy.all_text, obj.UIRoot)
                if okt and type(text) == "string" and text ~= "" then
                    out[#out + 1] = obj.UIRoot
                end
            end
            return
        end
    end

    if node.children then
        each_child(node.children, function(ch)
            collect(ch, out, (depth or 0) + 1, seen)
        end)
    end
end

-- Speak a control's current value (after an adjust / toggle), if it has one.
local function speak_value(ctx, node)
    local ok = pcall(function()
        local proxy = Factory.create(node)
        local m = proxy and proxy.get_value_message and proxy:get_value_message()
        if m then ctx.message:fragment(m) end
    end)
    return ok
end

-- Port of the engine's tab handling (controller.lua:1317): find the strip's
-- choice group, click the previous/next chosen neighbor (with wraparound).
local function tab_adjust(node, sign)
    pcall(function()
        local group = node.children[1].children[1].config.group
        local proto = node.UIBox:get_group(nil, group)
        local choices = {}
        for _, v in ipairs(proto) do
            if v.config and v.config.choice and v.config.button then choices[#choices + 1] = v end
        end
        for k, v in ipairs(choices) do
            if v.config.chosen then
                local next_i = k + sign
                if next_i < 1 then next_i = #choices elseif next_i > #choices then next_i = 1 end
                choices[next_i]:click()
                return
            end
        end
    end)
end

-- Spoken names for icon-only buttons (sprite, no text — the proxies would
-- read a bare "button"). Keyed by config.button.
local BUTTON_LABELS = {
    go_to_discord = "MENU.DISCORD",
    go_to_twitter = "MENU.TWITTER",
}

-- The overlay's infotip slot content (a UIBox swapped in by two-stage
-- confirm buttons like Unlock All), or nil.
local function infotip_box()
    local ok, box = pcall(function()
        local slot = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID
            and G.OVERLAY_MENU:get_UIE_by_ID("overlay_menu_infotip")
        return slot and slot.config and slot.config.object or nil
    end)
    return ok and box or nil
end

-- The other two-stage confirm mechanism (Delete/Reset Profile): an invisible
-- "Select again to confirm" line (id warning_text, colour CLEAR) that the
-- first press turns WHITE.
local function warning_node(node)
    local ok, w = pcall(function()
        return node.UIBox and node.UIBox.get_UIE_by_ID
            and node.UIBox:get_UIE_by_ID("warning_text") or nil
    end)
    return ok and w or nil
end

local function warning_visible(w)
    return w and w.config and w.config.colour == G.C.WHITE or false
end

local function vtable_for(node)
    -- Text panels pushed by collect (a controls-free nested box, or a
    -- progress bar): read-only, label = their rendered text, re-read live.
    local pcfg = node.config
    if (pcfg and pcfg.progress_bar) or is_stat_row(node)
        or (node.UIT and G.UIT and node.UIT == G.UIT.ROOT
            and not (pcfg and (pcfg.button or pcfg.focus_args))) then
        return {
            label = function(ctx)
                local parts = {}
                -- A bar's naming label often sits in a SIBLING column of its
                -- row (profile progress: "Collection" | bar "62% (212/340)");
                -- prefix it, but only when the parent row holds no other
                -- control — then its text can only belong to this bar.
                if pcfg and pcfg.progress_bar and node.parent
                    and not Proxy.has_other_control(node.parent, node) then
                    local okp, prefix = pcall(Proxy.static_text, node.parent, node)
                    if okp and type(prefix) == "string" and prefix ~= "" then
                        parts[#parts + 1] = prefix
                    end
                end
                local ok, text = pcall(Proxy.all_text, node)
                if ok and type(text) == "string" and text ~= "" then
                    parts[#parts + 1] = text
                end
                if parts[1] then
                    ctx.message:fragment(Message.raw(table.concat(parts, ", ")))
                end
            end,
        }
    end

    -- Cards (from an inlined CardArea): label + the game's own click (the
    -- title-screen card, collection highlights); description follows via the
    -- deferred path.
    if node.is and Card and node:is(Card) then
        return {
            label = function(ctx)
                local proxy = Factory.create(node)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end,
            on_click = function(ctx)
                pcall(function() node:click() end)
            end,
        }
    end

    local vt = {
        label = function(ctx)
            local proxy = Factory.create(node)
            if not proxy then return end
            local override = node.config and node.config.button and BUTTON_LABELS[node.config.button]
            if override then proxy.override_label = Message.localized(override):resolve() end
            local m = proxy:get_focus_message()
            if m then ctx.message:fragment(m) end
        end,
    }

    local cfg = node.config or {}
    local ftype = cfg.focus_args and cfg.focus_args.type

    -- Enter: the node's own click. Only for genuinely clickable nodes, so
    -- everything else keeps the read-the-label fallback.
    if cfg.button or cfg.button_UIE then
        vt.on_click = function(ctx)
            local tip_before = infotip_box()
            local warn = warning_node(node)
            local warn_before = warning_visible(warn)
            node:click()
            -- A toggle speaks its new state; buttons that swap the screen are
            -- announced by the fresh-open path instead.
            speak_value(ctx, node)
            -- Two-stage confirms must SPEAK their first press, or it reads as
            -- doing nothing: a newly attached overlay infotip (Unlock All's
            -- achievements warning) ...
            local tip_after = infotip_box()
            if tip_after and tip_after ~= tip_before and tip_after.UIRoot then
                local ok, text = pcall(Proxy.all_text, tip_after.UIRoot)
                if ok and type(text) == "string" and text ~= "" then
                    ctx.message:fragment(Message.raw(text))
                end
            end
            -- ... or the warning_text line turning visible (Delete/Reset
            -- Profile's "Select again to confirm").
            if not warn_before and warning_visible(warn) then
                local text = warn.config and warn.config.text
                if type(text) == "string" and text ~= "" then
                    ctx.message:fragment(Message.raw(text))
                end
            end
        end
    end

    -- Left/right: adjust value controls in place (engine dpad semantics).
    if ftype == "slider" then
        vt.on_horizontal_adjust = function(ctx, sign, large)
            pcall(function()
                G.FUNCS.slider_descreet(node.children[1], sign * (large and 0.05 or 0.01))
            end)
            speak_value(ctx, node)
        end
    elseif ftype == "cycle" then
        vt.on_horizontal_adjust = function(ctx, sign)
            pcall(function()
                local arrow = node.children[sign > 0 and 3 or 1]
                if arrow then arrow:click() end
            end)
            speak_value(ctx, node)
        end
    elseif ftype == "tab" then
        vt.on_horizontal_adjust = function(ctx, sign)
            tab_adjust(node, sign)
            speak_value(ctx, node)
        end
    end

    return vt
end

-- Gather the focusable controls from a list of sources, in order: UIBoxes
-- (walked via UIRoot) and/or CardAreas (inlined).
local function gather(sources)
    local nodes, seen = {}, {}
    for _, src in ipairs(sources) do
        if type(src) == "table" then
            if src.is and CardArea and src:is(CardArea) then
                for _, card in ipairs(src.cards or {}) do
                    if card_focusable(card) then nodes[#nodes + 1] = card end
                end
            else
                collect(src.UIRoot or src, nodes, 0, seen)
            end
        end
    end
    return nodes
end

-- Build one mirror instance. get_sources returns a list of roots to walk; the
-- first source is the screen's identity anchor.
local function make(id, get_sources, is_active)
    local M = { id = id }

    -- Menus materialize over several frames (run setup attaches its panels via
    -- per-frame funcs; tab contents swap in), and announcing those transitional
    -- states reads as a stutter of unrelated controls. So the handler reports
    -- "pending" — engaged but quiet, nav keys swallowed — until the collected
    -- control list is IDENTICAL on two consecutive ticks (the screen has
    -- settled), and only then goes active: one clean announcement of the final
    -- start node, ~a frame late. LIVENESS CAP: a screen that never stabilizes
    -- (some element churning per frame) goes active after MAX_PENDING ticks
    -- anyway — pending-forever would mean silence with every key swallowed.
    local MAX_PENDING = 30
    local last_sig = nil
    local pending_ticks = 0
    local forced = false   -- cap fired: stay live through continued churn

    local function signature()
        local ok, sources = pcall(get_sources)
        if not ok or type(sources) ~= "table" then return "none" end
        local nodes = gather(sources)
        local parts = { tostring(sources[1]), tostring(#nodes) }
        for _, n in ipairs(nodes) do parts[#parts + 1] = tostring(n) end
        return table.concat(parts, "|")
    end

    function M:handler()
        local ok, active = pcall(is_active)
        if not (ok and active) then
            last_sig, pending_ticks, forced = nil, 0, false
            return "inactive"
        end
        local ok2, sig = pcall(signature)
        sig = ok2 and sig or "error"
        local changed = sig ~= last_sig
        last_sig = sig
        if not changed then
            -- Settled normally; a later churn burst gets a fresh settle window.
            pending_ticks, forced = 0, false
            return "active"
        end
        if forced then return "active" end
        pending_ticks = pending_ticks + 1
        if pending_ticks >= MAX_PENDING then
            -- Never settled: go live with what we have rather than stay mute.
            forced = true
            pending_ticks = 0
            return "active"
        end
        return "pending"
    end

    -- Screen identity, for the fresh-open (reset to start) behavior. Keyed on
    -- the SCREEN, not the UIBox instance: a tagged screen that rebuilds its
    -- UIBox in place (the keybinds screen does after every rebind) keeps its
    -- identity, so the positional reconcile silently keeps the cursor on the
    -- same row instead of resetting. Untagged game menus fall back to instance
    -- identity — for those, a new UIBox is a new screen.
    function M:sub_identity()
        local ok, sources = pcall(get_sources)
        local src = ok and sources and sources[1]
        if type(src) ~= "table" then return "nil" end
        if src.blindfold_title_key then return "tag:" .. tostring(src.blindfold_title_key) end
        return tostring(src)
    end

    function M:build(b)
        b:capture_input()
        local ok, sources = pcall(get_sources)
        if not ok or type(sources) ~= "table" then return end
        for i, n in ipairs(gather(sources)) do
            b:add_item(Id.referenced(n, "m:" .. i), vtable_for(n))
        end
    end

    return M
end

local M = {}

-- Reused by bespoke overlays (the main menu) that want the mirror's control
-- discovery and per-control behavior but their own layout.
M.gather = gather
M.vtable_for = vtable_for

-- Whatever modal overlay menu is up (options tree, run setup, run info, deck
-- view, our own keybinds/announcements screens, ...).
M.overlay = make("menu",
    function() return { G.OVERLAY_MENU } end,
    function() return type(G.OVERLAY_MENU) == "table" end)

return M
