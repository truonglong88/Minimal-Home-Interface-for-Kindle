--[[--
Reads the user's books from disk and from KOReader's own records:

* the books folder (KOReader's home folder unless set otherwise)
* reading history (when each book was last opened)
* each book's sidecar settings (progress, finished or not)
* the CoverBrowser plugin's database (title, author, page count, cover)
--]]

local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local Library = {}

local MAX_DEPTH = 6

local bim_loaded, BookInfoManager
local function getBIM()
    if bim_loaded == nil then
        -- Provided by the CoverBrowser plugin (bundled with KOReader).
        bim_loaded, BookInfoManager = pcall(require, "bookinfomanager")
        if not bim_loaded then
            logger.warn("MinimalHome: CoverBrowser not available, covers and metadata disabled")
            BookInfoManager = nil
        end
    end
    return BookInfoManager
end
Library.getBookInfoManager = getBIM

-- Only real book formats. KOReader can also open images, HTML, SVG and the
-- like, which would pull app icons, help pages and screensavers into the list.
local BOOK_EXT = {}
for ext in ([[epub epub3 kepub pdf mobi azw azw3 azw4 prc pdb fb2 fb3 fbz djvu djv
            cbz cbr cbt cb7 xps oxps doc docx odt rtf chm txt md]]):gmatch("%S+") do
    BOOK_EXT[ext] = true
end
Library.BOOK_EXT = BOOK_EXT

-- Folders that never hold the user's own books: apps, jailbreak tools, system
-- files and dictionaries (Kindle keeps those under documents/dictionaries).
local SKIP_DIRS = {}
for name in ([[koreader kual extensions mrpackages system linkss usbnet libkh
            screensaver screensavers fonts dictionaries dictionary audible voice
            sdr_backups thumbnails]]):gmatch("%S+") do
    SKIP_DIRS[name] = true
end

local SKIP_FILES = { ["my clippings.txt"] = true }

function Library.isBookFile(name)
    local lower = name:lower()
    if SKIP_FILES[lower] then return false end
    local ext = lower:match("%.([%w]+)$")
    if ext == "zip" then ext = lower:match("%.([%w]+)%.zip$") end -- book.fb2.zip
    return ext ~= nil and BOOK_EXT[ext] == true
end

local function scanDir(dir, depth, out)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
            local path = dir .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                if depth < MAX_DEPTH and not SKIP_DIRS[name:lower()] then
                    scanDir(path, depth + 1, out)
                end
            elseif mode == "file" and Library.isBookFile(name) and DocumentRegistry:hasProvider(path) then
                out[#out + 1] = ffiutil.realpath(path) or path
            end
        end
    end
end

function Library.listFiles(root)
    local out, seen = {}, {}
    if root and lfs.attributes(root, "mode") == "directory" then
        scanDir(root, 1, out)
    end
    -- the same book reached through a symlink only counts once
    local unique = {}
    for _, path in ipairs(out) do
        if not seen[path] then seen[path] = true; unique[#unique + 1] = path end
    end
    return unique
end

local function titleFromFilename(path)
    local _, filename = util.splitFilePathName(path)
    local name = util.splitFileNameSuffix(filename)
    return (name:gsub("[_]+", " "))
end

-- Kindle Store files KOReader cannot read --------------------------------------------

local KINDLE_EXT = { azw = true, azw3 = true, azw4 = true, kfx = true, prc = true, mobi = true }
local kindle_cache = {}

local function u16(s, i) return s:byte(i) * 256 + s:byte(i + 1) end
local function u32(s, i) return ((s:byte(i) * 256 + s:byte(i + 1)) * 256 + s:byte(i + 2)) * 256 + s:byte(i + 3) end

--- True for Kindle Store files KOReader can't open: KFX (newer Amazon format,
--- also what Send to Kindle delivers) and MOBI/AZW with DRM.
function Library.isKindleOnly(path)
    local ext = (util.getFileNameSuffix(path) or ""):lower()
    if not KINDLE_EXT[ext] then return false end
    if ext == "kfx" then return true end
    local mtime = lfs.attributes(path, "modification")
    if type(mtime) ~= "number" then mtime = 0 end
    local key = path .. "@" .. mtime
    if kindle_cache[key] ~= nil then return kindle_cache[key] end
    local result = false
    local f = io.open(path, "rb")
    if f then
        local head = f:read(96) or ""
        if head:sub(1, 4) == "CONT" or head:sub(1, 8) == "\234DRMION\238" then
            result = true -- KFX container
        elseif #head >= 82 and (head:sub(61, 68) == "BOOKMOBI" or head:sub(61, 68) == "TEXtREAd") then
            -- PalmDB: first record holds the MOBI header; bytes 12-13 = encryption type
            local rec0 = u32(head, 79)
            if f:seek("set", rec0) then
                local r = f:read(16) or ""
                if #r >= 14 and u16(r, 13) ~= 0 then result = true end
            end
        end
        f:close()
    end
    kindle_cache[key] = result
    return result
end

--- One book record. `last_opened` maps path → time; `missing` collects paths
--- CoverBrowser has not indexed yet (both optional).
function Library.record(path, last_opened, missing)
    local bim = getBIM()
    local info = BookList.getBookInfo(path)
    local status = BookList.getBookStatus(path)
    local b = {
        path = path,
        title = titleFromFilename(path),
        authors = nil,
        pages = info.pages,
        percent = info.percent_finished,
        status = status,
        last_opened = last_opened and last_opened[path],
        added = lfs.attributes(path, "modification"),
        format = (util.getFileNameSuffix(path) or ""):upper(),
        has_cover = false,
    }
    local ko_ok, kindle_only = pcall(Library.isKindleOnly, path)
    b.kindle_only = ko_ok and kindle_only or false
    if b.last_opened == nil and status ~= "new" then
        -- opened before history existed: fall back to the sidecar date
        b.last_opened = b.added
    end
    if bim then
        local ok, bi = pcall(bim.getBookInfo, bim, path, false)
        if ok and bi then
            if bi.title and bi.title ~= "" then b.title = bi.title end
            if bi.authors and bi.authors ~= "" then b.authors = bi.authors:gsub("\n", ", ") end
            if (not b.pages or b.pages == 0) and bi.pages then b.pages = bi.pages end
            b.has_cover = bi.has_cover and true or false
            b._cover_w, b._cover_h = bi.cover_w, bi.cover_h
        elseif missing and not b.kindle_only then
            missing[#missing + 1] = path
        end
    end
    return b
end

--- Build the book records for every file under `root`.
--- Returns books, and the list of paths CoverBrowser has not indexed yet.
function Library.load(root)
    ReadHistory:reload()
    local last_opened = {}
    for _, item in ipairs(ReadHistory.hist) do
        if not last_opened[item.file] then last_opened[item.file] = item.time end
    end
    local books, missing = {}, {}
    for _, path in ipairs(Library.listFiles(root)) do
        books[#books + 1] = Library.record(path, last_opened, missing)
    end
    return books, missing
end

--- The book to suggest after finishing `exclude`: the most recently opened
--- book that is started but not finished; else the newest unopened one in history.
function Library.upNext(exclude)
    ReadHistory:reload()
    local fallback
    for _, item in ipairs(ReadHistory.hist) do
        local path = item.file
        if path ~= exclude and lfs.attributes(path, "mode") == "file" and Library.isBookFile(path) then
            local status = BookList.getBookStatus(path)
            if status == "reading" then
                return Library.record(path, { [path] = item.time })
            elseif status ~= "complete" and not fallback then
                fallback = path
            end
        end
    end
    return fallback and Library.record(fallback) or nil
end

--- Cut away plain white bands around a cover image (many EPUB covers are
--- letterboxed), so the thumbnail's centre crop fills the frame with the art.
--- Returns a new blitbuffer (the old one is freed) or the original if there is
--- nothing worth trimming or the pixels can't be read.
function Library.trimWhite(bb)
    local ok, out = pcall(function()
        local w, h = bb:getWidth(), bb:getHeight()
        if w < 20 or h < 20 then return bb end
        local WHITE = 235
        local function light(x, y)
            local c = bb:getPixel(x, y)
            return c:getColor8().a >= WHITE
        end
        local step_x = math.max(1, math.floor(w / 40))
        local step_y = math.max(1, math.floor(h / 40))
        local function columnWhite(x)
            for y = 0, h - 1, step_y do if not light(x, y) then return false end end
            return true
        end
        local function rowWhite(y)
            for x = 0, w - 1, step_x do if not light(x, y) then return false end end
            return true
        end
        local left, right, top, bottom = 0, w - 1, 0, h - 1
        while left < right and columnWhite(left) do left = left + 1 end
        while right > left and columnWhite(right) do right = right - 1 end
        while top < bottom and rowWhite(top) do top = top + 1 end
        while bottom > top and rowWhite(bottom) do bottom = bottom - 1 end
        local nw, nh = right - left + 1, bottom - top + 1
        -- nothing to trim, or the "cover" is mostly white: leave it alone
        if (nw >= w - 2 and nh >= h - 2) or nw < w * 0.4 or nh < h * 0.4 then return bb end
        local Blitbuffer = require("ffi/blitbuffer")
        local nb = Blitbuffer.new(nw, nh, bb:getType())
        nb:blitFrom(bb, 0, 0, left, top, nw, nh)
        bb:free()
        return nb
    end)
    if ok and out then return out end
    return bb
end

--- Fetch a cover blitbuffer (caller owns it), or nil. White bands are trimmed.
function Library.getCover(path)
    local bim = getBIM()
    if not bim then return nil end
    local ok, bi = pcall(bim.getBookInfo, bim, path, true)
    if ok and bi and bi.cover_bb then return Library.trimWhite(bi.cover_bb) end
    return nil
end

--- Average reading speed (seconds per page) from KOReader's Reading statistics:
--- this book's own pace once a few pages are read, otherwise the reader's overall pace.
function Library.secondsPerPage(path)
    local ok, result = pcall(function()
        local DataStorage = require("datastorage")
        local DocSettings = require("docsettings")
        local SQ3 = require("lua-ljsqlite3/init")
        local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if lfs.attributes(db, "mode") ~= "file" then return nil end
        local md5 = DocSettings:open(path):readSetting("partial_md5_checksum")
        local conn = SQ3.open(db, "ro")
        local per
        if md5 and md5:match("^%x+$") then
            local t, p = conn:rowexec(string.format(
                "SELECT total_read_time, total_read_pages FROM book WHERE md5 = '%s' LIMIT 1;", md5))
            t, p = tonumber(t), tonumber(p)
            if t and p and p >= 5 and t > 0 then per = t / p end
        end
        if not per then
            local t, p = conn:rowexec("SELECT sum(total_read_time), sum(total_read_pages) FROM book;")
            t, p = tonumber(t), tonumber(p)
            if t and p and p >= 5 and t > 0 then per = t / p end
        end
        conn:close()
        return per
    end)
    if ok then return result end
    logger.dbg("MinimalHome: no reading statistics:", result)
    return nil
end

--- Ask CoverBrowser to index books in a background process.
--- `on_done` is called once extraction has finished.
function Library.indexInBackground(paths, cover_w, cover_h, UIManager, on_done)
    local bim = getBIM()
    if not bim or #paths == 0 then return false end
    local specs = { max_cover_w = cover_w, max_cover_h = cover_h }
    local files = {}
    for i, p in ipairs(paths) do files[i] = { filepath = p, cover_specs = specs } end
    local launched = bim:extractInBackground(files)
    if not launched then return false end
    local function poll()
        if bim:isExtractingInBackground() then
            UIManager:scheduleIn(1, poll)
        else
            on_done()
        end
    end
    UIManager:scheduleIn(1, poll)
    return true
end

return Library
