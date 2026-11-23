--[[--
The Library home screen.

Status bar on top; below it one scrolling column: header (title, search,
settings) · hero (currently reading / what's next) · recent · all books.

E-ink smears when content follows the finger, so a swipe scrolls by the
distance swiped and the screen is redrawn once, when the finger lifts.
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local time = require("ui/time")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Library = require("mh/data/library")
local Model = require("mh/data/model")
local Prefs = require("mh/data/prefs")
local Theme = require("mh/theme")
local Viewport = require("mh/ui/viewport")

local px = Theme.px

-- Layers paint bottom to top, but hand taps to the topmost layer first, so a
-- button floating over the list (Back to top) is never "seen through".
local Layers = OverlapGroup:extend{}
function Layers:propagateEvent(event)
    for i = #self, 1, -1 do
        if self[i]:handleEvent(event) then return true end
    end
    return false
end

local Home = InputContainer:extend{
    name = "MinimalHome",
    ui = nil,          -- the FileManager instance
    on_close = nil,
}

function Home:init()
    self.covers_fullscreen = true
    -- a drag that started on the book (swipe up to Home) must not scroll the list
    self.calm_until = time.now() + time.s(1)
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }

    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        self.ges_events.MHSwipe = { GestureRange:new{ ges = "swipe", range = range } }
        self.ges_events.MHPan = { GestureRange:new{ ges = "pan", range = range } }
        self.ges_events.MHPanRelease = { GestureRange:new{ ges = "pan_release", range = range } }
        -- long-press the clock / battery strip: screenshot
        self.ges_events.MHShot = { GestureRange:new{ ges = "hold", range = function()
            return Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.view_top or px(140) }
        end } }
    end
    if Device:hasKeys() then
        self.key_events.MHNextPage = { { Device.input.group.PgFwd } }
        self.key_events.MHPrevPage = { { Device.input.group.PgBack } }
    end
    self:reload()
    self:scheduleClock()
    -- ‹ Back from a book opened in a folder: that folder again
    if Home.back_pressed and Home.return_folders then
        local paths = Home.return_folders
        Home.back_pressed, Home.return_folders = nil, nil
        UIManager:nextTick(function() self:reopenFolders(paths) end)
    end
    Home.back_pressed = nil
    -- a new build on GitHub? At most once an hour, only when Wi-Fi is already on
    require("mh/updater").checkSoon(require("mh/updater").HOME_EVERY,
        function(_, _, changed) if changed then self:rebuild() end end)
end

-- Data ------------------------------------------------------------------------

function Home:reload()
    local ok, err = pcall(function()
        self.books, self.missing = Library.load(Prefs.booksFolder())
    end)
    if not ok then
        logger.err("MinimalHome: failed to read library:", err)
        self.books, self.missing = {}, {}
    end
    self.state = Model.homeState(self.books)
    self:resort()
    self:layout()
    self:indexMissing()
end

function Home:resort()
    self.sort_key = Prefs.get("sort_key")
    self.sort_asc = Prefs.get("sort_asc")
    self.sorted = Model.sortBooks(self.books, self.sort_key, self.sort_asc)
    self.entries = nil
    if self.sort_key == "folders" then
        -- folders first (one row each), then the books on their own
        local root = Prefs.booksFolder()
        pcall(function() root = require("ffi/util").realpath(root) or root end)
        root = Model.foldersRoot(self.books, root)
        local folders, loose = Model.groupByFolder(self.books, root, self.sort_asc)
        self.entries = {}
        for _, f in ipairs(folders) do self.entries[#self.entries + 1] = { folder = f } end
        for _, b in ipairs(loose) do self.entries[#self.entries + 1] = { book = b } end
    end
    self.blocks = nil
end

function Home:indexMissing()
    if self.indexing or not self.missing or #self.missing == 0 then return end
    self.indexing = Library.indexInBackground(self.missing, px(340), px(480), UIManager, function()
        self.indexing = false
        if self.closed then return end
        self.books, self.missing = Library.load(Prefs.booksFolder())
        self.missing = {} -- don't loop on books that can't be indexed
        self.state = Model.homeState(self.books)
        self:resort()
        self:layout()
        UIManager:setDirty(self, "ui")
    end)
end

-- Layout helpers ---------------------------------------------------------------

function Home:contentWidth()
    return self.dimen.w - 2 * px(Theme.margin_h)
end

function Home:label(text)
    return C.text(text, "sans_bold", 32, self.col.muted)
end

function Home:coverFor(book, w, h, opts)
    opts = opts or {}
    opts.colors = self.col
    opts.frame = self.col.line -- grey frame on every cover, drawn or image
    if book.has_cover then
        opts.cover_bb = Library.getCover(book.path)
    end
    return C.cover(book, w, h, opts)
end

function Home:statusBar()
    return C.statusBar(self:contentWidth(), self.col, 36, true, true)
end

function Home:header()
    local w = self:contentWidth()
    local search_w, btn = px(520), px(112)
    local gap = px(24)
    local title_w = w - search_w - btn - 2 * gap
    local title = C.text("Library", "serif_bold", 84, self.col.fg, title_w)

    local search = HorizontalGroup:new{
        align = "center",
        C.icon("appbar.search", px(44)),
        C.space(px(18), 1),
        C.text("Search books…", "sans_medium", 36, self.col.muted, search_w - px(44 + 18 + 52)),
    }
    local search_box = C.tappable(
        C.box(search_w, btn, search, { border = px(4), border_color = self.col.fg, radius = px(10),
            pad_l = px(26), valign = "center" }),
        function() self:openSearch() end)
    local settings_btn = C.box(btn, btn, C.slidersIcon(px(64), self.col.fg, self.col.bg), { border = px(4),
        border_color = self.col.fg, radius = px(10), halign = "center", valign = "center" })
    if require("mh/updater").available() then
        -- a new build is waiting: black dot (white ring) on the button's top-right corner
        local d, ring = px(30), px(6)
        local o = d + 2 * ring
        local dot = C.box(o, o, C.Rect:new{ w = d, h = d, color = self.col.fg, radius = math.floor(d / 2) },
            { bg = self.col.bg, radius = math.floor(o / 2), pad = ring })
        dot.overlap_offset = { btn - o + px(8), -px(8) }
        settings_btn = OverlapGroup:new{ dimen = Geom:new{ w = btn, h = btn }, allow_mirroring = false,
            settings_btn, dot }
    end
    local settings_box = C.tappable(settings_btn, function() self:openSettings() end)

    return HorizontalGroup:new{
        align = "center",
        C.box(title_w, btn, title, { valign = "center" }),
        C.space(gap, 1), search_box, C.space(gap, 1), settings_box,
    }
end

Home.BUTTON_H = 124 -- design px
Home.TRACK = require("ffi/blitbuffer").gray(0.2) -- #CCCCCC, unread part of the hero progress bar

-- Hero: the big "Currently reading" / "What's next?" block.
function Home:hero(book, opts)
    local w = self:contentWidth()
    local cover_w, cover_h, gap = px(360), px(510), px(56)
    local col_w = w - cover_w - gap
    local cover = C.tappable(self:coverFor(book, cover_w, cover_h,
        { style_index = 1, title_size = 52, author_size = 28, border = px(3), radius = px(12) }),
        function() self:openBook(book.path) end)

    local top = VerticalGroup:new{ align = "left" }
    if opts.subline then
        table.insert(top, C.text(opts.subline, "sans_medium", 30, self.col.muted, col_w))
        table.insert(top, C.space(1, px(14)))
    end
    local title = C.textbox(book.title, "serif_bold", 62, self.col.fg, col_w, 3, 0.1)
    table.insert(top, title)
    if book.authors then
        table.insert(top, C.space(1, px(14)))
        table.insert(top, C.text(book.authors, "sans_medium", 40, self.col.muted, col_w))
    end

    local middle = VerticalGroup:new{ align = "left" }
    if opts.meta and opts.meta ~= "" then
        middle = VerticalGroup:new{ align = "left", C.text(opts.meta, "sans_medium", 34, self.col.muted, col_w) }
    end
    if Model.isInProgress(book) then
        -- progress bar, then one line under it: time left on the left, % on the right
        local pct_w = C.text(Model.percentInt(book) .. "%", "sans_bold", 36, self.col.muted)
        local pw, ph = pct_w:getSize().w, pct_w:getSize().h
        local left = Model.bookTimeLeft(book, Library.secondsPerPage(book.path))
        local line = OverlapGroup:new{ dimen = Geom:new{ w = col_w, h = ph } }
        if left then
            local lt = C.text(left, "sans_medium", 34, self.col.muted, col_w - pw - px(24))
            table.insert(line, C.box(lt:getSize().w, ph, lt, { valign = "center" }))
        end
        table.insert(line, C.box(pw, ph, pct_w, { overlap_align = "right" }))
        middle = VerticalGroup:new{
            align = "left",
            C.progress(col_w, px(16), book.percent or 0, Home.TRACK, self.col.fg, px(8)),
            C.space(1, px(22)),
            line,
        }
    end

    local button_label = opts.button or "Continue reading"
    local button = C.tappable(
        C.box(col_w, px(Home.BUTTON_H), C.text(button_label .. "  →", "sans_bold", 42, self.col.bg),
            { bg = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() self:openBook(book.path) end)

    -- The column is exactly as tall as the cover: title block at the top, button at
    -- the bottom, progress in the middle (design: flex column, space-between).
    local pad_v = px(6)
    local min_gap = px(24)
    local function spare()
        return cover_h - 2 * pad_v - top:getSize().h - middle:getSize().h - px(Home.BUTTON_H)
    end
    if spare() < 2 * min_gap then
        -- long title: keep it to two lines so the progress block can breathe
        local idx
        for i, child in ipairs(top) do if child == title then idx = i end end
        title:free()
        title = C.textbox(book.title, "serif_bold", 62, self.col.fg, col_w, 2, 0.1)
        top[idx] = title
        top:resetLayout()
    end
    local room = math.max(0, spare())
    local column = VerticalGroup:new{
        align = "left",
        C.space(1, pad_v),
        top,
        C.space(1, math.floor(room / 2)),
        middle,
        C.space(1, room - math.floor(room / 2)),
        button,
    }
    return HorizontalGroup:new{ align = "top", cover, C.space(gap, 1), column }
end

--- No books in the folder yet (design: "Home – no books").
function Home:emptyLibrary()
    local w = self:contentWidth()
    local text_w = math.min(w, px(900))
    local g = VerticalGroup:new{
        align = "center",
        C.text("No books yet", "serif_bold", 64, self.col.fg, w),
        C.space(1, px(28)),
        C.textbox("Connect your Kindle to a computer and copy EPUB or PDF files into its documents folder. "
            .. "They show up here the next time Home opens.", "sans_medium", 36, self.col.muted, text_w, 5, 0.3, "center"),
    }
    return C.box(w, g:getSize().h, g, { halign = "center" })
end

function Home:finishedBanner(book)
    local w = self:contentWidth()
    local check = C.text("✓", "sans_bold", 40, self.col.fg)
    local lead = C.text("Just finished ", "sans_medium", 34, self.col.fg)
    local title_max = w - px(56) - check:getSize().w - px(18) - lead:getSize().w
    local row = HorizontalGroup:new{
        align = "center",
        check, C.space(px(18), 1), lead,
        C.text(book.title, "sans_bold", 34, self.col.fg, title_max),
    }
    return C.box(w, px(104), row, { border = px(4), border_color = self.col.fg, radius = px(10),
        pad_l = px(30), valign = "center" })
end

function Home:startNewCards(list)
    local w = self:contentWidth()
    local gap = px(40)
    local card_w = math.floor((w - gap) / 2)
    local cover_w, cover_h = px(132), px(192)
    local text_w = card_w - 2 * px(24) - cover_w - px(28)
    local row = HorizontalGroup:new{ align = "top" }
    for i, b in ipairs(list) do
        local texts = VerticalGroup:new{
            align = "left",
            C.textbox(b.title, "serif_bold", 38, self.col.fg, text_w, 2, 0.1),
            C.space(1, px(8)),
            C.text(b.authors or "", "sans_medium", 30, self.col.muted, text_w),
            C.space(1, px(8)),
            C.text(Model.whenLabel(b), "sans_medium", 26, self.col.muted, text_w),
        }
        local inner = HorizontalGroup:new{
            align = "center",
            self:coverFor(b, cover_w, cover_h, { compact = true, title_size = 22, border = px(2), radius = px(8), style_index = i + 1 }),
            C.space(px(28), 1),
            texts,
        }
        local card = C.tappable(C.box(card_w, cover_h + 2 * px(24), inner, { border = px(3),
            border_color = self.col.line, radius = px(12), pad_l = px(24), valign = "center" }),
            function() self:openBook(b.path) end)
        if i > 1 then table.insert(row, C.space(gap, 1)) end
        table.insert(row, card)
    end
    return row
end

function Home:recentRow(list)
    local w = self:contentWidth()
    local gap = px(40)
    local col_w = math.floor((w - 3 * gap) / 4)
    local cover_h = px(350)
    local row = HorizontalGroup:new{ align = "top" }
    for i, b in ipairs(list) do
        local status = Model.shortStatus(b)
        local item = VerticalGroup:new{
            align = "left",
            self:coverFor(b, col_w, cover_h, { style_index = i + 1, title_size = 34, author_size = 20, border = px(3), radius = px(10) }),
            C.space(1, px(18)),
            C.textbox(b.title, "sans_bold", 32, self.col.fg, col_w, 2, 0.15),
            C.space(1, px(6)),
            C.text(status, "sans_medium", 28, self.col.muted, col_w),
        }
        if i > 1 then table.insert(row, C.space(gap, 1)) end
        table.insert(row, C.tappable(item, function() self:openBook(b.path) end))
    end
    return row
end

Home.ROW_H = 296 -- design px, without the divider
Home.LINE = 3   -- divider thickness, design px
function Home:bookRow(b, index)
    local w = self:contentWidth()
    local cover_w, cover_h = px(148), px(216)
    local gap = px(40)
    local col_w = w - cover_w - gap

    local when = C.text(Model.whenLabel(b), "sans_medium", 30, self.col.muted)
    local title = C.text(b.title, "serif_bold", 44, self.col.fg, col_w - when:getSize().w - px(24))
    local line1 = OverlapGroup:new{
        dimen = Geom:new{ w = col_w, h = title:getSize().h },
        title,
        C.box(when:getSize().w, title:getSize().h, when, { valign = "center" }),
    }
    line1[2].overlap_align = "right"

    local meta = C.text(Model.metaLine(b), "sans_medium", 30, self.col.muted)
    local line3 = OverlapGroup:new{ dimen = Geom:new{ w = col_w, h = meta:getSize().h }, meta }
    if b.kindle_only then
        -- KOReader can't read it: say so in the list (design: "KINDLE ONLY" tag)
        local t = C.text("KINDLE ONLY", "sans_bold", 24, self.col.fg)
        local tag = C.box(t:getSize().w + 2 * px(16), px(52), t, { border = px(3), border_color = self.col.fg,
            radius = px(8), halign = "center", valign = "center" })
        tag.overlap_align = "right"
        line3.dimen.h = math.max(line3.dimen.h, px(52))
        table.insert(line3, tag)
    elseif Model.isFinished(b) then
        local done = C.text("✓ Finished", "sans_medium", 30, self.col.muted)
        done.overlap_align = "right"
        table.insert(line3, done)
    end

    local texts = VerticalGroup:new{ align = "left", line1, C.space(1, px(10)) }
    -- no author: the file type / pages line moves up under the title
    local authors = b.authors and b.authors:match("%S") and b.authors
    if authors then
        table.insert(texts, C.text(authors, "sans_medium", 34, self.col.muted, col_w))
        table.insert(texts, C.space(1, px(10)))
    end
    table.insert(texts, line3)
    if Model.isInProgress(b) and b.percent then
        table.insert(texts, C.space(1, px(18)))
        table.insert(texts, HorizontalGroup:new{
            align = "center",
            C.progress(px(300), px(12), b.percent, Home.TRACK, self.col.fg, px(6)),
            C.space(px(20), 1),
            C.text(Model.percentInt(b) .. "%", "sans_bold", 30, self.col.muted),
        })
    end

    -- text column starts at the top of the cover, whatever its length
    local content = HorizontalGroup:new{
        align = "top",
        self:coverFor(b, cover_w, cover_h, { compact = true, title_size = 23, border = px(2), radius = px(8), style_index = index }),
        C.space(gap, 1),
        texts,
    }
    return VerticalGroup:new{
        align = "left",
        C.hline(w, px(Home.LINE), self.col.line),
        C.tappable(C.box(w, px(Home.ROW_H), content, { valign = "center" }),
            function() self:openBook(b.path) end,
            function() UIManager:nextTick(function() self:confirmDelete(b) end) end),
    }
end

--- Hold a book in All books: delete it from the Kindle, after asking.
--- A folder in the Folders view (design: "All books – Folders view"): a small pile
--- of covers with the top book's cover in front, the name, how many books and,
--- while one is being read, which one and how far.
function Home:folderRow(f, index)
    local w = self:contentWidth()
    local cover_w, cover_h = px(148), px(216)
    local step = px(12)
    local pile_w, pile_h = cover_w + 2 * step, cover_h + 2 * step
    local gap = px(40)
    local chev_w = px(40)
    local col_w = w - pile_w - gap - chev_w - px(16)

    local back1 = C.Rect:new{ w = cover_w, h = cover_h, color = self.col.line, radius = px(8) }
    back1.overlap_offset = { 2 * step, 0 }
    local back2 = C.box(cover_w, cover_h, C.space(1, 1), { bg = self.col.bg, border = px(2), border_color = self.col.line,
        radius = px(8) })
    back2.overlap_offset = { step, step }
    local front = f.top and self:coverFor(f.top, cover_w, cover_h,
        { compact = true, title_size = 23, border = px(2), radius = px(8), style_index = index })
        or C.box(cover_w, cover_h, C.space(1, 1), { border = px(2), border_color = self.col.line, radius = px(8) })
    front.overlap_offset = { 0, 2 * step }
    local pile = OverlapGroup:new{ dimen = Geom:new{ w = pile_w, h = pile_h }, allow_mirroring = false,
        back1, back2, front }

    local count, reading = Model.folderSummary(f)
    local texts = VerticalGroup:new{ align = "left",
        C.text(f.name, "serif_bold", 44, self.col.fg, col_w), C.space(1, px(10)) }
    local meta = count
    if reading then meta = count .. " · Reading " .. Model.volumeLabel(reading) end
    table.insert(texts, C.text(meta, "sans_medium", 32, self.col.muted, col_w))
    if reading and reading.percent then
        table.insert(texts, C.space(1, px(18)))
        table.insert(texts, HorizontalGroup:new{
            align = "center",
            C.progress(px(300), px(12), reading.percent, Home.TRACK, self.col.fg, px(6)),
            C.space(px(20), 1),
            C.text(Model.percentInt(reading) .. "%", "sans_bold", 30, self.col.muted),
        })
    end
    local content = HorizontalGroup:new{
        align = "center",
        pile, C.space(gap, 1),
        C.box(col_w, pile_h, texts, { valign = "center" }),
        C.space(px(16), 1),
        C.text("›", "sans_bold", 48, self.col.muted),
    }
    return VerticalGroup:new{
        align = "left",
        C.hline(w, px(Home.LINE), self.col.line),
        C.tappable(C.box(w, px(Home.ROW_H), content, { valign = "center" }),
            function() UIManager:nextTick(function() self:openFolder(f) end) end),
    }
end

--- Open the folder pages for these paths again (outermost first).
function Home:reopenFolders(paths)
    if self.closed then return end
    for _, path in ipairs(paths) do
        local f = { name = path:match("([^/]+)$") or path, path = path, books = {} }
        local prefix = path .. "/"
        for _, b in ipairs(self.books or {}) do
            if (b.path or ""):sub(1, #prefix) == prefix then f.books[#f.books + 1] = b end
        end
        if #f.books == 0 then return end -- moved or deleted meanwhile: stay on Home
        self:openFolder(f)
    end
end

function Home:openFolder(f)
    require("mh/ui/folderpage"):new{ ui = self.ui, home = self, folder = f }:show()
end

function Home:confirmDelete(b)
    require("mh/ui/confirm").show{
        title = "Delete this book?",
        text = "“" .. (b.title or "") .. "” will be removed from this Kindle, with its reading progress and highlights. "
            .. "This can’t be undone.",
        ok_text = "Delete",
        ok_callback = function()
            UIManager:nextTick(function()
                if require("mh/device").deleteBook(self.ui, b.path) then
                    if not self.closed then
                        -- stay where we were: the books below move up into the gap
                        self._keep_scroll = self.viewport and self.viewport.scroll or 0
                        self:reload()
                        UIManager:setDirty(self, "ui")
                    end
                    require("mh/ui/snackbar").show("Book deleted")
                else
                    require("mh/ui/snackbar").show("Couldn’t delete this book")
                end
            end)
        end,
    }
end

function Home:allBooksHeader()
    local w = self:contentWidth()
    local label = self:label("ALL BOOKS · " .. #self.books)
    local sort_text = C.text(Model.sortLabel(self.sort_key, self.sort_asc) .. "  ⌄", "sans_bold", 34, self.col.fg)
    local h = px(76)
    local sort = C.tappable(C.box(sort_text:getSize().w, h, sort_text, { valign = "center" }),
        function() self:showSortMenu() end)
    self.sort_button = sort
    sort.overlap_align = "right"
    -- "Sync books": look in the documents folder again (books copied while Home is open)
    local syncing = self.syncing
    local link_col = syncing and self.col.muted or self.col.fg
    local link_t = C.text(syncing and "Syncing…" or "Sync books", "sans_bold", 32, link_col)
    local link = VerticalGroup:new{ align = "left", link_t }
    if not syncing then
        table.insert(link, C.space(1, px(4)))
        table.insert(link, C.hline(link_t:getSize().w, px(3), link_col))
    end
    local pad = px(12)
    local link_box = C.tappable(C.box(link:getSize().w + 2 * pad, h, link, { halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:syncBooks() end) end)
    local left = HorizontalGroup:new{ align = "center",
        C.box(label:getSize().w, h, label, { valign = "center" }), C.space(px(20) - pad, 1), link_box }
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        left,
        sort,
    }
end

--- Sync books: read the documents folder again and say how many books are new.
--- The list stays where it was scrolled.
function Home:syncBooks()
    if self.syncing or self.closed then return end
    self.syncing = true
    self:rebuild() -- "Syncing…"
    UIManager:forceRePaint()
    UIManager:scheduleIn(0.05, function()
        if self.closed then return end
        local before = {}
        for _, b in ipairs(self.books or {}) do before[b.path] = true end
        self.syncing = false
        self._keep_scroll = self.viewport and self.viewport.scroll or 0
        self:reload()
        local new = 0
        for _, b in ipairs(self.books or {}) do
            if not before[b.path] then new = new + 1 end
        end
        UIManager:setDirty(self, "ui")
        require("mh/ui/snackbar").show(new == 0 and "No new books"
            or (new == 1 and "1 new book" or (new .. " new books")))
    end)
end

-- Screen assembly -----------------------------------------------------------------
--
-- Everything below the status bar is one tall column of blocks (header, hero,
-- recent, the "All books" header, one block per book) shown through a Viewport.
-- Swipes scroll the column by the distance swiped; the screen is redrawn once,
-- when the finger lifts, which keeps e-ink clean.

function Home:topBlocks()
    local s = self.state
    local blocks = {}
    local function block(space_before, build)
        blocks[#blocks + 1] = function()
            return VerticalGroup:new{ align = "left", C.space(1, px(space_before)), build() }
        end
    end

    block(44, function() return self:header() end)

    if s.mode == "empty" then
        block(200, function() return self:emptyLibrary() end)
        return blocks, false
    end

    if s.mode == "finished" then
        block(48, function() return self:finishedBanner(s.just_finished) end)
    end

    if s.hero then
        local label, subline, button
        if s.mode == "reading" then
            label = "CURRENTLY READING"
        elseif s.mode == "finished" then
            label = "WHAT’S NEXT?"
            if s.hero_is_new then
                subline, button = "New · " .. Model.whenLabel(s.hero):lower(), "Start reading"
            else
                subline = "In progress · opened " .. Model.whenLabel(s.hero):lower()
            end
        else
            label = "START READING"
            button = Model.isOpened(s.hero) and "Continue reading" or "Start reading"
            if not Model.isOpened(s.hero) then
                subline = "New · " .. Model.whenLabel(s.hero):lower()
            end
        end
        -- a book not started yet: format and length where the progress would be
        local meta = not Model.isInProgress(s.hero) and Model.metaLine(s.hero) or nil
        local hero_path = s.hero.path
        block(60, function()
            -- the whole block (label, cover, title, progress, button) opens the book
            return C.tappable(VerticalGroup:new{
                align = "left",
                self:label(label), C.space(1, px(28)),
                self:hero(s.hero, { subline = subline, button = button, meta = meta }),
            }, function() self:openBook(hero_path) end)
        end)
    end

    if s.mode == "finished" and #s.start_new > 0 then
        block(64, function()
            return VerticalGroup:new{
                align = "left",
                self:label("OR START SOMETHING NEW"), C.space(1, px(28)),
                self:startNewCards(s.start_new),
            }
        end)
    end

    if #s.recent > 0 then
        block(76, function()
            return VerticalGroup:new{
                align = "left",
                self:label("RECENT"), C.space(1, px(28)),
                self:recentRow(s.recent),
            }
        end)
    end
    return blocks, true
end

function Home:listHeaderBlock(space_before)
    return VerticalGroup:new{
        align = "left",
        C.space(1, px(space_before)),
        self:allBooksHeader(),
        C.space(1, px(18)),
    }
end

--- Work out which blocks go on which page. Heights are measured once.
function Home:buildColumn()
    local blocks = {}
    local y = 0
    local function add(build, h)
        if not h then
            local w = build()
            h = w:getSize().h
            w:free()
        end
        blocks[#blocks + 1] = { y = y, h = h, build = build }
        y = y + h
    end

    local builders, has_list = self:topBlocks()
    for _, build in ipairs(builders) do add(build) end
    if has_list and #self.sorted > 0 then
        local space = #builders > 1 and 88 or 48
        self.list_header_y = y + px(space)
        add(function() return self:listHeaderBlock(space) end)
        local row_h = px(Home.ROW_H) + px(Home.LINE)
        if self.entries then
            for i, e in ipairs(self.entries) do
                if e.folder then
                    add(function() return self:folderRow(e.folder, i) end, row_h)
                else
                    add(function() return self:bookRow(e.book, i) end, row_h)
                end
            end
        else
            for i = 1, #self.sorted do
                add(function() return self:bookRow(self.sorted[i], i) end, row_h)
            end
        end
        add(function() return C.hline(self:contentWidth(), px(Home.LINE), self.col.line) end, px(Home.LINE))
    end
    -- room at the end so the last book clears the "Back to top" button
    add(function() return C.space(1, px(220)) end, px(220))
    return blocks
end

function Home:layout()
    local keep_scroll = self.viewport and self.viewport.scroll or 0
    if self[1] then self[1]:free() end
    local status = self:statusBar()
    -- small gap so scrolled content never touches the status bar
    local view_top = px(Theme.margin_top) + status:getSize().h + px(12)
    self.view_top = view_top
    if not self.blocks then
        self.blocks = self:buildColumn()
        -- a new column starts at the top, unless asked to stay put (after deleting a book)
        keep_scroll = self._keep_scroll or 0
    end
    self._keep_scroll = nil
    self.viewport = Viewport:new{
        x = 0, y = view_top, w = self.dimen.w, h = self.dimen.h - view_top,
        content_x = px(Theme.margin_h),
        blocks = self.blocks,
        bg = self.col.bg,
    }
    self.viewport.scroll = -1
    self.viewport:scrollTo(keep_scroll)
    if self.viewport.scroll < 0 then self.viewport.scroll = 0; self.viewport:update() end

    self.chrome = OverlapGroup:new{ dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h } }
    local status_box = C.box(self.dimen.w, view_top, status, { bg = self.col.bg,
        pad_l = px(Theme.margin_h), pad_t = px(Theme.margin_top) })
    -- small grabber at the top edge: the quick panel pulls down from here
    local grabber = C.TopGrabber:new{ color = self.col.line,
        overlap_offset = { math.floor(self.dimen.w / 2) - px(64), px(14) } }
    self[1] = Layers:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h },
        OverlapGroup:new{ dimen = Geom:new{ w = self.dimen.w, h = view_top }, status_box, grabber },
        self.viewport,
        self.chrome,
    }
    self._status_box = status_box
    self.viewport.overlap_offset = { 0, view_top }
    self.status_box = self._status_box
    self:updateChrome()
end

-- Clock and battery ----------------------------------------------------------------
--
-- The home screen is painted once and then left alone, so the clock would freeze.
-- Redraw the status bar on every minute change, and right after waking up.

function Home:refreshStatus()
    if self.closed or not self.status_box then return end
    local old = self.status_box[1]
    self.status_box[1] = self:statusBar()
    if old then old:free() end
    UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.view_top })
end

function Home:scheduleClock()
    if not self._clock_tick then
        self._clock_tick = function()
            self:refreshStatus()
            self:scheduleClock()
        end
    end
    UIManager:unschedule(self._clock_tick)
    if self.closed then return end
    local sec = tonumber(os.date("%S")) or 0
    UIManager:scheduleIn(60 - sec + 0.2, self._clock_tick)
end

function Home:onResume()
    self:refreshStatus()
    self:scheduleClock()
end

-- Wi-Fi turned on or off: show or hide its icon.
function Home:onNetworkConnected()
    self:refreshStatus()
    require("mh/updater").checkSoon(require("mh/updater").HOME_EVERY,
        function(_, _, changed) if changed then self:rebuild() end end)
end
function Home:onNetworkDisconnected() self:refreshStatus() end
-- Charger plugged in or out: the bolt on the battery.
function Home:onCharging() self:refreshStatus() end
function Home:onNotCharging() self:refreshStatus() end

function Home:onSuspend()
    if self._clock_tick then UIManager:unschedule(self._clock_tick) end
end

-- Scrollbar and "Back to top": only once the user has scrolled.
function Home:updateChrome()
    local chrome = self.chrome
    for i = #chrome, 1, -1 do chrome[i] = nil end
    local vp = self.viewport
    if vp.scroll > 0 and vp:maxScroll() > 0 then
        table.insert(chrome, self:scrollbar())
    end
    if vp.scroll > vp.h * 0.6 then
        table.insert(chrome, self:backToTop())
    end
end

Home.BAR_TOP, Home.BAR_BOTTOM = 160, 48 -- design px

function Home:scrollbar()
    local vp = self.viewport
    local top, bottom = px(Home.BAR_TOP), px(Home.BAR_BOTTOM)
    local track_h = self.dimen.h - top - bottom
    local thumb_h = C.barThumb(track_h, vp)
    local y = math.floor((track_h - thumb_h) * vp.scroll / math.max(1, vp:maxScroll()))
    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = px(12), h = track_h },
        C.Rect:new{ w = px(6), h = track_h, color = Home.TRACK, radius = px(3), overlap_offset = { px(3), 0 } },
        C.Rect:new{ w = px(12), h = thumb_h, color = self.col.fg, radius = px(6), overlap_offset = { 0, y } },
    }
    bar.overlap_offset = { self.dimen.w - px(26) - px(12), top }
    return bar
end

function Home:backToTop()
    local label = C.text("↑  Back to top", "sans_bold", 36, self.col.fg)
    local w = label:getSize().w + 2 * px(44)
    local h = px(112)
    local btn = C.tappable(
        C.box(w, h, label, { bg = self.col.bg, border = px(4), border_color = self.col.fg,
            radius = math.floor(h / 2), halign = "center", valign = "center" }),
        function() self:scrollTo(0) end)
    btn.overlap_offset = { self.dimen.w - px(Theme.margin_h) - w, self.dimen.h - px(64) - h }
    return btn
end

--- Once the list is scrolled, a grey line separates the fixed status bar (as in Settings).
function Home:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.viewport and (self.viewport.scroll or 0) > 0 and self.view_top then
        local t = px(4)
        bb:paintRect(x, y + self.view_top - t, self.dimen.w, t, self.col.line)
    end
end

-- Scrolling ------------------------------------------------------------------------

Home.FLICK = 1.5 -- a quick swipe travels a bit further than the finger did

function Home:scrollTo(offset)
    if self.viewport:scrollTo(offset) then
        self:updateChrome()
        UIManager:setDirty(self, "ui")
    end
end

function Home:scrollBy(dy)
    self:scrollTo(self.viewport.scroll + dy)
end

-- A drag or flick down that starts on the status bar opens the quick panel.
Home.PULL_MIN = 150 -- design px the finger must travel (as on Settings and the other pages)

--- The strip along the top edge (around the grabber): a pull down from here opens the quick panel.
function Home.startsOnStatusBar(_, y)
    return y and y < px(require("mh/ui/page").EDGE)
end

-- Slow drag: remember how far the finger has moved, scroll once on release.
function Home:calm()
    return time.now() < self.calm_until
end

--- Drag the scrollbar: the list follows the finger (repainted at most every 0.15 s).
function Home:dragBar(y, final)
    self._bar_last = y
    local vp = self.viewport
    local top = px(Home.BAR_TOP)
    local track_h = self.dimen.h - top - px(Home.BAR_BOTTOM)
    local moved = vp:scrollTo(C.barOffset(y, top, track_h, vp))
    local now = time.now()
    if final or (moved and (not self._bar_paint or now - self._bar_paint > time.s(0.15))) then
        self._bar_paint = now
        self:updateChrome()
        UIManager:setDirty(self, final and "ui" or "fast")
    end
end

function Home:barReach(p)
    return self.viewport and self.viewport:maxScroll() > 0
        and C.onBar(p, self.dimen.w, self.view_top or px(Home.BAR_TOP), self.dimen.h - px(Home.BAR_BOTTOM))
end

function Home:onMHPan(_, ges)
    if not self._pan_dy and not self._bar_drag and ges and self:barReach(C.gestureStart(ges)) then
        self._bar_drag = true
    end
    if self._bar_drag then
        if ges and ges.pos then self:dragBar(ges.pos.y) end
        return true
    end
    if self._swallow or (not self._pan_dy and self:calm()) then
        self._swallow = true
        return true
    end
    if ges and ges.relative then
        if not self._pan_dy and ges.pos then self._pan_start_y = ges.pos.y - ges.relative.y end
        self._pan_dy = ges.relative.y
    end
    return true
end

function Home:onMHPanRelease(_, ges)
    if self._bar_drag then
        self._bar_drag = nil
        self:dragBar(ges and ges.pos and ges.pos.y or self._bar_last or 0, true)
        return true
    end
    if self._swallow then
        self._swallow = nil
        return true
    end
    if self._pan_dy then
        local dy, start = self._pan_dy, self._pan_start_y
        self._pan_dy, self._pan_start_y = nil, nil
        if self:startsOnStatusBar(start) and dy > px(Home.PULL_MIN) then
            self:showQuickPanel()
        else
            self:scrollBy(-dy)
        end
    end
    return true
end

-- Quick flick.
function Home:onMHSwipe(_, ges)
    if self._swallow or self:calm() then
        self._swallow = nil
        return true
    end
    self._pan_dy = nil
    if ges and (ges.direction == "north" or ges.direction == "south") and self:barReach(ges.pos) then
        -- a quick drag on the bar: jump to where the finger let go
        local e = C.swipeEnd(ges)
        if e then self:dragBar(e.y, true) end
        return true
    end
    local dir = ges and ges.direction
    if dir == "south" and ges.pos and self:startsOnStatusBar(ges.pos.y)
            and (ges.distance or 0) >= px(Home.PULL_MIN) then
        self:showQuickPanel()
        return true
    end
    local dist = (ges and ges.distance or 0) * Home.FLICK
    if dir == "north" then
        self:scrollBy(dist)
        return true
    elseif dir == "south" then
        self:scrollBy(-dist)
        return true
    end
end

-- Page-turn buttons move most of a screen.
function Home:onMHShot()
    return require("mh/screenshot").take(self.ui)
end

function Home:onMHNextPage() self:scrollBy(self.viewport.h * 0.85) return true end
function Home:onMHPrevPage() self:scrollBy(-self.viewport.h * 0.85) return true end

function Home:showSortMenu()
    local anchor = self.sort_button and self.sort_button.dimen
    if not anchor then return end
    require("mh/ui/sortmenu"):new{
        anchor = anchor,
        sort_key = self.sort_key,
        sort_asc = self.sort_asc,
        col = self.col,
        on_rotate = function(mode) self:onSetRotationMode(mode) end,
        on_pick = function(key, asc)
            Prefs.set("sort_key", key)
            Prefs.set("sort_asc", asc)
            -- stay where we were, but no further down than the top of the list
            local prev = self.viewport.scroll
            self:resort()
            self:layout()
            if self.list_header_y then
                self.viewport:scrollTo(math.min(prev, self.list_header_y))
                self:updateChrome()
            end
            UIManager:setDirty(self, "ui")
        end,
    }:show()
end

--- A Kindle Store book KOReader can't read?
function Home:isKindleOnly(path)
    for _, b in ipairs(self.books or {}) do
        if b.path == path then return b.kindle_only end
    end
    return false
end

function Home.showKindleOnly()
    require("mh/ui/snackbar").show("Open this book in the Kindle reader", 3,
        "KOReader can’t read this Kindle Store format.")
end

-- Back from a book opened in a folder returns to that folder (and the folders
-- above it). `Home.return_folders` lists their paths, outermost first;
-- `Home.back_pressed` is set by the reading menu's ‹ Back (swiping up goes Home).
Home.return_folders = nil
Home.back_pressed = nil

function Home:openBook(path, from_folders)
    Home.return_folders = from_folders
    Home.back_pressed = nil
    if self:isKindleOnly(path) then Home.showKindleOnly() return end
    if self.opening then return end
    self.opening = true
    -- show at once that the tap landed: opening can take a few seconds
    require("mh/loadingbar").show(0.03, true)
    require("mh/ui/snackbar").paintNow("Opening book…")
    -- Leave the tap handler first: closing frees the widgets that are handling it.
    UIManager:nextTick(function() self:openBookNow(path) end)
end

--- Close Home and open the reader in one go, so Home is never drawn in between
--- (also used by Search, which shows the loading bar itself).
function Home:openBookNow(path)
    local DocumentRegistry = require("document/documentregistry")
    -- a check that fails must never stop the book from opening
    local ok_check, readable = pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        return lfs.attributes(path, "mode") == "file" and DocumentRegistry:hasProvider(path)
    end)
    if ok_check and not readable then
        -- stay on Home and say so (KOReader would leave us in its file browser)
        self.opening = nil
        require("mh/loadingbar").done()
        UIManager:setDirty(self, "ui")
        require("mh/ui/snackbar").show("Couldn’t open this book")
        return
    end
    self.opening = true
    self:onClose()
    local provider = DocumentRegistry:getProvider(path, true)
    local FileManager = require("apps/filemanager/filemanager")
    if provider and provider.order and FileManager.instance then
        -- handled by another app or plugin (archives, …): let KOReader decide
        FileManager.instance:openFile(path)
    else
        -- seamless = no "Opening file…" message in the middle of the screen
        require("apps/reader/readerui"):showReader(path, nil, true)
    end
end

function Home:openSearch()
    local ok, err = pcall(function()
        require("mh/ui/search"):new{
            books = self.books,
            cover_for = function(b, w, h, opts) return self:coverFor(b, w, h, opts) end,
            on_open = function(path) self:openBookNow(path) end,
            on_kindle_only = function() Home.showKindleOnly() end,
        }:show()
    end)
    if not ok then
        logger.err("MinimalHome: search could not open:", err)
        local fm = self.ui -- fall back to KOReader's file search
        if fm and fm.filesearcher then fm.filesearcher:onShowFileSearch() end
    end
end

--- Rebuild the whole column where it is (e.g. the update dot came or went).
function Home:rebuild()
    if self.closed then return end
    self._keep_scroll = self.viewport and self.viewport.scroll or 0
    self.blocks = nil
    self:layout()
    UIManager:setDirty(self, "ui")
end

function Home:openSettings()
    require("mh/ui/settings").openPage(self.ui, {
        on_close = function()
            if not self.closed then
                self:rebuild()
                self:refreshStatus()
                UIManager:setDirty(self, "full")
            end
        end,
        on_library_changed = function()
            if not self.closed then self:reload() end
        end,
    })
end

function Home:showQuickPanel()
    local ok, err = pcall(function() require("mh/ui/quickpanel"):new{
        ui = self.ui,
        on_settings = function() self:openSettings() end,
        -- Wi-Fi may have been switched: redraw the status bar icon
        on_close = function() if not self.closed then self:refreshStatus() end end,
    }:show() end)
    if not ok then logger.err("MinimalHome: quick panel failed:", err) end
end

-- The device was turned (accelerometer) or the user picked a rotation.
-- KOReader sends this to the top widget only, so we pass it on to the file
-- browser underneath and lay ourselves out again for the new screen size.
function Home:onSetRotationMode(mode)
    if mode == nil then return true end
    if self.ui and self.ui.onSetRotationMode then
        self.ui:onSetRotationMode(mode)
    elseif mode ~= Screen:getRotationMode() then
        Screen:setRotationMode(mode)
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.blocks = nil
    self:layout()
    UIManager:setDirty("all", "full")
    return true
end

function Home:onClose()
    if self.closed then return true end
    self.closed = true
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

function Home:onCloseWidget()
    self.closed = true
    if self._clock_tick then UIManager:unschedule(self._clock_tick) end
    if self[1] then self[1]:free() end
end

return Home
