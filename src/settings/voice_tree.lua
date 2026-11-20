-- settings/voice_tree.lua — the voice picker's logic over the speech
-- library's menu tree (speech.menu): a tree of groups (categories, languages,
-- novelty voices) whose leaves are voices and autos, every group opening with
-- its auto. The Voice screen shows one cycle per level along the path to the
-- chosen voice, so no list is longer than one group.
--
-- Pure tables in, pure tables out (tests/voice_tree_test.lua); the screen
-- itself is settings/menu.lua.
local M = {}

-- The node standing for a voice id (a voice or an auto), or nil.
function M.find(node, voice)
    if not node then return nil end
    if node.voice == voice and (node.kind == "voice" or node.kind == "auto") then return node end
    for _, c in ipairs(node.children or {}) do
        local hit = M.find(c, voice)
        if hit then return hit end
    end
    return nil
end

-- What choosing `node` selects: itself when it is a voice or an auto, else
-- the auto that opens it (a group's best voice), descending as needed.
function M.descend(node)
    while node and node.kind ~= "voice" and node.kind ~= "auto" do
        node = node.children and node.children[1]
    end
    return node
end

-- The picker's rows for the chosen voice, top down. Each level is
--   { parent = node, options = { nodes }, index = which option is chosen }
-- The first level lists the root's children; each further level lists the
-- children of the group chosen above it, down to the chosen voice or auto.
-- A voice the tree does not hold (a reader that is not running, a removed
-- voice) gives one level with nothing chosen (index nil).
function M.levels(root, voice)
    if not root then return {} end
    local chosen = M.find(root, voice)
    if not chosen then
        return { { parent = root, options = root.children, index = nil } }
    end
    local path = {}
    local n = chosen
    while n and n.parent do
        table.insert(path, 1, n)
        n = n.parent
    end
    local levels = {}
    for _, node in ipairs(path) do
        local parent = node.parent
        local index
        for i, c in ipairs(parent.children) do
            if c == node then index = i; break end
        end
        levels[#levels + 1] = { parent = parent, options = parent.children, index = index }
    end
    return levels
end

return M
