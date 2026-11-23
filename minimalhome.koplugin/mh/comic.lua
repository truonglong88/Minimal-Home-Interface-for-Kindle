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
    if not Comic.isOn(ui) then return end
    ui._minimalhome_comic = true
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
