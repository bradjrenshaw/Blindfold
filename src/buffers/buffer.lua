-- buffers/buffer.lua — a browsable list of strings with a persistent cursor
-- (port of SayTheSpire2's Buffer). A buffer holds the current readout of some
-- collection; the user moves through items with the buffer hotkeys. Subclass-
-- like behavior is provided via an `update` function passed at construction,
-- which refreshes contents from live game state (use :repopulate to keep the
-- cursor position across refreshes).
local require = ...

local Buffer = {}
Buffer.__index = Buffer

-- opts: { enabled?, follow_latest?, update? = function(self) }
function Buffer.new(key, opts)
    opts = opts or {}
    return setmetatable({
        key = key,
        enabled = opts.enabled ~= false,        -- enabled unless explicitly false
        follow_latest = opts.follow_latest or false,
        _update = opts.update,
        contents = {},
        position = 1,
    }, Buffer)
end

function Buffer:add(item)
    if type(item) == "string" and item ~= "" then self.contents[#self.contents + 1] = item end
end

function Buffer:clear() self.contents = {}; self.position = 1 end
function Buffer:is_empty() return #self.contents == 0 end
function Buffer:count() return #self.contents end

function Buffer:current_item()
    if #self.contents == 0 then return nil end
    if self.position > #self.contents then self.position = 1 end
    return self.contents[self.position]
end

function Buffer:update() if self._update then self._update(self) end end

-- First navigation into a freshly-populated buffer lands on item 1 rather than
-- skipping to item 2.
function Buffer:move_to_next()
    local was_empty = #self.contents == 0
    self:update()
    if was_empty then return #self.contents > 0 end
    if self.position + 1 > #self.contents then return false end
    self.position = self.position + 1
    return true
end

function Buffer:move_to_previous()
    local was_empty = #self.contents == 0
    self:update()
    if was_empty then return #self.contents > 0 end
    if self.position - 1 < 1 then return false end
    self.position = self.position - 1
    return true
end

function Buffer:move_to_position(p)
    if p < 1 or p > #self.contents then return false end
    self.position = p
    return true
end

-- Clear + repopulate while preserving the cursor position (for live `update`s).
function Buffer:repopulate(populate)
    local saved = self.position
    self:clear()
    populate()
    if saved > 1 and saved <= #self.contents then self.position = saved end
end

return Buffer
