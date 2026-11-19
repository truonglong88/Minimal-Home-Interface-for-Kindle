-- Rough text metrics: average advance per character, by font kind.
local M = {}
local function chars(s) local t = {} for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end return t end
M.chars = chars
function M.advance(face, ch)
    local k = 0.55
    if face.path:find("Literata") then k = 0.52 end
    if face.path:find("SemiBold") or face.path:find("Bold") then k = k * 1.05 end
    if ch:match("^[A-Z]$") then k = k * 1.25 elseif ch == " " then k = 0.28 elseif ch:match("^[il.,'|]$") then k = 0.3 end
    return face.size * k
end
function M.width(face, s)
    local w = 0
    for _, ch in ipairs(chars(s)) do w = w + M.advance(face, ch) end
    return math.ceil(w)
end
function M.truncate(face, s, max_w)
    if not max_w or M.width(face, s) <= max_w then return s end
    local out, w = {}, M.width(face, "…")
    for _, ch in ipairs(chars(s)) do
        w = w + M.advance(face, ch)
        if w > max_w then break end
        out[#out + 1] = ch
    end
    return table.concat(out) .. "…"
end
function M.lineHeight(face) return math.ceil(face.size * 1.25) end
return M
