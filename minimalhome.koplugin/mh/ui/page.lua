--[[--
A full-screen page with the status bar on top and one scrolling column below
(the same scrolling as the home screen: by swipe distance, redrawn on lift).
Settings and Screensaver are built on it.

Subclasses implement `blocks()`, returning a list of build functions; each one
returns a widget for one block of the column. Call `refresh()` after a change.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local C = require("mh/ui/components")
local Theme = require("mh/theme")
local Viewport = require("mh/ui/viewport")

local px = Theme.px

local Page = InputContainer:extend{
    is_mh_page = true,
    swipe_home = false, -- swipe up from the bottom edge goes back to Home (Settings and its pages)
    title = "",
    back_label = "Back",
    on_close = nil,
}

Page.FLICK = 1.5

function Page:init()
    self.covers_fullscreen = true
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        self.ges_events = {
            MHSwipe = { GestureRange:new{ ges = "swipe", range = range } },
            MHPan = { GestureRange:new{ ges = "pan", range = range } },
            MHPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            MHNextPage = { { Device.input.group.PgFwd } },
            MHPrevPage = { { Device.input.group.PgBack } },
            Close = { { Device.input.group.Back } },
        }
    end
    self:layout()
end

function Page:contentWidth()
    return self.dimen.w - 2 * px(Theme.margin_h)
end

-- Shared pieces -----------------------------------------------------------------------

function Page:sectionLabel(text)
    return C.text(text, "sans_bold", 32, self.col.muted)
end

--- "‹ Back": stays put under the status bar while the page scrolls.
function Page:backButton()
    return C.tappable(
        C.box(px(360), px(88), C.text("‹  " .. self.back_label, "sans_bold", 34, self.col.fg), { valign = "center" }),
        function() self:close() end)
end

--- The big title (scrolls with the page).
function Page:headerBlock()
    local g = VerticalGroup:new{
        align = "left",
        C.space(1, px(8)),
        C.text(self.title, "serif_bold", 84, self.col.fg, self:contentWidth()),
    }
    if self.subtitle then
        table.insert(g, C.space(1, px(8)))
        table.insert(g, C.textbox(self.subtitle, "sans_medium", 34, self.col.muted, self:contentWidth(), 3, 0.25))
    end
    return g
end

--- On/off switch as in the design: outlined pill, filled when on.
function Page:toggle(on)
    return C.toggle(on, self.col)
end

--- One settings row: label (+ sub-line) on the left; a switch or a value with "›" on the right.
--- opts = { label, sub, toggle = bool|nil, value = string|nil, action = fn, enabled = bool }
function Page:row(opts)
    local w = self:contentWidth()
    local right
    if opts.toggle ~= nil then
        right = self:toggle(opts.toggle)
    else
        right = HorizontalGroup:new{
            align = "center",
            C.text(opts.value or "", "sans_medium", 34, self.col.muted, math.floor(w * 0.4)),
            C.space(px(12), 1),
            C.text("›", "sans_bold", 44, self.col.muted),
        }
    end
    local text_w = w - right:getSize().w - px(32)
    local texts = VerticalGroup:new{
        align = "left",
        C.text(opts.label, "sans_bold", 38, opts.enabled == false and self.col.muted or self.col.fg, text_w),
    }
    if opts.sub and opts.sub ~= "" then
        table.insert(texts, C.space(1, px(6)))
        table.insert(texts, C.text(opts.sub, "sans_medium", 30, self.col.muted, text_w))
    end
    local h = math.max(px(128), texts:getSize().h + 2 * px(22))
    right.overlap_align = "right"
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        C.box(texts:getSize().w, h, texts, { valign = "center" }),
        C.box(right:getSize().w, h, right, { valign = "center", overlap_align = "right" }),
    }
    local g = VerticalGroup:new{ align = "left", C.hline(w, px(3), self.col.line) }
    table.insert(g, C.tappable(content, function()
        if opts.enabled == false or not opts.action then return end
        -- leave the tap handler before the page is rebuilt under it
        UIManager:nextTick(function() opts.action() end)
    end))
    return g
end

--- A section: label, rows, closing line.
function Page:section(label, rows, space_before)
    local w = self:contentWidth()
    local g = VerticalGroup:new{ align = "left", C.space(1, px(space_before or 88)),
        self:sectionLabel(label), C.space(1, px(20)) }
    for _, r in ipairs(rows) do table.insert(g, self:row(r)) end
    table.insert(g, C.hline(w, px(3), self.col.line))
    return g
end

--- A full-width outlined button.
function Page:button(label, w, action)
    return C.tappable(C.box(w, px(116), C.text(label, "sans_bold", 38, self.col.fg),
        { border = px(4), border_color = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(action) end)
end

-- Layout -------------------------------------------------------------------------------

function Page:blocks()
    return { function() return self:headerBlock() end }
end

function Page:buildColumn()
    local out, y = {}, 0
    for _, block in ipairs(self:blocks()) do
        local build, h
        if type(block) == "table" then
            -- { h = height, build = fn }: known height, built only when scrolled into view
            build, h = block.build, block.h
        else
            build = block
            local w = build()
            h = w:getSize().h
            w:free()
        end
        out[#out + 1] = { y = y, h = h, build = build }
        y = y + h
    end
    out[#out + 1] = { y = y, h = px(120), build = function() return C.space(1, px(120)) end }
    return out
end

function Page:layout()
    local keep = self.viewport and self.viewport.scroll or 0
    if self[1] then self[1]:free() end
    local status = C.statusBar(self:contentWidth(), self.col, 36, true, true)
    local back = self:backButton()
    local fixed = VerticalGroup:new{ align = "left", status, C.space(1, px(20)), back }
    local view_top = px(Theme.margin_top) + fixed:getSize().h + px(8)
    self.view_top = view_top
    self.viewport = Viewport:new{
        x = 0, y = view_top, w = self.dimen.w, h = self.dimen.h - view_top,
        content_x = px(Theme.margin_h), blocks = self:buildColumn(), bg = self.col.bg,
    }
    self.viewport.scroll = -1
    self.viewport:scrollTo(keep)
    if self.viewport.scroll < 0 then self.viewport.scroll = 0; self.viewport:update() end
    self.viewport.overlap_offset = { 0, view_top }
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h },
        C.box(self.dimen.w, view_top, fixed, { bg = self.col.bg,
            pad_l = px(Theme.margin_h), pad_t = px(Theme.margin_top) }),
        self.viewport,
    }
    -- taps go to the topmost layer first (Back to top floats over the list)
    self[1].propagateEvent = function(g, event)
        for i = #g, 1, -1 do
            if g[i]:handleEvent(event) then return true end
        end
        return false
    end
    self:updateChrome()
end

--- Scrollbar and "Back to top", once the page is scrolled (as on Home).
function Page:updateChrome()
    local layers = self[1]
    if not layers then return end
    for i = #layers, 3, -1 do table.remove(layers, i) end
    local vp = self.viewport
    if vp.scroll > 0 and vp:maxScroll() > 0 then
        local top, bottom = self.view_top, px(48)
        local track_h = self.dimen.h - top - bottom
        local thumb_h = math.max(px(100), math.floor(track_h * vp.h / vp:totalHeight()))
        local y = math.floor((track_h - thumb_h) * vp.scroll / math.max(1, vp:maxScroll()))
        local bar = OverlapGroup:new{
            dimen = Geom:new{ w = px(12), h = track_h },
            C.Rect:new{ w = px(6), h = track_h, color = Blitbuffer.gray(0.2), radius = px(3), overlap_offset = { px(3), 0 } },
            C.Rect:new{ w = px(12), h = thumb_h, color = self.col.fg, radius = px(6), overlap_offset = { 0, y } },
        }
        bar.overlap_offset = { self.dimen.w - px(26) - px(12), top }
        table.insert(layers, bar)
    end
    if self.back_to_top ~= false and vp.scroll > vp.h * 0.6 then
        local label = C.text("↑  Back to top", "sans_bold", 36, self.col.fg)
        local w = label:getSize().w + 2 * px(44)
        local h = px(112)
        local btn = C.tappable(C.box(w, h, label, { bg = self.col.bg, border = px(4), border_color = self.col.fg,
            radius = math.floor(h / 2), halign = "center", valign = "center" }),
            function() self:scrollBy(-self.viewport.scroll) end)
        btn.overlap_offset = { self.dimen.w - px(Theme.margin_h) - w, self.dimen.h - px(64) - h }
        table.insert(layers, btn)
    end
end

--- Once the column is scrolled, a grey line separates the fixed header.
function Page:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.viewport and (self.viewport.scroll or 0) > 0 and self.view_top then
        local t = px(4)
        bb:paintRect(x, y + self.view_top - t, self.dimen.w, t, self.col.line)
    end
    if self.swipe_home then
        -- grabbers: pull down from the top for the quick panel, swipe up from the bottom for Home
        local gw, gh = px(120), px(8)
        local gx = x + math.floor((self.dimen.w - gw) / 2)
        bb:paintRoundedRect(gx, y + px(18), gw, gh, self.col.line, math.floor(gh / 2))
        bb:paintRoundedRect(gx, y + self.dimen.h - px(18) - gh, gw, gh, self.col.line, math.floor(gh / 2))
    end
end

--- Rebuild after a setting changed; keeps the scroll position.
function Page:refresh()
    if self.closed then return end
    self:layout()
    UIManager:setDirty(self, "ui")
end

-- Scrolling ----------------------------------------------------------------------------

function Page:scrollBy(dy)
    if self.viewport:scrollTo(self.viewport.scroll + dy) then
        self:updateChrome()
        UIManager:setDirty(self, "ui")
    end
end

--- Bottom eighth of the screen: a swipe up from here goes Home.
function Page:fromBottomEdge(y)
    return self.swipe_home and y and y >= self.dimen.h - math.floor(self.dimen.h / 8)
end

function Page:onMHPan(_, ges)
    if ges and ges.relative then
        if not self._pan_dy and ges.pos then self._pan_start_y = ges.pos.y - ges.relative.y end
        self._pan_dy = ges.relative.y
    end
    return true
end

--- The status bar strip at the top: a pull down from here opens the quick panel.
function Page:fromTopEdge(y)
    return self.swipe_home and y and y < (self.view_top or px(140))
end

function Page:showQuickPanel()
    local ok, err = pcall(function()
        require("mh/ui/quickpanel"):new{
            ui = self.ui,
            on_settings = function() end, -- already here
            on_close = function() self:refresh() end,
        }:show()
    end)
    if not ok then require("logger").warn("MinimalHome: quick panel:", err) end
end

function Page:onMHPanRelease()
    if self._pan_dy then
        local dy, start = self._pan_dy, self._pan_start_y
        self._pan_dy, self._pan_start_y = nil, nil
        if self:fromTopEdge(start) and dy > px(100) then
            UIManager:nextTick(function() self:showQuickPanel() end)
        elseif self:fromBottomEdge(start) and dy < -px(80) then
            UIManager:nextTick(function() self:goHome() end)
        else
            self:scrollBy(-dy)
        end
    end
    return true
end

function Page:onMHSwipe(_, ges)
    self._pan_dy = nil
    local dir = ges and ges.direction
    local dist = (ges and ges.distance or 0) * Page.FLICK
    if dir == "south" and ges.pos and self:fromTopEdge(ges.pos.y) then
        UIManager:nextTick(function() self:showQuickPanel() end)
        return true
    end
    if dir == "north" and ges.pos and self:fromBottomEdge(ges.pos.y) then
        UIManager:nextTick(function() self:goHome() end)
        return true
    end
    if dir == "north" then self:scrollBy(dist) return true end
    if dir == "south" then self:scrollBy(-dist) return true end
    if dir == "east" then self:close() return true end -- swipe right: back
end

function Page:onMHNextPage() self:scrollBy(self.viewport.h * 0.85) return true end
function Page:onMHPrevPage() self:scrollBy(-self.viewport.h * 0.85) return true end

-- Open / close -------------------------------------------------------------------------

function Page:show()
    UIManager:show(self, "flashui")
    return self
end

function Page:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "flashui")
    if self.on_close then self.on_close() end
end

--- Close this page and every page under it (Settings › Default font › …);
--- from a book, leave the book too.
function Page:goHome()
    local pages = {}
    for _, win in ipairs(UIManager._window_stack or {}) do
        if win.widget and win.widget.is_mh_page and not win.widget.closed then pages[#pages + 1] = win.widget end
    end
    if #pages == 0 then pages = { self } end
    -- the pages on top would refresh the ones being closed: skip that
    for i = #pages, 2, -1 do pages[i].on_close = nil; pages[i]:close() end
    pages[1]:close()
    local ui = self.ui
    if ui and not ui.file_chooser and ui.handleEvent then
        ui:handleEvent(require("ui/event"):new("Home"))
    end
end

function Page:onClose()
    self:close()
    return true
end

function Page:onSetRotationMode(mode)
    if self.ui and self.ui.onSetRotationMode then self.ui:onSetRotationMode(mode) end
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self:refresh()
    UIManager:setDirty("all", "full")
    return true
end

function Page:onResume() self:refresh() end
function Page:onNetworkConnected() self:refresh() end
function Page:onNetworkDisconnected() self:refresh() end
function Page:onCharging() self:refresh() end
function Page:onNotCharging() self:refresh() end

function Page:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return Page
