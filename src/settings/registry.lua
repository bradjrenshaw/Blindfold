-- settings/registry.lua — the mod's settings data layer (lightweight port of
-- SayTheSpire2's ModSettings). Typed settings with defaults + persistence to
-- %APPDATA%/Balatro/blindfold_settings.lua. This is the source of truth that
-- the settings menu renders and the rest of the mod reads from.
local require = ...

local M = { list = {}, by_key = {}, values = {}, _loaded = false }

local FILE = "blindfold_settings.lua"

-- opts: { key, type ('bool'|'choice'|'number'), label_key, default, options?,
--         labels?, label_values?, min?, max?, apply? } — labels are LOC KEYS per
-- option; label_values are pre-rendered literal strings (e.g. live format
-- examples) and win over labels. 'number' settings render as a slider over
-- min..max (integers; default 0..100). apply(v) runs on every change, for
-- settings with live side effects (e.g. rebinding the speech backend).
-- Registering an existing key again updates its options/labels in place
-- (dynamic lists such as voices) and keeps the saved value.
function M.register(opts)
    local s = M.by_key[opts.key]
    if s then
        s.options, s.labels, s.label_values = opts.options, opts.labels, opts.label_values
        s.min, s.max, s.apply = opts.min, opts.max, opts.apply or s.apply
        return s
    end
    s = {
        key = opts.key, type = opts.type, label_key = opts.label_key,
        default = opts.default, options = opts.options, labels = opts.labels,
        label_values = opts.label_values, min = opts.min, max = opts.max,
        category = opts.category, apply = opts.apply,
    }
    M.list[#M.list + 1] = s
    M.by_key[s.key] = s
    if M.values[s.key] == nil then M.values[s.key] = opts.default end
    return s
end

function M.value(key)
    local v = M.values[key]
    if v ~= nil then return v end
    local s = M.by_key[key]
    return s and s.default
end

function M.on_change(key, v)
    M.values[key] = v
    M.save()
    local s = M.by_key[key]
    if s and s.apply then pcall(s.apply, v) end
end

-- For a choice setting, the 1-based index of its current value (for the cycle).
function M.choice_index(s)
    local cur = M.values[s.key]
    for i, opt in ipairs(s.options or {}) do
        if opt == cur then return i end
    end
    return 1
end

local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        local vs
        if type(v) == "string" then vs = string.format("%q", v)
        elseif type(v) == "boolean" or type(v) == "number" then vs = tostring(v) end
        if vs then parts[#parts + 1] = string.format("[%q]=%s", k, vs) end
    end
    return "return {" .. table.concat(parts, ",") .. "}"
end

function M.save()
    pcall(function() love.filesystem.write(FILE, serialize(M.values)) end)
end

-- Overlay any saved values onto the registered defaults. Call after registering.
function M.load()
    if M._loaded then return end
    M._loaded = true
    pcall(function()
        local data = love.filesystem.read(FILE)
        if not data then return end
        local chunk = load(data, "@" .. FILE)
        local t = chunk and chunk()
        if type(t) == "table" then
            for k, v in pairs(t) do M.values[k] = v end
        end
    end)
end

return M
