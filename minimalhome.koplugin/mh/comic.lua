--[[--
Comic mode (design: "Comics"): picture-only books (EPUB, MOBI, AZW3, FB2…)
read like a picture book. No clock, no status line, no margins; each picture
fills the screen, so one tap or page button turns one comic page.

Auto: the first time a book is opened, 10 pages spread evenly through it are
looked at (10 %, 20 % … 90 %, skipping the first and last 3 %). Seven or more
with (almost) no words → comic. Decided once per book and remembered.
The Font panel has Auto / On / Off for when the guess is wrong.

PDF and CBZ (page-based documents) already show one picture per page: untouched.
--]]

local Event = require("ui/event")
local logger = require("logger")

local Comic = {}

Comic.SAMPLES = 10
Comic.NEED = 7      -- picture-only pages out of SAMPLES
Comic.MAX_WORDS = 15 -- fewer words than this on a page: a picture page
Comic.MODES = { "auto", "on", "off" }

-- Pictures on their own page, nothing around them that could spill onto a second page.
Comic.CSS = [[
html, body, div, p, section, figure, span, a, svg {
    margin: 0 !important; padding: 0 !important; border: 0 !important;
    text-indent: 0 !important; line-height: 1 !important;
}
img, image {
    display: block !important; margin: 0 auto !important; padding: 0 !important;
}
]]

local function settings(ui) return ui and ui.doc_settings end

--- "auto", "on" or "off" for this book.
function Comic.mode(ui)
    local ds = settings(ui)
    local m = ds and ds:readSetting("minimalhome_comic_mode")
    if m == "on" or m == "off" then return m end
    return "auto"
end

--- What Auto decided for this book (nil before the book has been looked at).
function Comic.autoResult(ui)
    local ds = settings(ui)
    if not ds then return nil end
    return ds:readSetting("minimalhome_comic_auto")
end

function Comic.isOn(ui)
    local m = Comic.mode(ui)
    if m == "on" then return true end
    if m == "off" then return false end
    return Comic.autoResult(ui) == true
end

--- Count the words on page p.
local function wordsOnPage(doc, p, total)
    local a = doc:getPageXPointer(p)
    local b = p < total and doc:getPageXPointer(p + 1) or nil
    if not a then return 0 end
    local ok, text = pcall(doc.getTextFromXPointers, doc, a, b or a)
    if not ok or type(text) ~= "string" then return 0 end
    local n = 0
    for _ in text:gmatch("[%w\128-\255]+") do n = n + 1 end
    -- a page of prose has hundreds of words, a picture page none or a few in speech balloons
    return n
end

--- Look at 10 pages spread through the book. True when it is a comic.
function Comic.detect(ui)
    local doc = ui and ui.document
    if not (ui.rolling and doc and doc.getPageXPointer) then return false end
    local ok, total = pcall(doc.getPageCount, doc)
    if not ok or not total or total < 2 then return false end
    local pictures, looked = 0, 0
    local seen = {}
    for k = 0, Comic.SAMPLES - 1 do
        -- 5 %, 15 % … 95 %, kept between 3 % and 97 %
        local f = math.min(0.97, math.max(0.03, (k + 0.5) / Comic.SAMPLES))
        local p = math.max(1, math.min(total, math.floor(total * f + 0.5)))
        if not seen[p] then
            seen[p] = true
            looked = looked + 1
            if wordsOnPage(doc, p, total) < Comic.MAX_WORDS then pictures = pictures + 1 end
        end
    end
    local need = math.ceil(looked * Comic.NEED / Comic.SAMPLES)
    logger.info("MinimalHome: comic check:", pictures, "of", looked, "pages are pictures")
    return looked > 0 and pictures >= need
end

-- Pictures grow (or shrink) to fit the page, keeping their shape. KOReader turns
-- this off for every book; comic books get it back. 2 = any scale, 0 = fit the page.
local ZOOM = { "crengine.image.scaling.zoomin.block", "crengine.image.scaling.zoomout.block" }
local function setZoom(ui, on)
    local d = ui.document and ui.document._document
    if not d or not d.setIntProperty then return end
    for _, key in ipairs(ZOOM) do
        d:setIntProperty(key .. ".mode", on and 2 or 0)
        d:setIntProperty(key .. ".scale", on and 0 or 1)
    end
end
Comic.setZoom = setZoom

-- Blank pages: a picture that fills the page can leave an empty line behind it,
-- which crengine puts on a page of its own. After a page is drawn in comic mode,
-- look at the screen: nothing on it → go on in the same direction.
Comic.BLANK_GRID = 24     -- points across and down that are looked at
Comic.MAX_SKIPS = 3       -- blank pages in a row we pass over before stopping

--- True when the page area of bb has no ink at all (every sampled point white).
function Comic.isBlank(bb, x, y, w, h)
    if not (bb and bb.getPixel) then return false end
    local n = Comic.BLANK_GRID
    for i = 1, n do
        for j = 1, n do
            local px = x + math.floor((i - 0.5) * w / n)
            local py = y + math.floor((j - 0.5) * h / n)
            local ok, c = pcall(bb.getPixel, bb, px, py)
            if not ok or not c then return false end
            local v = c.getColor8 and c:getColor8().a or c.a
            if v == nil or v < 235 then return false end
        end
    end
    return true
end

