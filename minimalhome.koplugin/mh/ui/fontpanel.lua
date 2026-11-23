--[[--
Font panel (design: "Reading › Text", titled "Font"), opened from the reading
menu. A sheet that slides up from the bottom:

  Font            Literata ›     (opens the font list, for this book)
  SIZE            −  ▬▬▬▬▬○────  +
  LINE SPACING    Tight · Normal · Loose
  MARGINS         Narrow · Normal · Wide
  ALIGNMENT       Left · Justify

Every change applies to the book being read, as KOReader's own panel does.
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
local logger = require("logger")
local Screen = Device.screen

local C = require("mh/ui/components")
local Theme = require("mh/theme")
local px = Theme.px

local FontPanel = InputContainer:extend{
    ui = nil,
}

FontPanel.SIZES = { min = 12, max = 44 }
FontPanel.SPACING = { { "Tight", 90 }, { "Normal", 100 }, { "Loose", 120 } }
FontPanel.MARGINS = { { "Narrow", 30 }, { "Normal", 46 }, { "Wide", 70 } }
FontPanel.LEFT_TWEAK = "text_align_most_left"

function FontPanel:init()
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local range = function() return self.dimen end
    self.ges_events = {
        MHTapOutside = { GestureRange:new{ ges = "tap", range = range } },
        MHSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

-- Current values ---------------------------------------------------------------------------

function FontPanel:fontSize()
    local f = self.ui.font
    return f and f.configurable and f.configurable.font_size or 22
end

function FontPanel:lineSpacing()
    local f = self.ui.font
    return f and f.configurable and f.configurable.line_spacing or 100
end

function FontPanel:margin()
    local m = self.ui.typeset and self.ui.typeset.unscaled_margins
    return m and m[1] or 46
end

function FontPanel:leftAligned()
    local st = self.ui.styletweak
    local ok, on = pcall(function() return st and st:isTweakEnabled(FontPanel.LEFT_TWEAK) end)
    return ok and on or false
end

function FontPanel:fontName()
    local f = self.ui.font
    return (f and f.font_face) or (self.ui.document and self.ui.document.font_face)
        or G_reader_settings:readSetting("cre_font") or ""
end

-- Changes ----------------------------------------------------------------------------------

--- Apply a change to the book, then redraw the panel over the new page.
function FontPanel:apply(fn)
    UIManager:nextTick(function()
        local ok, err = pcall(fn)
        if not ok then logger.warn("MinimalHome: font panel:", err) end
        self:rebuild()
    end)
end

function FontPanel:setSize(size)
    size = math.max(FontPanel.SIZES.min, math.min(FontPanel.SIZES.max, size))
    self:apply(function() self.ui:handleEvent(Event:new("SetFontSize", size)) end)
end

function FontPanel:setSpacing(v)
    self:apply(function() self.ui:handleEvent(Event:new("SetLineSpace", v)) end)
end

function FontPanel:setMargin(v)
    self:apply(function() self.ui:handleEvent(Event:new("SetPageHorizMargins", { v, v })) end)
end

function FontPanel:setLeft(left)
    if left == self:leftAligned() then return end
    self:apply(function() self.ui.styletweak:onToggleStyleTweak(FontPanel.LEFT_TWEAK, nil, true) end)
end

function FontPanel:openFonts()
    local Settings = require("mh/ui/settings")
    Settings.FontPicker:new{
        ui = self.ui,
        title = "Font",
        subtitle = "For this book.",
        current = self:fontName(),
        on_pick = function(face)
            self.ui:handleEvent(Event:new("SetFont", face))
        end,
        on_close = function() self:rebuild() end,
    }:show()
end

-- Pieces -----------------------------------------------------------------------------------

function FontPanel:label(text)
    return C.text(text, "sans_bold", 30, self.col.muted)
end

--- A row of options, the chosen one black (as the quick panel tiles).
function FontPanel:segments(w, options, chosen, pick)
    local gap = px(20)
    local bw = math.floor((w - (#options - 1) * gap) / #options)
    local row = HorizontalGroup:new{ align = "center" }
    for i, o in ipairs(options) do
        if i > 1 then table.insert(row, C.space(gap, 1)) end
        local on = o[2] == chosen
        local t = C.text(o[1], "sans_bold", 32, on and self.col.bg or self.col.muted)
        table.insert(row, C.tappable(C.box(bw, px(104), t, {
            bg = on and self.col.fg or self.col.bg, border = px(4), border_color = on and self.col.fg or self.col.line,
            radius = px(12), halign = "center", valign = "center" }), function() pick(o[2]) end))
    end
    return row
end

local function nearest(options, value)
    local best, dist = options[1][2], math.huge
    for _, o in ipairs(options) do
        local d = math.abs(o[2] - value)
        if d < dist then best, dist = o[2], d end
    end
    return best
end

function FontPanel:sizeRow(w)
    local size = self:fontSize()
    -- − and + drawn as bars (no glyph to go missing in a font)
    local len, thick = px(40), px(6)
    local function sign(plus)
        local g = OverlapGroup:new{ dimen = Geom:new{ w = len, h = len },
            C.Rect:new{ w = len, h = thick, color = self.col.fg, overlap_offset = { 0, math.floor((len - thick) / 2) } } }
        if plus then
            table.insert(g, C.Rect:new{ w = thick, h = len, color = self.col.fg,
                overlap_offset = { math.floor((len - thick) / 2), 0 } })
        end
        return g
    end
    local small = C.roundButton(px(100), sign(false), self.col, false, function() self:setSize(size - 1) end)
    local big = C.roundButton(px(100), sign(true), self.col, false, function() self:setSize(size + 1) end)
    local bar_w = w - 2 * px(100) - 2 * px(40)
    local ratio = (size - FontPanel.SIZES.min) / (FontPanel.SIZES.max - FontPanel.SIZES.min)
    local knob, bar_h = px(52), px(20)
    local filled = math.floor(bar_w * ratio)
    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = bar_w, h = knob },
        C.Rect:new{ w = bar_w, h = bar_h, color = Theme.colors(false).line, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.Rect:new{ w = filled, h = bar_h, color = self.col.fg, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.box(knob, knob, C.space(1, 1), { bg = self.col.bg, border = px(5), border_color = self.col.fg,
            radius = math.floor(knob / 2), overlap_offset = { math.max(0, math.min(bar_w - knob, filled - math.floor(knob / 2))), 0 } }),
    }
    local bar_tap = C.tappable(C.box(bar_w, px(100), bar, { valign = "center" }), nil)
    bar_tap.callback = function()
        local ges, d = self._last_tap, bar_tap.dimen
        if not (ges and d) then return end
        local r = math.max(0, math.min(1, (ges.pos.x - d.x) / d.w))
        self:setSize(math.floor(FontPanel.SIZES.min + r * (FontPanel.SIZES.max - FontPanel.SIZES.min) + 0.5))
    end
    return HorizontalGroup:new{ align = "center", small, C.space(px(40), 1), bar_tap, C.space(px(40), 1), big }
end

function FontPanel:build()
    local W = self.dimen.w
    local margin = px(Theme.margin_h)
    local w = W - 2 * margin
    -- title row: "Font" and the book's font, which opens the font list
    local name = self:fontName()
    local name_t = C.text(name ~= "" and (name .. "  ›") or "›", "sans_bold", 34, self.col.fg, math.floor(w / 2))
    local font_btn = C.tappable(C.box(name_t:getSize().w, px(88), name_t, { valign = "center" }),
        function() UIManager:nextTick(function() self:openFonts() end) end)
    font_btn.overlap_align = "right"
    local title = OverlapGroup:new{ dimen = Geom:new{ w = w, h = px(88) },
        C.box(math.floor(w / 2), px(88), C.text("Font", "serif_bold", 56, self.col.fg), { valign = "center" }),
        font_btn }
    local content = VerticalGroup:new{
        align = "left",
        title,
        C.space(1, px(52)), HorizontalGroup:new{ align = "center", self:label("SIZE · "),
            C.text(string.format("%g", self:fontSize()), "sans_bold", 30, self.col.fg) }, C.space(1, px(18)), self:sizeRow(w),
        C.space(1, px(52)), self:label("LINE SPACING"), C.space(1, px(18)),
        self:segments(w, FontPanel.SPACING, nearest(FontPanel.SPACING, self:lineSpacing()), function(v) self:setSpacing(v) end),
        C.space(1, px(52)), self:label("MARGINS"), C.space(1, px(18)),
        self:segments(w, FontPanel.MARGINS, nearest(FontPanel.MARGINS, self:margin()), function(v) self:setMargin(v) end),
        C.space(1, px(52)), self:label("ALIGNMENT"), C.space(1, px(18)),
        self:segments(w, { { "Left", 1 }, { "Justify", 0 } }, self:leftAligned() and 1 or 0,
            function(v) self:setLeft(v == 1) end),
    }
    if self.ui and self.ui.rolling then
        -- picture-only books fill the screen (mh/comic)
        local Comic = require("mh/comic")
        for _, wdg in ipairs({
            C.space(1, px(52)),
            HorizontalGroup:new{ align = "center", self:label("COMIC MODE · "),
                C.text(Comic.hint(self.ui), "sans_bold", 30, self.col.fg) },
            C.space(1, px(18)),
            self:segments(w, { { "Auto", "auto" }, { "On", "on" }, { "Off", "off" } }, Comic.mode(self.ui),
                function(v) UIManager:nextTick(function() Comic.setMode(self.ui, v); self:rebuild() end) end),
        }) do table.insert(content, wdg) end
    end
    local h = px(44) + content:getSize().h + px(64)
    self.panel_h = h
    self.panel_y = self.dimen.h - h
    self.panel = C.box(W, h, content, { bg = self.col.bg, pad_l = margin, pad_t = px(44) })
    self.panel.overlap_offset = { 0, self.panel_y }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = W, h = self.dimen.h }, self.panel }
end

function FontPanel:rebuild()
    if self.closed then return end
    if self[1] then self[1]:free() end
    self:build()
    UIManager:setDirty(self, "ui")
end

function FontPanel:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    local W = self.dimen.w
    -- grey line along the top edge and the grabber, as on the quick panel
    bb:paintRect(0, self.panel_y - px(4), W, px(4), self.col.line)
    local gw, gh = px(120), px(8)
    bb:paintRoundedRect(math.floor((W - gw) / 2), self.panel_y + px(18), gw, gh, self.col.line, math.floor(gh / 2))
end

-- Input ------------------------------------------------------------------------------------

function FontPanel:handleEvent(event)
    if event.handler == "onGesture" and event.args and event.args[1] and event.args[1].ges == "tap" then
        self._last_tap = event.args[1]
    end
    return InputContainer.handleEvent(self, event)
end

function FontPanel:onMHTapOutside(_, ges)
    if ges and ges.pos and ges.pos.y < self.panel_y - px(4) then self:close() end
    return true
end

function FontPanel:onMHSwipe(_, ges)
    if ges and ges.direction == "south" then self:close() end
    return true
end

function FontPanel:show()
    UIManager:show(self, "ui")
    return self
end

function FontPanel:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui")
end

function FontPanel:onSuspend() self:close() end

function FontPanel:onClose()
    self:close()
    return true
end

function FontPanel:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return FontPanel
