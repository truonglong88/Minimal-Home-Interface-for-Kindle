local J = {}
local function esc(s) return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
function J.encode(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local o = {} for i, x in ipairs(v) do o[i] = J.encode(x) end return "[" .. table.concat(o, ",") .. "]"
        end
        local o = {} for k, x in pairs(v) do o[#o + 1] = esc(tostring(k)) .. ":" .. J.encode(x) end
        return "{" .. table.concat(o, ",") .. "}"
    elseif t == "string" then return esc(v)
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return tostring(v) end
    return "null"
end
return J
