--[[--
The reading menu shown when the page is tapped (design: "Reading – after
tapping the screen").

Top bar:    status · ‹ Library · title · bookmark
Bottom bar: Page X of Y · progress (tap or drag) · % · Contents · Go to page · Text
(the light is in the quick panel: swipe down from the top)

Tapping the page area between the bars closes it. KOReader's own menus stay
reachable by swiping down from the top edge or up from the bottom edge.
--]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Theme = require("mh/theme")
local px = Theme.px

-- Small drawn icons -----------------------------------------------------------

-- Bookmark ribbon, outlined or filled.
local Ribbon = Widget:extend{ size = 40, filled = false, fg = nil, bg = nil }
function Ribbon:getSize() return Geom:new{ w = self.size, h = self.size } end
local function paintRibbon(bb, x, y, w, h, color)
    local body = math.floor(h * 0.72)
    for row = 0, h - 1 do
        if row < body then
            bb:paintRect(x, y + row, w, 1, color)
        else
            local d = math.floor((row - body) / math.max(1, h - body) * w / 2)
            bb:paintRect(x, y + row, math.max(0, math.floor(w / 2) - d), 1, color)
            bb:paintRect(x + math.ceil(w / 2) + d, y + row, math.max(0, w - math.ceil(w / 2) - d), 1, color)
        end
    end
end
function Ribbon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local w, h = math.floor(self.size * 0.55), math.floor(self.size * 0.82)
    local ox, oy = x + math.floor((self.size - w) / 2), y + math.floor((self.size - h) / 2)
    paintRibbon(bb, ox, oy, w, h, self.fg)
    if not self.filled then
        local t = math.max(2, math.floor(self.size / 14))
        paintRibbon(bb, ox + t, oy + t, w - 2 * t, h - 3 * t, self.bg)
    end
end

-- Table of contents: three dots and lines.
local ListIcon = Widget:extend{ size = 44, fg = nil }
function ListIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function ListIcon:paintTo(bb, x, y)
    local u = self.size / 24
    local t = math.max(2, math.floor(2 * u + 0.5))
    for _, yy in ipairs({ 6, 12, 18 }) do
        bb:paintRoundedRect(math.floor(x + 3.5 * u), math.floor(y + yy * u - t / 2), t + 1, t + 1, self.fg, t)
        bb:paintRect(math.floor(x + 9 * u), math.floor(y + yy * u - t / 2), math.floor(11 * u), t, self.fg)
    end
end

-- The overlay ---------------------------------------------------------------------

local ReaderMenu = InputContainer:extend{
    ui = nil,
}

function ReaderMenu:init()
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        MHTapPage = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        MHShot = { GestureRange:new{ ges = "hold", range = function()
            return self.top_rect or self.dimen
        end } },
        MHPan = { GestureRange:new{ ges = "pan", range = function() return self.dimen end } },
        MHPanRelease = { GestureRange:new{ ges = "pan_release", range = function() return self.dimen end } },
        MHSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
end

ReaderMenu.EDGE = 4 -- grey line along the inner edge of each bar, design px

function ReaderMenu:currentPage()
    local ok, page = pcall(function() return self.ui:getCurrentPage() end)
    return ok and page or 1
end

function ReaderMenu:build()
    local W = self.dimen.w
    local col = self.col
    local margin = px(88)
    local inner = W - 2 * margin

    -- top bar
    local props = self.ui.doc_props or {}
    local title = props.display_title or props.title or ""

    local back = C.tappable(C.box(px(240), px(104), C.text("‹  Back", "sans_bold", 34, col.fg), { valign = "center" }),
        function() self:close() self.ui:handleEvent(Event:new("Home")) end)

    local bookmarked = false
    if self.ui.bookmark and self.ui.bookmark.isPageBookmarked then
        local ok, res = pcall(self.ui.bookmark.isPageBookmarked, self.ui.bookmark)
        bookmarked = ok and res or false
    end
    local mark = C.tappable(C.box(px(104), px(104),
        Ribbon:new{ size = px(50), filled = bookmarked, fg = col.fg, bg = col.bg }, { halign = "center", valign = "center" }),
        function()
            if self.ui.bookmark then self.ui.bookmark:onToggleBookmark() end
            self:rebuild()
        end)
    local right = HorizontalGroup:new{ align = "center", mark }
    local center_w = inner - 2 * math.max(px(240), right:getSize().w) - 2 * px(16)
    local center = C.text(title, "serif_bold", 40, col.fg, center_w)
    local top_row = OverlapGroup:new{
        dimen = Geom:new{ w = inner, h = px(104) },
        back,
        C.box(center:getSize().w, px(104), center, { valign = "center", overlap_align = "center" }),
        C.box(right:getSize().w, px(104), right, { valign = "center", overlap_align = "right" }),
    }
    local top_content = VerticalGroup:new{
        align = "left",
        C.statusBar(inner, col, 36, true, true), -- as on Home: size, Wi-Fi, battery
        C.space(1, px(20)),
        top_row,
    }
    local top_h = px(32) + top_content:getSize().h + px(28)
    self.top = C.box(W, top_h, top_content, { bg = col.bg, pad_l = margin, pad_t = px(32) })
    self.top_rect = Geom:new{ x = 0, y = 0, w = W, h = top_h + px(ReaderMenu.EDGE) }

    -- bottom bar
    local total = 1
    pcall(function() total = self.ui.document:getPageCount() end)
    self.total = total
    -- while the knob is dragged, show the page it would go to
    local page = self._preview_page or self:currentPage()
    local ratio = total > 0 and page / total or 0
    local left_t = C.text(string.format("Page %d of %d", page, total), "sans_medium", 32, col.fg)
    local pct_t = C.text(math.floor(ratio * 100 + 0.5) .. "%", "sans_bold", 32, col.muted)
    -- "Page X of Y" … "N%" on one line, then ‹ slider ›
    local pct_box = C.box(pct_t:getSize().w, left_t:getSize().h, pct_t, { valign = "center" })
    pct_box.overlap_align = "right"
    local label_row = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = left_t:getSize().h }, left_t, pct_box }
    local btn = px(88)
    local grey = require("ffi/blitbuffer").gray(0.2)
    local first, last = page <= 1, page >= total
    local prev = C.roundButton(btn, C.Chevron:new{ size = px(40), color = first and grey or col.fg }, col, first,
        function() UIManager:nextTick(function() self:step(-1) end) end)
    local next_ = C.roundButton(btn, C.Chevron:new{ size = px(40), color = last and grey or col.fg, right = true }, col, last,
        function() UIManager:nextTick(function() self:step(1) end) end)
    local track_w = inner - 2 * btn - 2 * px(32)
    local knob = px(44)
    local bar_h = px(14)
    local filled = math.floor(track_w * ratio)
    local track = OverlapGroup:new{
        dimen = Geom:new{ w = track_w, h = knob },
        C.Rect:new{ w = track_w, h = bar_h, color = Theme.colors(false).line, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.Rect:new{ w = filled, h = bar_h, color = col.fg, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.box(knob, knob, C.space(1, 1), { bg = col.bg, border = px(5), border_color = col.fg,
            radius = math.floor(knob / 2), overlap_offset = { math.max(0, math.min(track_w - knob, filled - math.floor(knob / 2))), 0 } }),
    }
    local track_tap = C.tappable(track, nil)
    self._track = track_tap
    track_tap.callback = function()
        local ges = self._last_tap
        if ges then self:goToX(ges.pos.x) end
    end
    local progress_row = VerticalGroup:new{
        align = "left",
        label_row,
        C.space(1, px(20)),
        HorizontalGroup:new{ align = "center", prev, C.space(px(32), 1), track_tap, C.space(px(32), 1), next_ },
    }

    local tools = {
        { label = "Contents", icon = ListIcon:new{ size = px(52), fg = col.fg },
          act = function() self:openContents() end },
        { label = "Go to page", icon = C.text("⇥", "sans_bold", 52, col.fg),
          act = function() self:openGoTo() end },
        { label = "Text", icon = C.text("Aa", "serif_bold", 48, col.fg),
          act = function() self:openTextSettings() end },
    }
    local tool_w = math.floor(inner / #tools)
    local tool_row = HorizontalGroup:new{ align = "top" }
    for _, t in ipairs(tools) do
        local cell = VerticalGroup:new{
            align = "center",
            C.box(px(56), px(56), t.icon, { halign = "center", valign = "center" }),
            C.space(1, px(12)),
            C.text(t.label, "sans_medium", 30, col.fg),
        }
        table.insert(tool_row, C.tappable(C.box(tool_w, px(144), cell, { halign = "center", valign = "center" }),
            function() self:close() t.act() end))
    end

    local bottom_content = VerticalGroup:new{
        align = "left",
        progress_row,
        C.space(1, px(32)),
        C.hline(inner, px(3), col.line),
        C.space(1, px(14)),
        tool_row,
    }
    local bottom_h = px(40) + bottom_content:getSize().h + px(44)
    self.bottom = C.box(W, bottom_h, bottom_content, { bg = col.bg, pad_l = margin, pad_t = px(40) })
    local edge = px(ReaderMenu.EDGE)
    self.bottom_rect = Geom:new{ x = 0, y = self.dimen.h - bottom_h - edge, w = W, h = bottom_h + edge }

    -- children receive taps; they are painted by paintTo below
    self[1] = self.top
    self[2] = self.bottom
end

function ReaderMenu:rebuild()
    if self[1] then self[1]:free() end
    if self[2] then self[2]:free() end
    self:build()
    UIManager:setDirty(self, "ui", self.top_rect)
end

-- Page slider: tap, drag or flick along the track ------------------------------------

function ReaderMenu:pageAtX(x)
    local d = self._track_rect
    if not d then return nil end
    local r = math.max(0, math.min(1, (x - d.x) / d.w))
    return math.max(1, math.min(self.total or 1, math.floor(r * (self.total or 1) + 0.5)))
end

--- Go to the page under x. The menu stays open (both bars) on the new page.
function ReaderMenu:goToX(x)
    local page = self:pageAtX(x)
    if not page then return end
    self._preview_page = nil
    self.ui:handleEvent(Event:new("GotoPage", page))
    -- the reader repaints the page underneath; then redraw our bars for it
    UIManager:nextTick(function()
        if self.closed then return end
        self:rebuild()
        UIManager:setDirty(self, "ui", self.bottom_rect)
    end)
end

--- ‹ / ›: one page back or forward; the menu stays open on the new page.
function ReaderMenu:step(delta)
    if self.closed then return end
    local page = self:currentPage()
    if (delta < 0 and page <= 1) or (delta > 0 and page >= (self.total or 1)) then return end
    self._preview_page = nil
    self.ui:handleEvent(Event:new("GotoViewRel", delta))
    UIManager:nextTick(function()
        if self.closed then return end
        self:rebuild()
        UIManager:setDirty(self, "ui", self.bottom_rect)
    end)
end

function ReaderMenu:onTrack(pos)
    local d = self._track_rect
    return d and pos and pos.x >= d.x - px(30) and pos.x <= d.x + d.w + px(30)
        and pos.y >= d.y - px(36) and pos.y <= d.y + d.h + px(36)
end

--- Redraw only the bottom bar (knob and "Page X of Y") while dragging.
function ReaderMenu:previewAtX(x)
    local page = self:pageAtX(x)
    if not page or page == self._preview_page then return end
    self._preview_page = page
    if self[2] then self[2]:free() end
    if self[1] then self[1]:free() end
    self:build()
    -- "ui", not "fast": the fast waveform flashes the grey track black
    UIManager:setDirty(self, "ui", self.bottom_rect)
end

--- Pull down from the top edge: quick panel. Pull up from the bottom edge: Home.
--- Same rule as on the page (Reader.edgePull): from the edge strip, 150 px.
function ReaderMenu:pullGesture(ges, direction)
    local Reader = require("mh/reader")
    local pull = Reader.edgePull(ges, direction == "south" and "top" or "bottom")
    if pull == "wait" then return true end
    if pull ~= "go" or self.closed then return false end
    self:close()
    if direction == "south" then
        UIManager:nextTick(function() Reader.pullDown(self.ui, { direction = "south" }, true) end)
    else
        UIManager:nextTick(function() Reader.pullUp(self.ui, { direction = "north" }, true) end)
    end
    return true
end

function ReaderMenu:onMHPan(_, ges)
    if not ges then return false end
    if self._dragging or self:onTrack(ges.start_pos) then
        self._dragging = true
        self:previewAtX(ges.pos.x)
        return true
    end
    -- a slow drag down from the top / up from the bottom
    local dy = ges.relative and ges.relative.y or 0
    if ges.start_pos and math.abs(dy) > px(60) then
        return self:pullGesture(ges, dy > 0 and "south" or "north")
    end
    return false
end

function ReaderMenu:onMHPanRelease(_, ges)
    if not self._dragging then return false end
    self._dragging = nil
    if ges and ges.pos then self:goToX(ges.pos.x) end
    return true
end

function ReaderMenu:onMHSwipe(_, ges)
    if ges and (ges.direction == "east" or ges.direction == "west") and self:onTrack(ges.pos) then
        self:goToX(ges.pos.x + (ges.direction == "east" and 1 or -1) * (ges.distance or 0))
        return true
    end
    if ges and ges.pos and (ges.direction == "south" or ges.direction == "north") then
        return self:pullGesture(ges, ges.direction)
    end
    return false
end

function ReaderMenu:paintTo(bb)
    local W = self.dimen.w
    self.top:paintTo(bb, 0, 0)
    local edge = px(ReaderMenu.EDGE)
    bb:paintRect(0, self.top_rect.h - edge, W, edge, self.col.line)
    bb:paintRect(0, self.bottom_rect.y, W, edge, self.col.line)
    -- grabber at the top centre (the quick panel opens with a swipe down)
    local gw, gh = px(120), px(8)
    bb:paintRoundedRect(math.floor((W - gw) / 2), px(18), gw, gh, self.col.line, math.floor(gh / 2))
    self.bottom:paintTo(bb, 0, self.bottom_rect.y + edge)
    -- home bar at the bottom centre, like the grabber at the top
    local hw, hh = px(120), px(8)
    bb:paintRoundedRect(math.floor((W - hw) / 2), self.dimen.h - px(18) - hh, hw, hh, self.col.line, math.floor(hh / 2))
    if self._track and self._track.dimen then self._track_rect = self._track.dimen:copy() end
end

-- Remember where a tap landed (the progress track needs the x position);
-- children (the bars) get the tap first, anything left over was on the page.
function ReaderMenu:handleEvent(event)
    if event.handler == "onGesture" and event.args and event.args[1] and event.args[1].ges == "tap" then
        self._last_tap = event.args[1]
    end
    return InputContainer.handleEvent(self, event)
end

function ReaderMenu:onMHTapPage(_, ges)
    local p = ges and ges.pos
    local function inside(r)
        return p and p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
    end
    if not inside(self.top_rect) and not inside(self.bottom_rect) then
        self:close()
    end
    return true
end

--- Our own pages, with KOReader's as the fallback if anything goes wrong.
function ReaderMenu:openContents()
    local ok, err = pcall(function() require("mh/ui/contents"):new{ ui = self.ui }:show() end)
    if not ok then
        logger.warn("MinimalHome: contents:", err)
        self.ui:handleEvent(Event:new("ShowToc"))
    end
end

function ReaderMenu:openGoTo()
    local ok, err = pcall(function() require("mh/ui/gotopage"):new{ ui = self.ui }:show() end)
    if not ok then
        logger.warn("MinimalHome: go to page:", err)
        self.ui:handleEvent(Event:new("ShowGotoDialog"))
    end
end

function ReaderMenu:openTextSettings()
    local ok, err = pcall(function() require("mh/ui/fontpanel"):new{ ui = self.ui }:show() end)
    if ok then return end
    logger.warn("MinimalHome: font panel:", err)
    local config = self.ui.config
    if not config then return end
    -- open KOReader's typography panel on its "Aa" tab
    for i, opt in ipairs(config.options or {}) do
        if opt.icon == "appbar.textsize" then config.last_panel_index = i end
    end
    config:onShowConfigMenu()
end

-- Turning the device closes the menu and hands the rotation to the reader.
function ReaderMenu:onMHShot()
    return require("mh/screenshot").take(self.ui)
end

function ReaderMenu:onSetRotationMode(mode)
    self:close()
    self.ui:handleEvent(Event:new("SetRotationMode", mode))
    return true
end

function ReaderMenu:onSuspend() self:close() end

function ReaderMenu:onClose()
    self:close()
    return true
end

function ReaderMenu:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui")
end

function ReaderMenu:show()
    UIManager:show(self, "ui")
end

return ReaderMenu
