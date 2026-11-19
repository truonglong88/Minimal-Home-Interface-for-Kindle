--[[--
"Finished" screen, shown in place of KOReader's end-of-book pop-up:
cover, title, a few numbers (reading time, days, pages, highlights), the book
to read next, and a way back to the library. The book is marked as finished.
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Library = require("mh/data/library")
local Model = require("mh/data/model")
local Theme = require("mh/theme")

local px = Theme.px

local Finished = InputContainer:extend{
    ui = nil, -- the ReaderUI of the book just finished
}

-- Numbers ------------------------------------------------------------------------------------

--- { time = seconds, days = n, pages = n, highlights = n } (fields may be nil).
function Finished.gatherStats(ui)
    local out = {}
    pcall(function()
        local st = ui.statistics
        if st and st.getStatsBookStatus then
            local s = st:getStatsBookStatus()
            if s then out.time, out.days = s.time, s.days end
            -- days since the first page was read, rather than days with reading
            if st.id_curr_book then
                local DataStorage = require("datastorage")
                local SQ3 = require("lua-ljsqlite3/init")
                local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
                local first = conn:rowexec(string.format(
                    "SELECT min(start_time) FROM page_stat WHERE id_book = %d;", st.id_curr_book))
                conn:close()
                first = tonumber(first)
                if first and first > 0 then
                    out.days = math.max(1, math.ceil((os.time() - first) / 86400))
                end
            end
        end
    end)
    pcall(function() out.pages = ui.document:getPageCount() end)
    pcall(function()
        local list = ui.annotation and ui.annotation.annotations
            or (ui.doc_settings and ui.doc_settings:readSetting("annotations")) or {}
        local n = 0
        for _, a in ipairs(list) do
            if a.drawer or a.pos1 then n = n + 1 end
        end
        out.highlights = n
    end)
    return out
end

local function shortDuration(s)
    if not s or s <= 0 then return "–" end
    local m = math.floor(s / 60 + 0.5)
    if m < 60 then return m .. "m" end
    local h = math.floor(m / 60)
    m = m % 60
    return m > 0 and string.format("%dh %dm", h, m) or (h .. "h")
end

-- Widget ----------------------------------------------------------------------------------

function Finished:init()
    self.covers_fullscreen = true
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.ges_events = {
        MHSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    local ui = self.ui
    local props = ui.doc_props or {}
    self.book = {
        path = ui.document and ui.document.file,
        title = props.display_title or props.title or "",
        authors = (props.authors or ""):gsub("\n", ", "),
    }
    self.stats = Finished.gatherStats(ui)
    local ok, nxt = pcall(Library.upNext, self.book.path)
    self.next = ok and nxt or nil
    self:build()
end

local function readerCover(ui)
    if ui.bookinfo and ui.bookinfo.getCoverImage then
        return ui.bookinfo:getCoverImage(ui.document)
    end
end

function Finished:cover(w, h)
    local bb
    pcall(function() bb = readerCover(self.ui) end)
    if not bb and self.book.path then bb = Library.getCover(self.book.path) end
    local book = { title = self.book.title, authors = self.book.authors }
    return C.cover(book, w, h, { colors = self.col, cover_bb = bb, border = px(3), radius = px(12),
        frame = self.col.line, style_index = 1, title_size = 40, author_size = 22 })
end

function Finished:statsRow(w)
    local s = self.stats
    local cells = {
        { shortDuration(s.time), "reading time" },
        { s.days and (s.days .. (s.days == 1 and " day" or " days")) or "–", "since you started" },
        { s.pages and tostring(s.pages) or "–", "pages" },
        { s.highlights and tostring(s.highlights) or "–", "highlights" },
    }
    local cw = math.floor(w / 4)
    local row = HorizontalGroup:new{ align = "center" }
    for i, c in ipairs(cells) do
        local cell = VerticalGroup:new{
            align = "center",
            C.text(c[1], "serif_bold", 54, self.col.fg, cw - px(16)),
            C.space(1, px(8)),
            C.text(c[2], "sans_medium", 28, self.col.muted, cw - px(16)),
        }
        if i > 1 then table.insert(row, C.Rect:new{ w = px(3), h = px(150), color = self.col.line }) end
        table.insert(row, C.box(cw - (i > 1 and px(3) or 0), px(150), cell, { halign = "center", valign = "center" }))
    end
    return VerticalGroup:new{
        align = "left",
        C.hline(w, px(3), self.col.line),
        row,
        C.hline(w, px(3), self.col.line),
    }
end

function Finished:upNextCard(w)
    local b = self.next
    if not b then return nil end
    local cover_w, cover_h = px(120), px(175)
    local text_w = w - 2 * px(28) - cover_w - px(36) - px(48) - px(24)
    local texts = VerticalGroup:new{
        align = "left",
        C.text(b.title, "serif_bold", 44, self.col.fg, text_w),
        C.space(1, px(10)),
        C.text(b.authors or "", "sans_medium", 32, self.col.muted, text_w),
    }
    if Model.isInProgress(b) and b.percent then
        table.insert(texts, C.space(1, px(14)))
        table.insert(texts, HorizontalGroup:new{
            align = "center",
            C.progress(px(300), px(12), b.percent, Theme.colors(false).line, self.col.fg, px(6)),
            C.space(px(20), 1),
            C.text(Model.percentInt(b) .. "%", "sans_bold", 30, self.col.muted),
        })
    end
    local cover = C.cover(b, cover_w, cover_h, { colors = self.col, compact = true, title_size = 24,
        border = px(2), radius = px(8), frame = self.col.line, style_index = 1,
        cover_bb = b.has_cover and Library.getCover(b.path) or nil })
    local inner = HorizontalGroup:new{
        align = "center",
        cover, C.space(px(36), 1), C.box(text_w, cover_h, texts, { valign = "center" }),
        C.space(px(24), 1), C.text("›", "sans_bold", 56, self.col.fg),
    }
    local card = C.box(w, cover_h + 2 * px(24), inner, { border = px(4), border_color = self.col.fg,
        radius = px(12), pad_l = px(28), valign = "center" })
    return VerticalGroup:new{
        align = "left",
        C.text("UP NEXT", "sans_bold", 32, self.col.muted),
        C.space(1, px(24)),
        C.tappable(card, function() self:openBook(b.path) end),
    }
end

function Finished:build()
    local W, H = self.dimen.w, self.dimen.h
    local margin = px(Theme.margin_h)
    local w = W - 2 * margin

    local status = C.statusBar(w, self.col, 36, true, true)
    local back = C.tappable(C.box(px(480), px(88), C.text("‹  Back", "sans_bold", 34, self.col.fg),
        { valign = "center" }), function() self:close() end)

    local hero = VerticalGroup:new{
        align = "center",
        C.text("FINISHED", "sans_bold", 32, self.col.muted),
        C.space(1, px(28)),
        self:cover(px(270), px(396)),
        C.space(1, px(28)),
        C.textbox(self.book.title, "serif_bold", 66, self.col.fg, w, 2, 0.1, "center"),
        C.space(1, px(24)),
        C.text(self.book.authors, "sans_medium", 38, self.col.muted, w),
    }
    local stats = self:statsRow(w)
    local upnext = self:upNextCard(w)
    local button = C.tappable(C.box(px(560), px(120), C.text("Back to library", "sans_bold", 40, self.col.bg),
        { bg = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() self:backToLibrary() end)

    local parts = { hero, stats }
    if upnext then table.insert(parts, upnext) end
    table.insert(parts, button)

    local top = px(Theme.margin_top) + status:getSize().h + px(28) + back:getSize().h + px(16)
    local bottom_pad = px(64)
    local used = 0
    for _, p in ipairs(parts) do used = used + p:getSize().h end
    local free = math.max(0, H - top - bottom_pad - used)
    local gap = math.floor(free / (#parts - 1))

    local column = VerticalGroup:new{ align = "center" }
    for i, p in ipairs(parts) do
        if i > 1 then table.insert(column, C.space(1, gap)) end
        table.insert(column, p)
    end

    self[1] = C.box(W, H, VerticalGroup:new{
        align = "left",
        status,
        C.space(1, px(28)),
        back,
        C.space(1, px(16)),
        C.box(w, column:getSize().h, column, { halign = "center" }),
    }, { bg = self.col.bg, pad_l = margin, pad_t = px(Theme.margin_top) })
end

-- Actions -----------------------------------------------------------------------------------

function Finished:show()
    UIManager:show(self, "full")
    return self
end

function Finished:close()
    if self.closed then return end
    self.closed = true
    if Finished.current == self then Finished.current = nil end
    UIManager:close(self, "full")
end

function Finished:onClose()
    self:close()
    return true
end

function Finished:onMHSwipe(_, ges)
    if ges and ges.direction == "east" then self:close() end
    return true
end

function Finished:backToLibrary()
    UIManager:nextTick(function()
        self:close()
        if self.ui and self.ui.handleEvent then
            local Event = require("ui/event")
            self.ui:handleEvent(Event:new("Home"))
        end
    end)
end

function Finished:openBook(path)
    require("mh/loadingbar").show(0.03, true)
    UIManager:nextTick(function()
        self:close()
        local ok, err = pcall(function()
            if self.ui and self.ui.switchDocument then
                self.ui:switchDocument(path, true)
            else
                require("apps/reader/readerui"):showReader(path, nil, true)
            end
        end)
        if not ok then logger.err("MinimalHome: could not open next book:", err) end
    end)
end

function Finished:onCloseWidget()
    self.closed = true
    if Finished.current == self then Finished.current = nil end
    if self[1] then self[1]:free() end
end

--- Show the Finished screen for the book open in `ui`, and mark it finished.
function Finished.showFor(ui)
    pcall(function()
        if ui.status and ui.status.markBook then
            local summary = ui.doc_settings:readSetting("summary") or {}
            if summary.status ~= "complete" then ui.status:markBook(true) end
        end
    end)
    if Finished.current and not Finished.current.closed then return true end -- already showing
    local ok, err = pcall(function() Finished.current = Finished:new{ ui = ui }:show() end)
    if not ok then
        logger.err("MinimalHome: could not show the Finished screen:", err)
        return false
    end
    return true
end

return Finished
