--[[--
Contents (design: "Reading › Contents").

A page like Settings: ‹ Back, the title and "Book · page X of Y", then every
chapter with its page number. The chapter being read is bold with a black
READING tag, and the page opens scrolled so that chapter is in view.
--]]

local Event = require("ui/event")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local C = require("mh/ui/components")
local Page = require("mh/ui/page")
local Theme = require("mh/theme")
local px = Theme.px

local Contents = Page:extend{
    title = "Contents",
    back_label = "Back",
    back_to_top = false,
    swipe_home = true, -- swipe up from the bottom edge: Home
    ui = nil,
}

-- Every row has the same height (titles wrap to two lines at most), so the
-- whole list is laid out without drawing it: rows are only built when they
-- scroll into view. A book with hundreds of chapters opens as fast as a short one.
Contents.ROW_H = 132
-- where the chapter being read sits when the page opens (from the top of the screen)
Contents.CURRENT_AT = 2 / 3

--- The table of contents as { title, page, depth, xpointer }.
function Contents.entries(ui)
    local toc = ui and ui.toc
    if not toc then return {} end
    pcall(function() if toc.fillToc then toc:fillToc() end end)
    local out = {}
    for _, e in ipairs(toc.toc or {}) do
        out[#out + 1] = { title = e.title or "", page = e.page, depth = e.depth or 1, xpointer = e.xpointer }
    end
    return out
end

--- Index of the chapter that contains `page` (the last one starting at or before it).
function Contents.currentIndex(entries, page)
    local cur
    for i, e in ipairs(entries) do
        if e.page and e.page <= page then cur = i end
    end
    return cur
end

function Contents:init()
    local ui = self.ui
    self.entries = Contents.entries(ui)
    require("logger").info("MinimalHome: contents:", #self.entries, "entries")
    local page, total = 1, 1
    pcall(function() page = ui:getCurrentPage() end)
    pcall(function() total = ui.document:getPageCount() end)
    self.page = page
    self.current = Contents.currentIndex(self.entries, page)
    local props = ui and ui.doc_props or {}
    local book = props.display_title or props.title or ""
    self.subtitle = (book ~= "" and (book .. " · ") or "") .. string.format("page %d of %d", page, total)
    Page.init(self)
    -- open with the chapter being read two thirds of the way down the screen
    if self.current_block and self.viewport.blocks[self.current_block] then
        local b = self.viewport.blocks[self.current_block]
        local target = math.floor(self.dimen.h * Contents.CURRENT_AT) - self.view_top
        self.viewport:scrollTo(b.y + math.floor(b.h / 2) - target)
        self:updateChrome()
    end
end

function Contents:row(e, is_current)
    local w = self:contentWidth()
    local indent = px(48) * math.max(0, (e.depth or 1) - 1)
    local sub = (e.depth or 1) > 1
    local right
    local page_t = C.text(tostring(e.page or ""), is_current and "sans_bold" or "sans_medium", 32,
        is_current and self.col.fg or self.col.muted)
    if is_current then
        local tag_t = C.text("READING", "sans_bold", 24, self.col.bg)
        local tag = C.box(tag_t:getSize().w + 2 * px(14), px(48), tag_t,
            { bg = self.col.fg, radius = px(8), halign = "center", valign = "center" })
        right = HorizontalGroup:new{ align = "center", tag, C.space(px(16), 1), page_t }
    else
        right = page_t
    end
    local text_w = w - indent - right:getSize().w - px(32)
    local kind = is_current and "sans_bold" or (sub and "sans_medium" or "sans_bold")
    local title = C.textbox(e.title, kind, sub and 34 or 36, self.col.fg, text_w, 2, 0.15)
    local h = px(Contents.ROW_H) - px(3)
    local content = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
        C.box(indent + text_w, h, title, { valign = "center", pad_l = indent }) }
    local r = C.box(right:getSize().w, h, right, { valign = "center" })
    r.overlap_align = "right"
    table.insert(content, r)
    return VerticalGroup:new{ align = "left",
        C.hline(w, px(3), self.col.line),
        C.tappable(content, function() UIManager:nextTick(function() self:go(e) end) end),
    }
end

function Contents:go(e)
    local ui = self.ui
    self:close()
    if e.xpointer and ui.rolling then
        ui:handleEvent(Event:new("GotoXPointer", e.xpointer, e.xpointer))
    elseif e.page then
        ui:handleEvent(Event:new("GotoPage", e.page))
    end
end

function Contents:blocks()
    local list = { function() return self:headerBlock() end }
    if #self.entries == 0 then
        table.insert(list, function()
            return VerticalGroup:new{ align = "left", C.space(1, px(72)),
                C.text("This book has no table of contents.", "sans_medium", 34, self.col.muted) }
        end)
        return list
    end
    table.insert(list, function() return C.space(1, px(56)) end)
    for i, e in ipairs(self.entries) do
        local is_current = i == self.current
        table.insert(list, { h = px(Contents.ROW_H), build = function() return self:row(e, is_current) end })
        if is_current then self.current_block = #list end
    end
    return list
end

--- A sleeping Kindle wakes on the page, not on the contents.
function Contents:onSuspend() self:close() end

return Contents
