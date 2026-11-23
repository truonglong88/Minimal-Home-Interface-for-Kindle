--[[--
Pure library logic: no KOReader dependencies, so it can be unit tested
with plain LuaJIT (see spec/model_spec.lua).

A book is a table:
    path, title, authors, pages,
    percent      -- 0..1, or nil when never opened
    status       -- "new" | "reading" | "complete" | "abandoned"
    last_opened  -- epoch seconds, or nil
    added        -- epoch seconds (file modification time)
--]]

local Model = {}

Model.RECENT_COUNT = 4
Model.START_NEW_COUNT = 2

function Model.isOpened(b)
    return b.last_opened ~= nil or (b.status ~= nil and b.status ~= "new")
end

function Model.isFinished(b)
    return b.status == "complete"
end

--- Opened, not finished, not put on hold.
function Model.isInProgress(b)
    return Model.isOpened(b) and b.status ~= "complete" and b.status ~= "abandoned"
end

local function byLastOpenedDesc(a, b)
    return (a.last_opened or 0) > (b.last_opened or 0)
end

local function byAddedDesc(a, b)
    if (a.added or 0) == (b.added or 0) then return (a.title or "") < (b.title or "") end
    return (a.added or 0) > (b.added or 0)
end

local function filter(list, pred)
    local out = {}
    for _, v in ipairs(list) do
        if pred(v) then out[#out + 1] = v end
    end
    return out
end

local function take(list, n, except)
    local out = {}
    for _, v in ipairs(list) do
        if #out >= n then break end
        if not (except and except[v]) then out[#out + 1] = v end
    end
    return out
end

--[[--
Decide what the top of the home screen shows.

Returns a table:
    mode = "reading"  -> hero = book being read
    mode = "finished" -> just_finished = last book (finished), hero = what to read next,
                         start_new = up to 2 unread books
    mode = "start"    -> nothing opened yet (or nothing in progress), hero = newest unread
    mode = "empty"    -> no books at all
    recent = up to 4 recently opened books, excluding the hero
--]]
function Model.homeState(books)
    local state = { recent = {}, start_new = {} }
    if #books == 0 then
        state.mode = "empty"
        return state
    end

    local opened = filter(books, function(b) return b.last_opened ~= nil end)
    table.sort(opened, byLastOpenedDesc)
    -- Kindle Store files KOReader cannot open are never suggested
    local unread = filter(books, function(b) return not Model.isOpened(b) and not b.kindle_only end)
    table.sort(unread, byAddedDesc)

    local latest = opened[1]
    local hero_is_new = false

    if latest and Model.isFinished(latest) then
        state.mode = "finished"
        state.just_finished = latest
        for _, b in ipairs(opened) do
            if b ~= latest and Model.isInProgress(b) then
                state.hero = b
                break
            end
        end
        if not state.hero then
            state.hero = unread[1]
            hero_is_new = state.hero ~= nil
        end
        local skip = {}
        if state.hero then skip[state.hero] = true end
        state.start_new = take(unread, Model.START_NEW_COUNT, skip)
    elseif latest and Model.isInProgress(latest) then
        state.mode = "reading"
        state.hero = latest
    else
        state.mode = "start"
        state.hero = unread[1] or latest
        hero_is_new = state.hero ~= nil and not Model.isOpened(state.hero)
    end
    state.hero_is_new = hero_is_new

    local skip = {}
    if state.hero then skip[state.hero] = true end
    state.recent = take(opened, Model.RECENT_COUNT, skip)
    return state
end

-- Sorting -----------------------------------------------------------------

-- Vietnamese-aware sort key: compare letters without tone marks first,
-- with "đ" placed right after "d".
local VI_BASE = {}
do
    local groups = {
        a = "àáảãạăằắẳẵặâầấẩẫậ", e = "èéẻẽẹêềếểễệ", i = "ìíỉĩị",
        o = "òóỏõọôồốổỗộơờớởỡợ", u = "ùúủũụưừứửữự", y = "ỳýỷỹỵ",
    }
    for base, chars in pairs(groups) do
        for ch in chars:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            VI_BASE[ch] = base
        end
    end
    VI_BASE["đ"] = "d\127"
end

local UPPER_TO_LOWER = {}
do
    local up = "ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ"
    local lo = "àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ"
    local ups, los = {}, {}
    for ch in up:gmatch("[%z\1-\127\194-\244][\128-\191]*") do ups[#ups + 1] = ch end
    for ch in lo:gmatch("[%z\1-\127\194-\244][\128-\191]*") do los[#los + 1] = ch end
    for i = 1, #ups do UPPER_TO_LOWER[ups[i]] = los[i] end
end

local LOWER_TO_UPPER = {}
for up, lo in pairs(UPPER_TO_LOWER) do LOWER_TO_UPPER[lo] = up end

--- Upper-case that also handles Vietnamese letters (string.upper is ASCII only).
function Model.upper(s)
    local out = {}
    for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        out[#out + 1] = LOWER_TO_UPPER[ch] or ch:upper()
    end
    return table.concat(out)
end

function Model.sortKey(s)
    s = s or ""
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        ch = UPPER_TO_LOWER[ch] or ch:lower()
        out[#out + 1] = VI_BASE[ch] or ch
    end
    -- leading articles are ignored for English titles
    local key = table.concat(out):gsub("^the%s+", ""):gsub("^an?%s+", "")
    return key
end

local function firstAuthor(b)
    local a = b.authors or ""
    return (a:match("^[^\n,;]+")) or a
end

Model.SORTS = {
    { id = "folders", label = "Folders",        dirs = { "A → Z", "Z → A" },
      sub = "Folders first, then single books" },
    { id = "recent", label = "Recently opened", dirs = { "Newest first", "Oldest first" } },
    { id = "added",  label = "Recently added",  dirs = { "Newest first", "Oldest first" } },
    { id = "title",  label = "Title",           dirs = { "A → Z", "Z → A" } },
    { id = "author", label = "Author",          dirs = { "A → Z", "Z → A" } },
}

--- Sort a copy of `books`.
--- @param key "recent"|"added"|"title"|"author"
--- @param asc boolean default direction (newest first / A to Z) when true
function Model.sortBooks(books, key, asc)
    local list = {}
    for i, b in ipairs(books) do list[i] = b end
    local cmp
    if key == "added" then
        cmp = byAddedDesc
    elseif key == "title" then
        cmp = function(a, b)
            local ka, kb = Model.sortKey(a.title), Model.sortKey(b.title)
            if ka == kb then return (a.path or "") < (b.path or "") end
            return ka < kb
        end
    elseif key == "author" then
        cmp = function(a, b)
            local ka, kb = Model.sortKey(firstAuthor(a)), Model.sortKey(firstAuthor(b))
            if ka == kb then return Model.sortKey(a.title) < Model.sortKey(b.title) end
            return ka < kb
        end
    else -- recent: opened books by last opened, then never-opened by date added
        cmp = function(a, b)
            if a.last_opened and b.last_opened then return a.last_opened > b.last_opened end
            if a.last_opened or b.last_opened then return a.last_opened ~= nil end
            return byAddedDesc(a, b)
        end
    end
    table.sort(list, cmp)
    if asc == false then
        local n = #list
        for i = 1, math.floor(n / 2) do list[i], list[n - i + 1] = list[n - i + 1], list[i] end
    end
    return list
end

-- Folders ------------------------------------------------------------------

--- Sort key that puts numbers in number order: "Tập 2" before "Tập 10".
function Model.naturalKey(s)
    return (Model.sortKey(s):gsub("%d+", function(d) return string.format("%012d", tonumber(d) or 0) end))
end

local function byNatural(field)
    return function(a, b)
        local ka, kb = Model.naturalKey(a[field] or ""), Model.naturalKey(b[field] or "")
        if ka == kb then return (a.path or "") < (b.path or "") end
        return ka < kb
    end
end

--- Books inside a folder: being read first (last opened on top), then not read
--- yet (A → Z, numbers in order), then finished (same order).
function Model.folderOrder(books)
    local reading, unread, done = {}, {}, {}
    for _, b in ipairs(books) do
        if Model.isFinished(b) then done[#done + 1] = b
        elseif Model.isInProgress(b) then reading[#reading + 1] = b
        else unread[#unread + 1] = b end
    end
    table.sort(reading, function(a, b) return (a.last_opened or 0) > (b.last_opened or 0) end)
    table.sort(unread, byNatural("title"))
    table.sort(done, byNatural("title"))
    local out = {}
    for _, list in ipairs({ reading, unread, done }) do
        for _, b in ipairs(list) do out[#out + 1] = b end
    end
    return out
end

--- Split `books` under `root`: the folders directly inside it (each with every
--- book below it) and the books that sit in `root` itself.
--- Folders come A → Z (numbers in order); `asc == false` reverses them.
function Model.groupByFolder(books, root, asc)
    root = (root or ""):gsub("/+$", "")
    local folders, by_name, loose = {}, {}, {}
    for _, b in ipairs(books) do
        local path = b.path or ""
        local rel = (root ~= "" and path:sub(1, #root + 1) == root .. "/") and path:sub(#root + 2) or nil
        local first = rel and rel:match("^([^/]+)/")
        if first then
            local f = by_name[first]
            if not f then
                f = { name = first, path = root .. "/" .. first, books = {} }
                by_name[first] = f
                folders[#folders + 1] = f
            end
            f.books[#f.books + 1] = b
        else
            loose[#loose + 1] = b
        end
    end
    table.sort(folders, byNatural("name"))
    table.sort(loose, byNatural("title"))
    if asc == false then
        local function rev(t) local n = #t for i = 1, math.floor(n / 2) do t[i], t[n - i + 1] = t[n - i + 1], t[i] end end
        rev(folders); rev(loose)
    end
    for _, f in ipairs(folders) do
        f.ordered = Model.folderOrder(f.books)
        f.top = f.ordered[1]
    end
    return folders, loose
end

--- "vol. 3" from a title or file name ending in a number, else the title.
function Model.volumeLabel(b)
    local title = b.title or ""
    local n = title:match("(%d+)%D*$") or (b.path or ""):match("(%d+)[^/%d]*$")
    return n and ("vol. " .. tonumber(n)) or title
end

--- Lines for a folder: "12 volumes" and, while one is being read, "Reading vol. 3".
function Model.folderSummary(f)
    local n = #f.books
    local count = n == 1 and "1 volume" or (n .. " volumes")
    local reading
    for _, b in ipairs(f.ordered or Model.folderOrder(f.books)) do
        if Model.isInProgress(b) then reading = b break end
    end
    return count, reading
end

function Model.sortLabel(key, asc)
    for _, s in ipairs(Model.SORTS) do
        if s.id == key then
            local show_dir = key == "title" or key == "author" or key == "folders" or asc == false
            return s.label .. (show_dir and (" · " .. s.dirs[asc == false and 2 or 1]) or "")
        end
    end
    return Model.SORTS[1].label
end

-- Labels ------------------------------------------------------------------

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }
local MONTHS_SHORT = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function dayStart(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

--- "Today", "Yesterday", "3 days ago", "Last week", "2 weeks ago", "October"
--- For books never opened: "Added Nov 12".
function Model.whenLabel(b, now)
    now = now or os.time()
    if not b.last_opened then
        if not b.added then return "" end
        local d = os.date("*t", b.added)
        return string.format("Added %s %d", MONTHS_SHORT[d.month], d.day)
    end
    local days = math.floor((dayStart(now) - dayStart(b.last_opened)) / 86400 + 0.5)
    if days <= 0 then return "Today" end
    if days == 1 then return "Yesterday" end
    if days < 7 then return days .. " days ago" end
    if days < 14 then return "Last week" end
    if days < 28 then return math.floor(days / 7) .. " weeks ago" end
    local d = os.date("*t", b.last_opened)
    local n = os.date("*t", now)
    if d.year == n.year then return MONTHS[d.month] end
    return string.format("%s %d", MONTHS_SHORT[d.month], d.year)
end

function Model.percentInt(b)
    if not b.percent then return 0 end
    return math.floor(b.percent * 100 + 0.5)
end

--- Short status for the Recent row: "42%", "Finished", or "".
function Model.shortStatus(b)
    if Model.isFinished(b) then return "Finished" end
    if Model.isInProgress(b) then return Model.percentInt(b) .. "%" end
    return ""
end

function Model.metaLine(b)
    local parts = {}
    if b.format then parts[#parts + 1] = b.format end
    if b.kindle_only then
        parts[#parts + 1] = "Kindle Store"
        return table.concat(parts, " · ")
    end
    if b.pages and b.pages > 0 then parts[#parts + 1] = b.pages .. " pages" end
    return table.concat(parts, " · ")
end

--- Reading time: "less than a minute", "8 min", "2 h 15 min", "3 h".
function Model.duration(seconds)
    if not seconds or seconds ~= seconds then return nil end
    local mins = math.floor(seconds / 60 + 0.5)
    if mins < 1 then return "less than a minute" end
    if mins < 60 then return mins .. " min" end
    local h, m = math.floor(mins / 60), mins % 60
    if m == 0 then return h .. " h" end
    return h .. " h " .. m .. " min"
end

--- Footer text for the time left, or nil when it can't be estimated yet.
function Model.timeLeftLabel(seconds, scope)
    local d = Model.duration(seconds)
    if not d then return nil end
    return d .. " left in " .. scope
end

--- "1 h 20 min left" for the hero, from seconds per page.
function Model.bookTimeLeft(b, seconds_per_page)
    if not seconds_per_page or not b.pages or b.pages <= 0 or not b.percent then return nil end
    local left_pages = math.max(0, b.pages - math.floor(b.percent * b.pages + 0.5))
    local d = Model.duration(left_pages * seconds_per_page)
    if not d then return nil end
    return d .. " left"
end

return Model
