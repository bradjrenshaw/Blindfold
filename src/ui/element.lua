-- ui/element.lua — base UIElement (port of SayTheSpire2's UIElement).
-- Concrete elements yield announcements; get_focus_message composes them.
local require = ...
local class = require("ui.class")
local announce = require("ui.announce")

local Element = class()

-- Canonical announcement order shared by all elements; an element can yield a
-- subset (the composer just skips missing ones).
Element.type_key = nil
Element.announcement_order = { "label", "type", "status", "extras", "locked", "tooltip", "description", "position" }

function Element:get_label() return nil end
function Element:get_status() return nil end
function Element:get_tooltip() return nil end

-- Abstract: yield this element's announcements. Default is empty.
function Element:get_focus_announcements() return {} end

function Element:get_focus_message()
    return announce.Composer.compose(self, self:get_focus_announcements() or {})
end

return Element
