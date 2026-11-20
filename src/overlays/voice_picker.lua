-- overlays/voice_picker.lua — the voice picker: a standard tree view over the
-- speech library's menu tree (categories, then languages, then voices, with
-- novelty voices in a group of their own). Opened from the Voice screen's
-- Voice button (settings/menu.lua), which owns the game-side UIBox; this
-- overlay owns the keys while that screen is up.
--
--   Up / Down   previous / next line (Home / End: first / last)
--   Right       on a closed group: open it; on an open group: its first line
--   Left        on an open group: close it; otherwise: the enclosing group
--   Enter       on a voice or an auto: choose it and return to the Voice
--               screen; on a group: open or close it
--   Back        return without changing anything (the screen's own Back)
--
-- Lines read "<name>", groups add "collapsed" / "expanded", the current
-- choice adds "selected"; moving up or down across a level boundary says
-- the new level first.
local require = ...
local Id = require("overlay.id")
local Message = require("ui.message")
local VoiceTree = require("settings.voice_tree")
local Dispatcher = require("overlay.dispatcher")

local M = { id = "voice_picker", TITLE = "SET.VOICE_PICK" }

-- Set by open(): { root, expanded = { [node] = true }, chosen = <hex voice>,
-- label_of = fn(node) -> string, on_pick = fn(voice), view = { text = } }.
-- `view.text` mirrors the focused line for the screen's text node.
M.state = nil

-- Start a picking session over `root` (speech.menu), opened down to the
-- current choice. Returns the table the screen binds its text to.
function M.open(root, chosen, label_of, on_pick)
    local st = { root = root, expanded = {}, chosen = chosen,
        label_of = label_of, on_pick = on_pick, view = { text = "" } }
    local cur = VoiceTree.find(root, chosen)
    if cur then
        VoiceTree.expand_to(cur, st.expanded)
        st.view.text = label_of(cur)
    end
    M.state = st
    return st.view
end

function M:handler()
    local ov = G and G.OVERLAY_MENU
    if M.state and type(ov) == "table" and ov.blindfold_title_key == M.TITLE then
        return "active"
    end
    return "inactive"
end

-- A fresh open lands on the current choice again.
function M:sub_identity()
    return tostring(G.OVERLAY_MENU)
end

local function id_of(node)
    return Id.structural("vt:" .. tostring(node.id))
end

local function state_word(st, node)
    return Message.localized(st.expanded[node] and "SET.TREE_EXPANDED" or "SET.TREE_COLLAPSED")
end

function M:build(b)
    local st = M.state
    local lines = VoiceTree.visible(st.root, st.expanded)
    if #lines == 0 then return end   -- nothing to pick from: the mirror reads the screen
    b:capture_input()
    for _, line in ipairs(lines) do
        local node = line.node
        local leaf = VoiceTree.is_leaf(node)
        local vt = {
            label = function(ctx)
                local text = st.label_of(node)
                st.view.text = text
                ctx.message:list_item(Message.raw(text))
                if not leaf then
                    ctx.message:list_item(state_word(st, node))
                elseif node.voice == st.chosen then
                    ctx.message:list_item(Message.localized("CARD.SELECTED"))
                end
            end,
        }
        if leaf then
            vt.on_click = function() st.on_pick(node.voice) end
        else
            local function toggle(ctx)
                st.expanded[node] = not st.expanded[node] or nil
                ctx.message:fragment(state_word(st, node))
            end
            vt.on_click = toggle
            -- Groups take left/right themselves: open/close in place, or step
            -- to the first line inside / the enclosing group (announced by
            -- the next frame's focus change).
            vt.on_horizontal_adjust = function(ctx, sign, large)
                if large then
                    -- Home / End arrive here too (a slider's coarse step):
                    -- on a group they still mean the first / last line.
                    ctx.controller:suggest_move(id_of(lines[sign > 0 and #lines or 1].node))
                elseif sign > 0 and not st.expanded[node] then
                    toggle(ctx)
                elseif sign > 0 then
                    if node.children[1] then ctx.controller:suggest_move(id_of(node.children[1])) end
                elseif st.expanded[node] then
                    toggle(ctx)
                elseif node.parent and node.parent.parent then
                    ctx.controller:suggest_move(id_of(node.parent))
                end
            end
        end
        b:add_node(id_of(node), vt)
    end
    for i, line in ipairs(lines) do
        local node, below = line.node, lines[i + 1]
        if below then
            -- Crossing into another level says which, before the line itself.
            local function level(depth)
                return function(ctx)
                    ctx.message:list_item(Message.localized("SET.TREE_LEVEL", { n = depth }))
                end
            end
            local differs = below.depth ~= line.depth
            b:connect(id_of(node), "down", id_of(below.node), differs and level(below.depth) or nil)
            b:connect(id_of(below.node), "up", id_of(node), differs and level(line.depth) or nil)
        end
        -- Left from a voice or an auto: the group it is in.
        if VoiceTree.is_leaf(node) and node.parent and node.parent.parent then
            b:connect(id_of(node), "left", id_of(node.parent))
        end
    end
    -- A fresh open (no cursor yet) lands on the current choice, which is
    -- listed: open() expanded the groups above it. After that the start is
    -- the first line again, so Home and the traversal order cover the lines
    -- above the choice too.
    local entry = Dispatcher.cache[M.id]
    if not (entry and entry.state.cur) then
        local cur = VoiceTree.find(st.root, st.chosen)
        for _, line in ipairs(lines) do
            if line.node == cur then b:set_start(id_of(cur)); break end
        end
    end
end

return M
