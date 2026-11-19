-- Library search: accent- and case-insensitive matching on titles and authors.
-- Usage: luajit spec/search_spec.lua
package.path = "minimalhome.koplugin/?.lua;" .. package.path
local S = require("mh/data/search")
local books = {
    { title = "Nhà giả kim", authors = "Paulo Coelho" },
    { title = "Ông già và biển cả", authors = "Ernest Hemingway" },
    { title = "Mắt biếc", authors = "Nguyễn Nhật Ánh" },
    { title = "Bỉ vỏ", authors = "Nguyên Hồng" },
    { title = "Đất rừng phương Nam", authors = "Đoàn Giỏi" },
    { title = "Sapiens" },
}
local function titles(r) local t = {} for i, x in ipairs(r) do t[i] = x.book.title end return table.concat(t, "|") end
assert(titles(S.find(books, "gia")) == "Nhà giả kim|Ông già và biển cả", titles(S.find(books, "gia")))
assert(titles(S.find(books, "NGUYEN")) == "Mắt biếc|Bỉ vỏ", "author match, accents and case ignored")
assert(titles(S.find(books, "dat rung")) == "Đất rừng phương Nam", "đ folds to d, spaces kept")
assert(titles(S.find(books, "  nhà   giả ")) == "Nhà giả kim", "extra spaces ignored")
assert(#S.find(books, "harry potter") == 0 and #S.find(books, "") == 0, "no match / empty")
local r = S.find(books, "gia")[1]
assert(r.title[1] == "Nhà " and r.title[2] == "giả" and r.title[3] == " kim", "hit keeps the original spelling")
local a = S.find(books, "gio")[1]
assert(a.title == nil and a.author[1] == "Đoàn " and a.author[2] == "Giỏ" and a.author[3] == "i", "author hit")
local rec = S.remember({ "sapiens", "Nguyễn" }, "nguyen", 3)
assert(table.concat(rec, "|") == "nguyen|sapiens", "recent: newest first, no duplicates: " .. table.concat(rec, "|"))
assert(#S.remember({ "a", "b", "c" }, "d", 3) == 3, "at most 3")
print("search OK")
