-- Which files on a Kindle count as books.
-- Usage: luajit spec/library_spec.lua /path/to/koreader
local KO = arg[1] or error("pass the path to a KOReader checkout")
package.path = table.concat({ "spec/stubs/?.lua", "minimalhome.koplugin/?.lua", KO .. "/frontend/?.lua", package.path }, ";")
require("stubs_env")

-- a typical jailbroken Kindle, as an in-memory tree
local tree = {
    ["/mnt/us"] = { "documents", "koreader", "extensions", "screensaver", "books", "linkss", ".active_content_sandbox", "notes.pdf" },
    ["/mnt/us/documents"] = { "My Clippings.txt", "Dune.azw3", "Dune.sdr", "dictionaries", "cover.jpg", "Sapiens.epub" },
    ["/mnt/us/documents/dictionaries"] = { "Oxford.azw" },
    ["/mnt/us/documents/Dune.sdr"] = { "metadata.azw3.lua" },
    ["/mnt/us/koreader"] = { "help", "resources", "fonts" },
    ["/mnt/us/koreader/help"] = { "quickstart-en.html", "guide.pdf" },
    ["/mnt/us/koreader/resources"] = { "icon.png", "icon.svg" },
    ["/mnt/us/koreader/fonts"] = { "Noto.ttf" },
    ["/mnt/us/extensions"] = { "readme.txt" },
    ["/mnt/us/screensaver"] = { "cat.png" },
    ["/mnt/us/linkss"] = { "screensavers" },
    ["/mnt/us/linkss/screensavers"] = { "a.png" },
    ["/mnt/us/books"] = { "Truyen Kieu.fb2.zip", "manga.cbz", "page.html", "archive.zip", "Notes.TXT" },
    ["/mnt/us/.active_content_sandbox"] = { "x.pdf" },
}
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(p, what)
        local mode = tree[p] and "directory" or "file"
        if what == "mode" then return mode end
        return { mode = mode }
    end,
    dir = function(p)
        local list, i = tree[p] or {}, 0
        return function() i = i + 1; return list[i] end, nil
    end,
    currentdir = function() return "/mnt/us/koreader" end,
}
package.loaded["ffi/util"] = setmetatable({ realpath = function(p) return p end }, { __index = require("ffi/util") })

local Library = require("mh/data/library")
local got = Library.listFiles("/mnt/us")
table.sort(got)
local expected = {
    "/mnt/us/books/Notes.TXT",
    "/mnt/us/books/Truyen Kieu.fb2.zip",
    "/mnt/us/books/manga.cbz",
    "/mnt/us/documents/Dune.azw3",
    "/mnt/us/documents/Sapiens.epub",
    "/mnt/us/notes.pdf",
}
local ok = #got == #expected
for i = 1, math.max(#got, #expected) do if got[i] ~= expected[i] then ok = false end end
if ok then print("library filter OK (" .. #got .. " books)") else
    print("FAIL library filter, got:\n  " .. table.concat(got, "\n  ")); os.exit(1)
end

-- Kindle Store files KOReader can't read: KFX, and MOBI/AZW with DRM
do
    local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p " .. dir)
    local function write(name, data) local f = io.open(dir .. "/" .. name, "wb"); f:write(data); f:close(); return dir .. "/" .. name end
    local function be16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
    local function be32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
    local function mobi(enc)
        local head = string.rep("\0", 60) .. "BOOKMOBI" .. string.rep("\0", 8) .. be16(1) .. be32(96)
        head = head .. string.rep("\0", 96 - #head)
        return head .. string.rep("\0", 12) .. be16(enc) .. string.rep("\0", 50)
    end
    local kfx = write("a.azw", "CONT" .. string.rep("x", 200))
    local drm = write("b.azw", mobi(2))
    local free = write("c.azw3", mobi(0))
    local epub = write("d.epub", "PK")
    local bad = {}
    if not Library.isKindleOnly(kfx) then bad[#bad + 1] = "kfx" end
    if not Library.isKindleOnly(drm) then bad[#bad + 1] = "drm mobi" end
    if Library.isKindleOnly(free) then bad[#bad + 1] = "drm-free azw3 flagged" end
    if Library.isKindleOnly(epub) then bad[#bad + 1] = "epub flagged" end
    os.execute("rm -rf " .. dir)
    if #bad == 0 then print("kindle-only detection OK") else print("FAIL kindle-only: " .. table.concat(bad, ", ")); os.exit(1) end
end
