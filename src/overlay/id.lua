-- overlay/id.lua — two-tier control identity (port of Tanglebeep's ControlId).
--
-- A control id is { key = <structural key>, ref = <backing object or nil> }.
-- The STRUCTURAL KEY is value-equatable (a string like "card:114", or — for
-- for_object — the object itself, where equality collapses to identity); the
-- graph stores nodes and traversal order by it. The REF tier is metadata used
-- during focus reconciliation: it lets focus follow a game object that MOVED
-- (its slot-based key changed), while the structural tier follows a logical
-- control whose backing object was REBUILT (new instance, same identity).
local Id = {}

-- A control identified only by a structural key (no backing object).
function Id.structural(key)
    assert(key ~= nil, "ControlId needs a structural key")
    return { key = key }
end

-- A control with both tiers: a backing object and a structural key.
function Id.referenced(ref, key)
    assert(key ~= nil, "ControlId needs a structural key")
    return { key = key, ref = ref }
end

-- A control identified by a backing object only; the object doubles as the
-- structural key (equality = identity). Use when no better key is available.
function Id.for_object(obj)
    assert(obj ~= nil, "ControlId.for_object needs an object")
    return { key = obj, ref = obj }
end

return Id
