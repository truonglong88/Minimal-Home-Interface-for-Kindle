-- Run with: luajit spec/model_spec.lua   (from the repository root)
package.path = "minimalhome.koplugin/?.lua;" .. package.path
local Model = require("mh/data/model")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n  " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function titles(list)
    local t = {}
    for i, b in ipairs(list) do t[i] = b.title end
    return table.concat(t, "|")
end

local NOW = os.time({ year = 2026, month = 11, day = 17, hour = 18 })
local DAY = 86400
local function book(t)
    t.status = t.status or (t.last_opened and "reading" or "new")
    return t
end

local function library()
    return {
        book{ title = "Dế Mèn phiêu lưu ký", authors = "Tô Hoài", percent = 0.64, last_opened = NOW - 60, added = NOW - 40 * DAY },
        book{ title = "Số đỏ", authors = "Vũ Trọng Phụng", percent = 0.42, last_opened = NOW - DAY, added = NOW - 50 * DAY },
        book{ title = "Truyện Kiều", authors = "Nguyễn Du", percent = 0.18, last_opened = NOW - 3 * DAY, added = NOW - 90 * DAY },
        book{ title = "Đất rừng phương Nam", authors = "Đoàn Giỏi", percent = 1, status = "complete", last_opened = NOW - 8 * DAY, added = NOW - 70 * DAY },
        book{ title = "Nhà giả kim", authors = "Paulo Coelho", added = NOW - 5 * DAY },
        book{ title = "Atomic Habits", authors = "James Clear", added = NOW - 15 * DAY },
        book{ title = "The Lean Startup", authors = "Eric Ries", percent = 1, status = "complete", last_opened = NOW - 60 * DAY, added = NOW - 200 * DAY },
    }
end

test("reading mode: hero is the last opened book in progress", function()
    local s = Model.homeState(library())
    eq(s.mode, "reading")
    eq(s.hero.title, "Dế Mèn phiêu lưu ký")
    eq(titles(s.recent), "Số đỏ|Truyện Kiều|Đất rừng phương Nam|The Lean Startup")
end)

test("finished mode: next is the most recent book still in progress", function()
    local lib = library()
    lib[1].status, lib[1].percent = "complete", 1
    local s = Model.homeState(lib)
    eq(s.mode, "finished")
    eq(s.just_finished.title, "Dế Mèn phiêu lưu ký")
    eq(s.hero.title, "Số đỏ")
    eq(s.hero_is_new, false)
    eq(titles(s.start_new), "Nhà giả kim|Atomic Habits")
    eq(titles(s.recent), "Dế Mèn phiêu lưu ký|Truyện Kiều|Đất rừng phương Nam|The Lean Startup")
end)

test("finished mode with nothing in progress suggests the newest unread book", function()
    local lib = library()
    for _, b in ipairs(lib) do if b.last_opened then b.status, b.percent = "complete", 1 end end
    local s = Model.homeState(lib)
    eq(s.mode, "finished")
    eq(s.hero.title, "Nhà giả kim")
    eq(s.hero_is_new, true)
    eq(titles(s.start_new), "Atomic Habits")
end)

test("a new library with nothing opened starts with the newest book", function()
    local s = Model.homeState({ book{ title = "A", added = 1 }, book{ title = "B", added = 2 } })
    eq(s.mode, "start")
    eq(s.hero.title, "B")
    eq(#s.recent, 0)
end)

test("empty library", function()
    eq(Model.homeState({}).mode, "empty")
end)

test("title sort puts Đ right after D and ignores tone marks", function()
    local list = Model.sortBooks({
        book{ title = "Đất rừng" }, book{ title = "Dế Mèn" }, book{ title = "Em" }, book{ title = "Cho tôi" },
    }, "title", true)
    eq(titles(list), "Cho tôi|Dế Mèn|Đất rừng|Em")
    eq(titles(Model.sortBooks(list, "title", false)), "Em|Đất rừng|Dế Mèn|Cho tôi")
end)

test("English leading articles are ignored", function()
    local list = Model.sortBooks({ book{ title = "The Lean Startup" }, book{ title = "Atomic Habits" }, book{ title = "Sapiens" } }, "title", true)
    eq(titles(list), "Atomic Habits|The Lean Startup|Sapiens")
end)

test("recent sort lists opened books first, then unread by date added", function()
    local list = Model.sortBooks(library(), "recent", true)
    eq(list[1].title, "Dế Mèn phiêu lưu ký")
    eq(list[5].title, "The Lean Startup")
    eq(list[6].title, "Nhà giả kim")
end)

test("author sort", function()
    local list = Model.sortBooks(library(), "author", true)
    eq(list[1].authors, "Đoàn Giỏi")   -- "Đ" sorts as "d…" before E
    eq(list[#list].authors, "Vũ Trọng Phụng")
end)

test("sort labels", function()
    eq(Model.sortLabel("recent", true), "Recently opened")
    eq(Model.sortLabel("recent", false), "Recently opened · Oldest first")
    eq(Model.sortLabel("title", true), "Title · A → Z")
end)

test("when labels", function()
    eq(Model.whenLabel({ last_opened = NOW - 60 }, NOW), "Today")
    eq(Model.whenLabel({ last_opened = NOW - DAY }, NOW), "Yesterday")
    eq(Model.whenLabel({ last_opened = NOW - 3 * DAY }, NOW), "3 days ago")
    eq(Model.whenLabel({ last_opened = NOW - 8 * DAY }, NOW), "Last week")
    eq(Model.whenLabel({ last_opened = NOW - 15 * DAY }, NOW), "2 weeks ago")
    eq(Model.whenLabel({ last_opened = os.time({ year = 2026, month = 9, day = 2, hour = 12 }) }, NOW), "September")
    eq(Model.whenLabel({ added = os.time({ year = 2026, month = 11, day = 12, hour = 12 }) }, NOW), "Added Nov 12")
end)

test("status and meta lines", function()
    eq(Model.shortStatus({ status = "reading", last_opened = 1, percent = 0.416 }), "42%")
    eq(Model.shortStatus({ status = "complete", last_opened = 1 }), "Finished")
    eq(Model.shortStatus({ status = "new" }), "")
    eq(Model.metaLine({ format = "EPUB", pages = 236 }), "EPUB · 236 pages")
    eq(Model.metaLine({ format = "PDF" }), "PDF")
end)

test("Vietnamese upper-case", function()
    eq(Model.upper("Vũ Trọng Phụng"), "VŨ TRỌNG PHỤNG")
    eq(Model.upper("đoàn giỏi"), "ĐOÀN GIỎI")
end)

test("reading time labels", function()
    eq(Model.duration(20), "less than a minute")
    eq(Model.duration(8 * 60), "8 min")
    eq(Model.duration(135 * 60), "2 h 15 min")
    eq(Model.duration(180 * 60), "3 h")
    eq(Model.timeLeftLabel(8 * 60, "chapter"), "8 min left in chapter")
    eq(Model.timeLeftLabel(nil, "book"), nil)
end)

test("time left for the hero", function()
    eq(Model.bookTimeLeft({ pages = 148, percent = 0.64 }, 90), "1 h 20 min left")
    eq(Model.bookTimeLeft({ pages = 148, percent = 0.64 }, nil), nil)
    eq(Model.bookTimeLeft({ pages = 0, percent = 0.5 }, 60), nil)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