local function hookBlankPages(ui)
    local view = ui.view
    if not view or view._minimalhome_blank_hook then return end
    view._minimalhome_blank_hook = true
    local orig = view.paintTo
    view.paintTo = function(self, bb, x, y)
        orig(self, bb, x, y)
        if not ui._minimalhome_comic or ui._minimalhome_skip_pending then return end
        local d = self.dimen or (self.visible_area)
        local w = d and d.w or bb:getWidth()
        local h = d and d.h or bb:getHeight()
        if not Comic.isBlank(bb, x or 0, y or 0, w, h) then
            ui._minimalhome_skips = 0
            return
        end
        local dir = ui._minimalhome_dir or 1
        local page = ui.document and ui.document.getCurrentPage and ui.document:getCurrentPage() or 1
        local total = ui.document and ui.document.getPageCount and ui.document:getPageCount() or 1
        if (dir > 0 and page >= total) or (dir < 0 and page <= 1) then return end
        if (ui._minimalhome_skips or 0) >= Comic.MAX_SKIPS then return end
        ui._minimalhome_skips = (ui._minimalhome_skips or 0) + 1
        ui._minimalhome_skip_pending = true
        require("ui/uimanager"):nextTick(function()
            ui._minimalhome_skip_pending = nil
            if ui._minimalhome_comic then ui:handleEvent(Event:new("GotoViewRel", dir)) end
        end)
    end
    -- remember which way the reader is going
    local last = nil
    local orig_update = view.onPageUpdate
    view.onPageUpdate = function(self, new_page, ...)
        if last and new_page and new_page ~= last then
            ui._minimalhome_dir = new_page > last and 1 or -1
        end
        last = new_page
        if orig_update then return orig_update(self, new_page, ...) end
    end
end
Comic.hookBlankPages = hookBlankPages

-- Our CSS goes after KOReader's style tweaks, for this book only.
local function hookCss(ui)
    local st = ui.styletweak
    if not st or st._minimalhome_comic_hook then return end
    local orig = st.getCssText
    st.getCssText = function(self, ...)
        local css = orig(self, ...) or ""
        if ui._minimalhome_comic then css = css .. "\n" .. Comic.CSS end
        return css
    end
    st._minimalhome_comic_hook = true
end

--- Show the book as a comic (on) or as a normal book (off).
function Comic.apply(ui, on)
    if not ui.rolling then return end
    on = on == true
    if ui._minimalhome_comic == on then return end
    if ui._minimalhome_comic == nil and not on then return end -- a normal book, as it is
    ui._minimalhome_comic = on
    local ok, err = pcall(function()
        hookCss(ui)
        hookBlankPages(ui)
        setZoom(ui, on)
        local footer = ui.view and ui.view.footer
        if footer and footer.applyFooterMode and footer.mode_list then
            if on then
                footer:applyFooterMode(footer.mode_list.off)
            else
                footer:applyFooterMode(G_reader_settings:readSetting("reader_footer_mode") or 1)
            end
        end
        local M = require("mh/reader").MARGINS
        local h, t, b = M.h, M.t, M.b
        if on then h, t, b = 0, 0, 0 end
        local conf = ui.document.configurable
        if conf then conf.h_page_margins, conf.t_page_margin, conf.b_page_margin = { h, h }, t, b end
        ui:handleEvent(Event:new("ApplyStyleSheet"))
        ui:handleEvent(Event:new("SetPageMargins", { h, t, h, b }))
    end)
    if not ok then logger.warn("MinimalHome: comic mode:", err) end
end

--- As the book opens (plugin init, before KOReader reads the book's settings):
--- a book already known to be a comic gets its CSS and a hidden status line in
--- the same layout pass as everything else, so it opens no slower than before.
function Comic.prepare(ui)
    if not ui or not ui.rolling or not settings(ui) then return end
    pcall(hookCss, ui)
    pcall(hookBlankPages, ui)
    if not Comic.isOn(ui) then return end
    ui._minimalhome_comic = true
    pcall(setZoom, ui, true)
    pcall(function()
        local footer = ui.view and ui.view.footer
        if footer and footer.applyFooterMode and footer.mode_list then
            footer:applyFooterMode(footer.mode_list.off)
        end
    end)
end

--- A book has opened: decide (once) and show it the right way.
function Comic.onReady(ui)
    if not ui or not ui.rolling or not settings(ui) then return end
    if Comic.mode(ui) == "auto" and Comic.autoResult(ui) == nil then
        local ok, res = pcall(Comic.detect, ui)
        settings(ui):saveSetting("minimalhome_comic_auto", ok and res == true)
    end
    local on = Comic.isOn(ui)
    -- a normal book needs nothing done: it is already styled
    if on then Comic.apply(ui, true) end
end

--- Font panel: Auto / On / Off.
function Comic.setMode(ui, mode)
    local ds = settings(ui)
    if not ds then return end
    ds:saveSetting("minimalhome_comic_mode", mode ~= "auto" and mode or nil)
    if mode == "auto" and Comic.autoResult(ui) == nil then
        local ok, res = pcall(Comic.detect, ui)
        ds:saveSetting("minimalhome_comic_auto", ok and res == true)
    end
    Comic.apply(ui, Comic.isOn(ui))
end

--- The line above the Font panel's buttons.
function Comic.hint(ui)
    local m = Comic.mode(ui)
    if m == "on" then return "Pictures fill the screen" end
    if m == "off" then return "Always as a text book" end
    return Comic.autoResult(ui) and "Auto: comic" or "Auto: text book"
end

return Comic
