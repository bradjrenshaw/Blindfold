-- overlays/tutorial.lua — makes the tutorial's Jimbo steps drivable. The
-- dialogue itself is spoken by core's speech-bubble hook; this overlay owns
-- the steps that end in Jimbo's NEXT button (a native UIBox no owned graph
-- would otherwise reach): a re-readable dialogue label plus the button.
--
-- Steps that instead wait for a real action (G.OVERLAY_TUTORIAL.button_listen
-- — select the blind, play the hand, buy the joker...) report "inactive" so
-- the underlying screen's own overlay drives; those actions advance the
-- tutorial through the engine's listen check (UIElement:click, mirrored by
-- Play.tut_listen for the FUNCS we invoke directly). The beats BETWEEN steps
-- (bubble torn down, next one 0.3s out) report "pending" so the screen below
-- doesn't churn announcements at every step boundary.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local Factory = require("ui.factory")
local Proxy = require("ui.proxies").Proxy
local Mirror = require("overlays.menu_mirror")

local M = { id = "tutorial" }

local function jimbo()
    local t = G and G.OVERLAY_TUTORIAL
    return t and t.Jimbo or nil
end

local function find_clickable(node, depth)
    if type(node) ~= "table" or (depth or 0) > 16 then return nil end
    if node.config and node.config.button then return node end
    for _, ch in ipairs(node.children or {}) do
        local hit = find_clickable(ch, (depth or 0) + 1)
        if hit then return hit end
    end
    return nil
end

local function next_button()
    local j = jimbo()
    local box = j and j.children and j.children.button
    return box and box.UIRoot and find_clickable(box.UIRoot) or nil
end

-- The tutorial's own escape hatch: the "Skip >" button in the top-right of
-- every step (tutorial_info, common_events.lua:2189 — skip_tutorial_section
-- tears the whole tutorial down). Sighted players can click it at any time.
local function find_button(node, name, depth)
    if type(node) ~= "table" or (depth or 0) > 16 then return nil end
    if node.config and node.config.button == name then return node end
    for _, ch in ipairs(node.children or {}) do
        local hit = find_button(ch, name, (depth or 0) + 1)
        if hit then return hit end
    end
    return nil
end

local function skip_button()
    local t = G and G.OVERLAY_TUTORIAL
    return t and t.UIRoot and find_button(t.UIRoot, "skip_tutorial_section") or nil
end

local function bubble_text()
    local j = jimbo()
    local bubble = j and j.children and j.children.speech_bubble
    local root = bubble and bubble.UIRoot
    if not root then return nil end
    local ok, text = pcall(Proxy.ordered_text, root)
    return (ok and type(text) == "string" and text ~= "") and text or nil
end

-- Controls inside the step's highlighted UIBoxes, for steps that have
-- neither a Next button nor an action to listen for: the choice IS the
-- step (Cryptid's intro asks you to pick a gameset from a highlighted panel
-- of buttons plus Confirm). Vanilla never has such a step, so this is empty
-- there; steps with a Next button keep just Next / Skip.
local function highlighted_controls()
    local t = G and G.OVERLAY_TUTORIAL
    local hl = t and t.highlights
    if type(hl) ~= "table" then return {} end
    local sources = {}
    for _, h in ipairs(hl) do
        if type(h) == "table" and h ~= t.Jimbo and h.UIRoot and h.is and UIBox and h:is(UIBox)
            and not (h.states and h.states.visible == false) then
            sources[#sources + 1] = h
        end
    end
    if not sources[1] then return {} end
    local ok, items = pcall(Mirror.gather, sources)
    return ok and items or {}
end

-- LIVENESS CAP on the between-steps "pending" beat: deviating from the
-- tutorial's scripted path (our owned handlers call G.FUNCS directly,
-- bypassing its gating) can strand a step with no Next button and no
-- button_listen — the queued next-step event no-ops on its step guard.
-- Unbounded pending would swallow every key forever (the reported "game
-- locks up"). After ~2s of pending the overlay goes ACTIVE instead, with
-- the Skip button reachable as the way out.
local STALL_CAP = 120
local _pending_ticks = 0
local _stalled = false

function M:handler()
    local t = G and G.OVERLAY_TUTORIAL
    if not t then _pending_ticks, _stalled = 0, false; return "inactive" end
    if next_button() then _pending_ticks, _stalled = 0, false; return "active" end
    if t.button_listen then _pending_ticks, _stalled = 0, false; return "inactive" end
    if t.step_complete and highlighted_controls()[1] then _pending_ticks, _stalled = 0, false; return "active" end
    if _stalled then return "active" end
    _pending_ticks = _pending_ticks + 1
    if _pending_ticks >= STALL_CAP then
        _stalled = true
        return "active"
    end
    return "pending"
end

-- Each tutorial step is a fresh open (cursor to the Next button); entering
-- the stalled state is one too (cursor to Skip).
function M:sub_identity()
    local t = G and G.OVERLAY_TUTORIAL
    return tostring(t and t.step or 0) .. (_stalled and ":stalled" or "")
end

function M:build(b)
    b:capture_input()

    -- The dialogue, re-readable by arrowing up from the button (it was
    -- already spoken once by the bubble hook when the step appeared).
    local text = bubble_text()
    if text then
        b:add_label(Id.structural("dialogue"), function(ctx)
            ctx.message:fragment(Message.raw(text))
        end)
    end

    -- A choice step: the highlighted panel's controls (no Next button).
    local choices = {}
    if not next_button() then choices = highlighted_controls() end
    for i, n in ipairs(choices) do
        b:add_item(Id.referenced(n, "choice:" .. i), Mirror.vtable_for(n))
    end

    local btn = next_button()
    if btn then
        b:add_clickable(Id.referenced(btn, "btn:next"),
            function(ctx)
                local proxy = Factory.create(btn)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end,
            -- UIElement:click runs tut_next (and any listen) natively.
            function(ctx) btn:click() end)
    end

    -- Skip is always present for sighted players; surface it on every step —
    -- and when the tutorial has STALLED it is the only control, the way out.
    local skip = skip_button()
    if skip then
        b:add_clickable(Id.referenced(skip, "btn:skip"),
            function(ctx)
                local proxy = Factory.create(skip)
                local m = proxy and proxy:get_focus_message()
                if m then ctx.message:fragment(m) end
            end,
            function(ctx) skip:click() end)
    end

    if btn then
        b:set_start(Id.structural("btn:next"))
    elseif choices[1] then
        b:set_start(Id.referenced(choices[1], "choice:1"))
    elseif skip then
        b:set_start(Id.structural("btn:skip"))
    end
end

return M
