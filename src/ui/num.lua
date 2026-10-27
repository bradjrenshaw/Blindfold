-- ui/num.lua — game numbers that may be "big". Talisman / Amulet (Steamodded
-- mods for scores past 1e308) replace scores, chips, mult, blind sizes and
-- more with big-number objects: tables in Talisman, FFI cdata in Amulet's
-- OmegaNum mode. Both register is_big(x), and both teach the game's own
-- number_format to render them — so format through it, exactly as the HUD
-- does. Without those mods is_big doesn't exist and this is plain numbers.
local M = {}

function M.is_big(x)
    if type(x) == "number" or x == nil then return false end
    local f = rawget(_G, "is_big")
    if type(f) ~= "function" then return false end
    local ok, r = pcall(f, x)
    return ok and r and true or false
end

-- A number of either kind.
function M.is(x)
    return type(x) == "number" or M.is_big(x)
end

-- A plain Lua number for comparisons and arithmetic (a big beyond the double
-- range comes back as +-inf). nil when x isn't a number of either kind.
function M.to_n(x)
    if type(x) == "number" then return x end
    if not M.is_big(x) then return nil end
    local f = rawget(_G, "to_number")
    if type(f) == "function" then
        local ok, n = pcall(f, x)
        if ok and type(n) == "number" then return n end
    end
    local n = tonumber(tostring(x))
    return n
end

-- Render like the HUD: the game's number_format (commas, scientific past
-- 1e11, "naneinf"; with Talisman/Amulet loaded, their notation for bigs).
-- Non-numbers pass through unchanged.
function M.fmt(x)
    if not M.is(x) then return x end
    local ok, s = pcall(number_format, x)
    if ok and s ~= nil then return tostring(s) end
    return tostring(x)
end

return M
