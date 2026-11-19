local F = {}
local NOW = os.time()
local DAY = 86400
local function b(t) t.path = "/books/" .. t.title .. ".epub"; t.format = t.format or "EPUB"
    t.added = t.added or NOW - 30 * DAY; t.status = t.status or (t.last_opened and "reading" or "new"); return t end
function F.library(mode)
    local list = {
        b{ title = "Dế Mèn phiêu lưu ký", authors = "Tô Hoài", percent = 0.64, pages = 148, last_opened = NOW - 60, has_cover = true },
        b{ title = "Số đỏ", authors = "Vũ Trọng Phụng", percent = 0.42, pages = 236, last_opened = NOW - DAY },
        b{ title = "Cho tôi xin một vé đi tuổi thơ", authors = "Nguyễn Nhật Ánh", percent = 0.25, pages = 208, last_opened = NOW - 2 * DAY, has_cover = true },
        b{ title = "Truyện Kiều", authors = "Nguyễn Du", percent = 0.18, pages = 312, last_opened = NOW - 3 * DAY, format = "PDF" },
        b{ title = "Đất rừng phương Nam", authors = "Đoàn Giỏi", percent = 1, status = "complete", pages = 288, last_opened = NOW - 8 * DAY, has_cover = true },
        b{ title = "Sapiens", authors = "Yuval Noah Harari", percent = 1, status = "complete", pages = 512, last_opened = NOW - 15 * DAY },
        b{ title = "Nhà giả kim", authors = "Paulo Coelho", pages = 228, added = NOW - 5 * DAY, has_cover = true },
        b{ title = "Hoàng tử bé", authors = "Antoine de Saint-Exupéry", percent = 1, status = "complete", pages = 112, last_opened = NOW - 22 * DAY },
        b{ title = "Atomic Habits", authors = "James Clear", pages = 320, added = NOW - 15 * DAY },
        b{ title = "Tắt đèn", authors = "Ngô Tất Tố", percent = 1, status = "complete", pages = 196, last_opened = NOW - 40 * DAY, format = "PDF" },
        b{ title = "The Lean Startup", authors = "Eric Ries", percent = 1, status = "complete", pages = 336, last_opened = NOW - 70 * DAY, format = "PDF" },
        b{ title = "Vang bóng một thời", authors = "Nguyễn Tuân", pages = 180, added = NOW - 63 * DAY },
        b{ title = "Thinking, Fast and Slow", authors = "Daniel Kahneman", percent = 1, status = "complete", pages = 499, last_opened = NOW - 100 * DAY },
        b{ title = "Đắc nhân tâm", authors = "Dale Carnegie", pages = 320, added = NOW - 139 * DAY, format = "AZW3" },
    }
    if mode == "finished" then list[1].status, list[1].percent = "complete", 1 end
    if mode == "start" then for _, x in ipairs(list) do x.last_opened, x.status, x.percent = nil, "new", nil end end
    return list
end
return F
