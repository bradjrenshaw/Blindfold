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

local function bubble_text()
    local j = jimbo()
    local bubble = j and j.children and j.children.speech_bubble
    local root = bubble and bubble.UIRoot
    if not root then return nil end
    local ok, text = pcall(Proxy.all_text, root)
    return (ok and type(text) == "string" and text ~= "") and text or nil
end

function M:handler()
    local t = G and G.OVERLAY_TUTORIAL
    if not t then return "inactive" end
    if next_button() then return "active" end
    if t.button_listen then return "inactive" end
    return "pending"
end

-- Each tutorial step is a fresh open (cursor to the Next button).
function M:sub_identity()
    local t = G and G.OVERLAY_TUTORIAL
    return tostring(t and t.step or 0)
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
        b:set_start(Id.structural("btn:next"))
    end
end

return M
