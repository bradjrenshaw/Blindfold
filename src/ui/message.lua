-- ui/message.lua — composable, resolvable speech text.
-- Port of SayTheSpire2's Message: carries raw or mod-localized text, resolves
-- lazily, composes via `+` and `join`. Game-provided text (already localized)
-- comes in as raw(); the mod's own words (type labels, on/off) use localized().
local require = ...

local Message = {}
Message.__index = Message

-- Resolver for mod-localized keys; set to the localization manager's get().
local resolver
function Message.set_resolver(fn) resolver = fn end

local function new(t) return setmetatable(t, Message) end
local function resolve_one(p)
    if type(p) == "table" and p.resolve then return p:resolve() end
    return tostring(p or "")
end

function Message.raw(text) return new{ kind = "raw", text = text or "" } end
function Message.maybe_raw(text) return text and Message.raw(text) or nil end
function Message.localized(key, vars) return new{ kind = "loc", key = key, vars = vars } end
function Message.join(sep, parts) return new{ kind = "join", sep = sep or ", ", parts = parts or {} } end
Message.empty = new{ kind = "raw", text = "" }

function Message.__add(a, b) return Message.join(" ", { a, b }) end

function Message:resolve()
    if self.kind == "raw" then
        return self.text or ""
    elseif self.kind == "loc" then
        local s = (resolver and resolver(self.key)) or tostring(self.key)
        if self.vars then
            s = s:gsub("{(%w+)}", function(k) return resolve_one(self.vars[k]) end)
        end
        return s
    elseif self.kind == "join" then
        local out = {}
        for _, p in ipairs(self.parts) do
            local r = resolve_one(p)
            if r ~= "" then out[#out + 1] = r end
        end
        return table.concat(out, self.sep)
    end
    return ""
end

return Message
