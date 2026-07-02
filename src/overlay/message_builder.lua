-- overlay/message_builder.lua — fluent speech accumulator (port of Tanglebeep's
-- MessageBuilder, itself a port of Factorio Access's speech.lua builder).
--
-- The value it carries is the separation discipline: consecutive fragments are
-- joined with a space, and list_item boundaries are joined with a comma. That
-- lets a chain of collaborating callbacks each append its piece without
-- coordinating spacing. Single-use: build() errors if the builder is reused.
--
-- fragment() accepts a plain string or a ui.message Message (anything with a
-- :resolve() method), so overlay code can append localized Messages directly.
local MB = {}
MB.__index = MB

function MB.new()
    return setmetatable({
        parts = {},
        -- "initial" | "list_item" | "fragment" | "fragment_in_list" | "built"
        state = "initial",
        first_list_item = true,
    }, MB)
end

function MB:is_empty() return #self.parts == 0 end

local function check_not_built(self)
    if self.state == "built" then error("attempt to use a MessageBuilder twice", 3) end
end

-- Append a text fragment. Fragments are separated from preceding content by a
-- space; the first fragment of a fresh list item is preceded by a comma. Nil /
-- empty fragments are ignored so optional pieces can be appended blindly.
function MB:fragment(text)
    check_not_built(self)
    if type(text) == "table" and text.resolve then text = text:resolve() end
    if text == nil or text == "" then return self end
    text = tostring(text)

    -- Opening a new list item: a comma between items (never before the first).
    if self.state == "list_item" then
        if not self.first_list_item and #self.parts > 0 then
            self.parts[#self.parts] = self.parts[#self.parts] .. ","
        end
        self.first_list_item = false
    end
    self.state = (self.state == "list_item" or self.state == "fragment_in_list")
        and "fragment_in_list" or "fragment"

    self.parts[#self.parts + 1] = text
    return self
end

-- Mark a list-item boundary; the next fragment starts a new comma-separated
-- item. The optional fragment is appended right after the boundary.
function MB:list_item(text)
    check_not_built(self)
    self.state = "list_item"
    if text ~= nil then self:fragment(text) end
    return self
end

-- Finalize and return the message, or nil if nothing was appended. The builder
-- is single-use after this.
function MB:build()
    check_not_built(self)
    self.state = "built"
    if #self.parts == 0 then return nil end
    return table.concat(self.parts, " ")
end

return MB
