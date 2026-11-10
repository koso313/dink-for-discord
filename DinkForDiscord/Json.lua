local _, ns = ...

-- Minimal JSON writer for alert payloads. Arrays are tables with [1]; everything else is an object.

local Json = {}
ns.Json = Json

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function str(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(t)
    if next(t) == nil then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

local encode
encode = function(v)
    local kind = type(v)
    if kind == "string" then return str(v)
    elseif kind == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
        return string.format("%.4f", v)
    elseif kind == "boolean" then return v and "true" or "false"
    elseif kind == "table" then
        local out = {}
        if isArray(v) then
            for i = 1, #v do out[i] = encode(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local item = v[k]
            if item == nil then item = v[tonumber(k)] end
            if item ~= nil then out[#out + 1] = str(k) .. ":" .. encode(item) end
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

Json.Encode = encode
