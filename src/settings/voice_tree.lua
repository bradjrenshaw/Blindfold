-- settings/voice_tree.lua — tree-view logic over the speech library's menu
-- tree (speech.menu): groups (categories, languages, novelty voices) whose
-- leaves are voices and autos, every group opening with its auto. The voice
-- picker (overlays/voice_picker.lua) shows it as a standard tree view: only
-- the children of expanded groups are listed.
--
-- Pure tables in, pure tables out (tests/voice_tree_test.lua).
local M = {}

-- Something the player can choose: a voice, or a group's auto.
function M.is_leaf(node)
    return node.kind == "voice" or node.kind == "auto"
end

-- The node standing for a voice id (a voice or an auto), or nil.
function M.find(node, voice)
    if not node then return nil end
    if node.voice == voice and M.is_leaf(node) then return node end
    for _, c in ipairs(node.children or {}) do
        local hit = M.find(c, voice)
        if hit then return hit end
    end
    return nil
end

-- Mark every group above `node` expanded, so the node is listed.
function M.expand_to(node, expanded)
    local n = node and node.parent
    while n and n.parent do   -- the root itself is never listed
        expanded[n] = true
        n = n.parent
    end
end

-- The tree view's lines, top to bottom: { { node =, depth = }, ... }. The
-- root's children are depth 1; a group's children follow it only while it is
-- expanded.
function M.visible(root, expanded)
    local out = {}
    local function walk(node, depth)
        for _, c in ipairs(node.children or {}) do
            out[#out + 1] = { node = c, depth = depth }
            if not M.is_leaf(c) and expanded[c] then walk(c, depth + 1) end
        end
    end
    if root then walk(root, 1) end
    return out
end

return M
