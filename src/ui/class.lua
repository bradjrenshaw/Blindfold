-- ui/class.lua — minimal single-inheritance class helper.
-- Method lookup walks subclass -> base -> ... via each class table's metatable.
local require = ...

return function(base)
    local c = {}
    c.__index = c
    if base then setmetatable(c, { __index = base }) end
    return c
end
