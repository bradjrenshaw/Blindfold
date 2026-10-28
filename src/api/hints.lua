-- api/hints.lua — accessibility hints a mod writes into its own UI
-- definitions (docs/mod-api.md, layer 1). The game ignores unknown config
-- fields, so a mod can carry these with or without Blindfold installed:
--
--   config = { button = "my_btn", blindfold = "Reroll bonus" }      -- label
--   config = { button = "my_btn", blindfold = {
--       label = "Reroll bonus",          -- replaces the guessed label
--       hint  = "Costs 2 dollars",       -- read after it, like a tooltip
--   } }
--   config = { blindfold = { text = "Bonus ready" } }   -- a sprite / icon's text
--   config = { blindfold = { hidden = true } }          -- decorative: skip it
--
-- label / hint / text may be functions (called with the node) for values
-- that change; a failing function is ignored.
local require = ...

local M = {}

local function of(node)
    local c = type(node) == "table" and node.config
    local h = type(c) == "table" and c.blindfold
    if type(h) == "string" or type(h) == "function" then return { label = h } end
    return type(h) == "table" and h or nil
end

local function resolve(v, node)
    if type(v) == "function" then
        local ok, r = pcall(v, node)
        v = ok and r or nil
    end
    if type(v) == "number" then v = tostring(v) end
    return type(v) == "string" and v ~= "" and v or nil
end

function M.label(node) local h = of(node); return h and resolve(h.label, node) end
function M.hint(node) local h = of(node); return h and resolve(h.hint, node) end
function M.text(node) local h = of(node); return h and resolve(h.text, node) end
function M.hidden(node) local h = of(node); return h ~= nil and h.hidden == true end

return M
