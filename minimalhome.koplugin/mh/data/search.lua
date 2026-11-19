--[[--
Library search: titles and authors, case- and accent-insensitive
("nha gia kim" finds "Nhà giả kim", "nguyen" finds "Nguyễn" and "Nguyên").

Pure Lua, no KOReader modules, so it is tested on its own.
--]]

local Search = {}

-- Vietnamese (and common Latin) letters with marks → base letter.
local FOLD = {}
local groups = {
    a = "àáảãạăằắẳẵặâầấẩẫậäåā", A = "ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÄÅĀ",
    e = "èéẻẽẹêềếểễệëē", E = "ÈÉẺẼẸÊỀẾỂỄỆËĒ",
    i = "ìíỉĩịïī", I = "ÌÍỈĨỊÏĪ",
    o = "òóỏõọôồốổỗộơờớởỡợöøō", O = "ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÖØŌ",
    u = "ùúủũụưừứửữựüū", U = "ÙÚỦŨỤƯỪỨỬỮỰÜŪ",
    y = "ỳýỷỹỵÿ", Y = "ỲÝỶỸỴŸ",
    d = "đ", D = "Đ",
    c = "ç", C = "Ç", n = "ñ", N = "Ñ",
}
for base, list in pairs(groups) do
    for ch in list:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        FOLD[ch] = base:lower()
    end
end

--- Split a UTF-8 string into characters.
function Search.chars(s)
    local out = {}
    for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

--- One character folded to its plain lower-case form (always one character).
function Search.foldChar(ch)
    local f = FOLD[ch]
    if f then return f end
    if #ch == 1 then return ch:lower() end
    return ch
end

--- Folded text, character by character (same length as Search.chars(s)).
function Search.foldList(s)
    local out = {}
    for i, ch in ipairs(Search.chars(s)) do out[i] = Search.foldChar(ch) end
    return out
end

--- The query as a folded string with spaces collapsed; "" when empty.
function Search.needle(query)
    local q = (query or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return table.concat(Search.foldList(q))
end

--- Where `needle` appears in `text`: pre, hit, post (original spelling), or nil.
function Search.split(text, needle)
    if not text or text == "" or needle == "" then return nil end
    -- compare character by character: folded letters are not all one byte
    local chars, f = Search.chars(text), Search.foldList(text)
    local nchars = Search.chars(needle)
    local n = #nchars
    for i = 1, #f - n + 1 do
        local ok = true
        for j = 1, n do
            if f[i + j - 1] ~= nchars[j] then ok = false break end
        end
        if ok then
            return table.concat(chars, "", 1, i - 1),
                table.concat(chars, "", i, i + n - 1),
                table.concat(chars, "", i + n)
        end
    end
    return nil
end

--- Books whose title or author contains the query, in library order.
--- Each result: { book = b, title = {pre, hit, post} | nil, author = {...} | nil }.
function Search.find(books, query)
    local needle = Search.needle(query)
    local out = {}
    if needle == "" then return out end
    for _, b in ipairs(books or {}) do
        local tp, th, tt = Search.split(b.title, needle)
        local ap, ah, at = Search.split(b.authors, needle)
        if tp or ap then
            out[#out + 1] = {
                book = b,
                title = tp and { tp, th, tt } or nil,
                author = ap and { ap, ah, at } or nil,
            }
        end
    end
    return out
end

--- Recent searches: newest first, no duplicates (case-insensitive), at most `max`.
function Search.remember(list, query, max)
    local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    if q ~= "" then out[1] = q end
    for _, v in ipairs(list or {}) do
        if #out >= (max or 3) then break end
        if Search.needle(v) ~= Search.needle(q) then out[#out + 1] = v end
    end
    return out
end

return Search
