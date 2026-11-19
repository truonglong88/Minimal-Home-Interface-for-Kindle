--[[--
Small building blocks shared by every Minimal Home screen.

All sizes passed in here are already in device pixels (use Theme.px()).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- Fill any polygon (even-odd scanlines); points in pixels relative to x, y.
local function fillPolygon(bb, x, y, pts, color)
    local miny, maxy = math.huge, -math.huge
    for _, p in ipairs(pts) do miny = math.min(miny, p[2]); maxy = math.max(maxy, p[2]) end
    for row = math.floor(miny), math.ceil(maxy) do
        local yc = row + 0.5
        local xs = {}
        for i = 1, #pts do
            local a, b = pts[i], pts[i % #pts + 1]
            if (a[2] <= yc and b[2] > yc) or (b[2] <= yc and a[2] > yc) then
                xs[#xs + 1] = a[1] + (yc - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
            end
        end
        table.sort(xs)
        for i = 1, #xs - 1, 2 do
            local x0, x1 = math.floor(xs[i] + 0.5), math.floor(xs[i + 1] + 0.5)
            if x1 > x0 then bb:paintRect(x + x0, y + row, x1 - x0, 1, color) end
        end
    end
end
local Theme = require("mh/theme")

local C = {}

--[[ Box: a fixed-size rectangle with optional background, border and
     radius, painting its single child aligned inside it. ]]
local Box = WidgetContainer:extend{
    w = 0, h = 0,
    bg = nil, border = 0, border_color = Blitbuffer.COLOR_BLACK, radius = nil,
    pad_l = 0, pad_t = 0, pad_r = 0, pad_b = 0,
    halign = "left", valign = "top",
    -- With `radius` and `outer_bg`, the child is clipped to the rounded corners
    -- (needed for cover images, which are square): the corner pixels outside the
    -- curve are repainted with `outer_bg`, the colour of what lies behind the box.
    outer_bg = nil,
}

local function maskCorners(bb, x, y, w, h, r, color)
    for dy = 0, r - 1 do
        local fy = r - dy - 0.5
        local cut = math.ceil(r - math.sqrt(math.max(0, r * r - fy * fy)) - 0.5)
        if cut > 0 then
            bb:paintRect(x, y + dy, cut, 1, color)
            bb:paintRect(x + w - cut, y + dy, cut, 1, color)
            bb:paintRect(x, y + h - 1 - dy, cut, 1, color)
            bb:paintRect(x + w - cut, y + h - 1 - dy, cut, 1, color)
        end
    end
end

function Box:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function Box:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    if self.bg then
        bb:paintRoundedRect(x, y, self.w, self.h, self.bg, self.radius)
    end
    local clip = self.radius and self.radius > 0 and self.outer_bg
    if self.border > 0 and not clip then
        bb:paintBorder(x, y, self.w, self.h, self.border, self.border_color, self.radius, true)
    end
    local child = self[1]
    if not child then
        if clip and self.border > 0 then
            bb:paintBorder(x, y, self.w, self.h, self.border, self.border_color, self.radius, true)
        end
        return
    end
    if clip then
        self:paintChild(bb, x, y, child)
        maskCorners(bb, x, y, self.w, self.h, self.radius, self.outer_bg)
        if self.border > 0 then
            bb:paintBorder(x, y, self.w, self.h, self.border, self.border_color, self.radius, true)
        end
        return
    end
    self:paintChild(bb, x, y, child)
end

function Box:paintChild(bb, x, y, child)
    local cs = child:getSize()
    local inner_w = self.w - self.pad_l - self.pad_r
    local inner_h = self.h - self.pad_t - self.pad_b
    local cx, cy = x + self.pad_l, y + self.pad_t
    if self.halign == "center" then
        cx = cx + math.floor((inner_w - cs.w) / 2)
    elseif self.halign == "right" then
        cx = cx + inner_w - cs.w
    end
    if self.valign == "center" then
        cy = cy + math.floor((inner_h - cs.h) / 2)
    elseif self.valign == "bottom" then
        cy = cy + inner_h - cs.h
    end
    child:paintTo(bb, cx, cy)
end
C.Box = Box

--- Shorthand: C.box(w, h, child, opts)
function C.box(w, h, child, opts)
    local o = opts or {}
    o.w, o.h = w, h
    if o.pad then
        o.pad_l, o.pad_t, o.pad_r, o.pad_b = o.pad, o.pad, o.pad, o.pad
        o.pad = nil
    end
    o[1] = child
    return Box:new(o)
end

--[[ Rect: a plain filled rectangle (lines, bars, spacers). ]]
local Rect = Widget:extend{ w = 0, h = 0, color = nil, radius = nil }
function Rect:getSize() return Geom:new{ w = self.w, h = self.h } end
function Rect:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    if self.color then
        bb:paintRoundedRect(x, y, self.w, self.h, self.color, self.radius)
    end
end
function Rect.free() end
C.Rect = Rect

function C.hline(w, thickness, color)
    return Rect:new{ w = w, h = thickness, color = color }
end

function C.space(w, h)
    return Rect:new{ w = w or 0, h = h or 0 }
end

--[[ Tappable: makes any widget respond to tap / hold. ]]
local Tappable = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
}
function Tappable:init()
    local range = function() return self.dimen end
    self.ges_events = {
        MHTap = { GestureRange:new{ ges = "tap", range = range } },
    }
    if self.hold_callback then
        self.ges_events.MHHold = { GestureRange:new{ ges = "hold", range = range } }
    end
end
function Tappable:getSize()
    return self[1]:getSize()
end
function Tappable:onMHTap()
    if self.callback then self.callback() end
    return true
end
function Tappable:onMHHold()
    if self.hold_callback then self.hold_callback() end
    return true
end
C.Tappable = Tappable

function C.tappable(child, callback, hold_callback)
    return Tappable:new{ child, callback = callback, hold_callback = hold_callback }
end

--[[ Text helpers ]]

--- One line of text, truncated with an ellipsis at max_width.
function C.text(str, kind, size, color, max_width)
    return TextWidget:new{
        text = str or "",
        face = Theme.face(kind, size),
        fgcolor = color or Blitbuffer.COLOR_BLACK,
        max_width = max_width,
        padding = 0,
    }
end

--- Wrapped text limited to max_lines, with an ellipsis on overflow.
--- `bg` must match what is behind the text: TextBoxWidget renders its
--- background when it is created.
function C.textbox(str, kind, size, color, width, max_lines, line_height, alignment, bg)
    local function make(height)
        return TextBoxWidget:new{
            text = str or "",
            face = Theme.face(kind, size),
            fgcolor = color or Blitbuffer.COLOR_BLACK,
            bgcolor = bg or Blitbuffer.COLOR_WHITE,
            width = width,
            height = height,
            height_overflow_show_ellipsis = height ~= nil,
            line_height = line_height or 0.15,
            alignment = alignment or "left",
        }
    end
    local tb = make(nil)
    if max_lines and #tb.vertical_string_list > max_lines then
        local lh = tb:getLineHeight()
        tb:free()
        tb = make(lh * max_lines)
    end
    return tb
end

--- Textbox drawn on a colored background (e.g. a dark cover).
function C.textboxOn(bg, str, kind, size, color, width, max_lines, line_height, alignment)
    return C.textbox(str, kind, size, color, width, max_lines, line_height, alignment, bg)
end

--[[ Progress bar: a light track with a dark fill. ]]
--[[ Outlined bar: a black frame, filled black up to `ratio`. Reads better on e-ink
     than a light grey track. ]]
function C.progressBox(w, h, ratio, fg, bg, border)
    border = border or Theme.px(3)
    local inner_w, inner_h = w - 2 * border, h - 2 * border
    local filled = math.max(0, math.min(inner_w, math.floor(inner_w * (ratio or 0) + 0.5)))
    return C.box(w, h, Rect:new{ w = math.max(1, filled), h = inner_h, color = filled > 0 and fg or bg },
        { border = border, border_color = fg, radius = math.floor(h / 2), pad = border, bg = bg })
end

function C.progress(w, h, ratio, track, fill, radius)
    local filled = math.max(0, math.min(w, math.floor(w * (ratio or 0) + 0.5)))
    if radius and filled > 0 then filled = math.max(filled, 2 * radius) end
    local OverlapGroup = require("ui/widget/overlapgroup")
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        Rect:new{ w = w, h = h, color = track, radius = radius },
        Rect:new{ w = filled, h = h, color = fill, radius = radius },
    }
end

--[[ Icon from KOReader's icon set. ]]
function C.icon(name, size)
    return IconWidget:new{ icon = name, width = size, height = size }
end

--[[ Settings icon: three slider lines with knobs, as in the design. ]]
local Sliders = Widget:extend{ size = 40, fg = nil, bg = nil }
function Sliders:getSize() return Geom:new{ w = self.size, h = self.size } end
function Sliders:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local u = self.size / 24
    local t = math.max(1, math.floor(2 * u + 0.5))
    local function line(x1, x2, yy)
        bb:paintRect(math.floor(x + x1 * u), math.floor(y + yy * u - t / 2), math.floor((x2 - x1) * u), t, self.fg)
    end
    local function knob(cx, cy)
        local r = math.floor(2.6 * u + 0.5)
        local px0, py0 = math.floor(x + cx * u - r), math.floor(y + cy * u - r)
        bb:paintRoundedRect(px0, py0, 2 * r, 2 * r, self.fg, r)
        local ri = math.max(1, r - t)
        bb:paintRoundedRect(px0 + (r - ri), py0 + (r - ri), 2 * ri, 2 * ri, self.bg, ri)
    end
    line(4, 20, 6);  knob(15, 6)
    line(4, 20, 12); knob(9, 12)
    line(4, 20, 18); knob(17, 18)
end
C.Sliders = Sliders

function C.slidersIcon(size, fg, bg)
    return Sliders:new{ size = size, fg = fg, bg = bg }
end

--[[ Book cover

     With a cover image: the image, cropped to fill, with a border.
     Without one: a "typographic" cover - title at the top, author at the
     bottom - in one of four styles chosen by `style_index`. ]]
--- Scale `bb` to cover a w×h box and cut out the centre (like CSS object-fit:
--- cover). Done here because some KOReader versions' ImageWidget ignores
--- crop_to_fit and letterboxes the image instead. Frees `bb`; returns a new one.
function C.cropToFill(bb, w, h)
    local ok, out = pcall(function()
        local bw, bh = bb:getWidth(), bb:getHeight()
        if bw <= 0 or bh <= 0 then return nil end
        local s = math.max(w / bw, h / bh)
        local sw, sh = math.max(w, math.ceil(bw * s)), math.max(h, math.ceil(bh * s))
        local scaled = bb
        if sw ~= bw or sh ~= bh then
            scaled = require("ui/renderimage"):scaleBlitBuffer(bb, sw, sh, true)
        end
        local res = Blitbuffer.new(w, h, scaled:getType())
        res:blitFrom(scaled, 0, 0, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
        scaled:free()
        return res
    end)
    if ok and out then return out end
    return nil
end

--- An image widget showing `bb` filling exactly w×h, centre-cropped.
function C.filledImage(bb, w, h)
    local filled = C.cropToFill(bb, w, h)
    if filled then
        return ImageWidget:new{ image = filled, image_disposable = true, width = w, height = h }
    end
    -- fallback: let KOReader scale it
    return ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h,
        scale_factor = 0, crop_to_fit = true }
end

function C.cover(book, w, h, opts)
    opts = opts or {}
    local col = opts.colors
    local border = opts.border or Theme.px(3)
    if opts.cover_bb then
        local img = C.filledImage(opts.cover_bb, w - 2 * border, h - 2 * border)
        -- image covers get a grey frame (opts.image_border), drawn covers a black one
        return C.box(w, h, img, { border = border, border_color = opts.frame or col.fg, pad = border, bg = col.bg,
            radius = opts.radius, outer_bg = opts.radius and col.bg or nil })
    end

    local styles = {
        { bg = col.fg, fg = col.bg },
        { bg = col.bg, fg = col.fg },
        { bg = col.fill, fg = col.fg },
        { bg = col.bg, fg = col.fg },
    }
    local st = styles[((opts.style_index or 1) - 1) % #styles + 1]
    local pad_h = opts.pad_h or math.floor(w * 0.09)
    local pad_v = opts.pad_v or math.floor(w * 0.1)
    local inner_w = w - 2 * pad_h
    local VerticalGroup = require("ui/widget/verticalgroup")

    local title = C.textboxOn(st.bg, book.title, "serif_bold", opts.title_size or 30, st.fg,
        inner_w, opts.title_lines or 5, 0.1)
    if opts.compact then
        return C.box(w, h, title, { bg = st.bg, border = border, border_color = opts.frame or col.fg, radius = opts.radius,
            pad_l = pad_h, pad_t = pad_v, pad_r = pad_h, pad_b = pad_v })
    end
    local author = C.text(require("mh/data/model").upper(book.authors or ""), "sans",
        opts.author_size or 18, st.fg, inner_w)
    local title_h = title:getSize().h
    local author_h = author:getSize().h
    local gap = math.max(0, h - 2 * pad_v - 2 * border - title_h - author_h)
    local group = VerticalGroup:new{ align = "left", title, C.space(1, gap), author }
    return C.box(w, h, group, { bg = st.bg, border = border, border_color = opts.frame or col.fg, radius = opts.radius,
        pad_l = pad_h, pad_t = pad_v + border, pad_r = pad_h, pad_b = pad_v + border })
end

--[[ Wi-Fi icon: a dot and three arcs, drawn in any colour (KOReader's own icon
     only comes in black). ]]
local WifiIcon = Widget:extend{ size = 40, color = nil, arcs = 3 }
function WifiIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function WifiIcon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local u = self.size / 24
    local cx, cy = 12, 20.5
    local half = 1.2 -- half the arc thickness, in icon units
    local radii = { 5.2, 9.2, 13.2 }
    local max_angle = math.rad(46)
    for py = 0, self.size - 1 do
        local run_start
        for px_ = 0, self.size do
            local on = false
            if px_ < self.size then
                local ux, uy = (px_ + 0.5) / u, (py + 0.5) / u
                local dx, dy = ux - cx, uy - cy
                local d = math.sqrt(dx * dx + dy * dy)
                if (ux - 12) ^ 2 + (uy - 19.5) ^ 2 <= 1.7 ^ 2 then
                    on = true
                elseif dy < 0 and math.abs(math.atan2(dx, -dy)) <= max_angle then
                    for i, r in ipairs(radii) do
                        if i <= self.arcs and math.abs(d - r) <= half then on = true break end
                    end
                end
            end
            if on and not run_start then
                run_start = px_
            elseif not on and run_start then
                bb:paintRect(x + run_start, y + py, px_ - run_start, 1, self.color)
                run_start = nil
            end
        end
    end
end
C.WifiIcon = WifiIcon

--- Signal strength: the dot and `level` arcs (1–3) in `color`, the rest in `dim`.
function C.signalIcon(size, level, color, dim)
    local OverlapGroup = require("ui/widget/overlapgroup")
    return OverlapGroup:new{
        dimen = Geom:new{ w = size, h = size },
        WifiIcon:new{ size = size, color = dim },
        WifiIcon:new{ size = size, color = color, arcs = level },
    }
end

--[[ Dark-mode icon: a circle, its right half filled. ]]
local DarkIcon = Widget:extend{ size = 48, color = nil, bg = nil }
function DarkIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function DarkIcon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local d = math.floor(self.size * 0.8)
    local ox, oy = x + math.floor((self.size - d) / 2), y + math.floor((self.size - d) / 2)
    local t = math.max(2, math.floor(self.size / 12))
    bb:paintRoundedRect(ox, oy, d, d, self.color, math.floor(d / 2))
    -- hollow out the left half, leaving the ring
    local r_in = math.floor(d / 2) - t
    local cx, cy = ox + d / 2, oy + d / 2
    for dy = -r_in, r_in do
        local half = math.floor(math.sqrt(r_in * r_in - dy * dy))
        if half > 0 then bb:paintRect(math.floor(cx - half), math.floor(cy + dy), half, 1, self.bg) end
    end
end
C.DarkIcon = DarkIcon

--[[ Airplane icon (Wi-Fi off). ]]
local PlaneIcon = Widget:extend{ size = 40, color = nil }
function PlaneIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function PlaneIcon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    -- design option A: solid airliner seen from above, nose up (24-unit grid)
    local u = self.size / 24
    local pts = {}
    for _, p in ipairs(PlaneIcon.SHAPE) do pts[#pts + 1] = { p[1] * u, p[2] * u } end
    fillPolygon(bb, x, y, pts, self.color)
end
PlaneIcon.SHAPE = {
    { 21, 16 }, { 21, 14 }, { 13, 9 }, { 13, 3.5 }, { 12.6, 2.45 }, { 11.5, 2 }, { 10.4, 2.45 }, { 10, 3.5 },
    { 10, 9 }, { 2, 14 }, { 2, 16 }, { 10, 13.5 }, { 10, 19 }, { 8, 20.5 }, { 8, 22 }, { 11.5, 21 },
    { 15, 22 }, { 15, 20.5 }, { 13, 19 }, { 13, 13.5 },
}
C.PlaneIcon = PlaneIcon

--[[ Chevron ‹ / › (drawn: no glyph to go missing in a font). ]]
local Chevron = Widget:extend{ size = 40, color = nil, right = false }
function Chevron:getSize() return Geom:new{ w = self.size, h = self.size } end
function Chevron:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local u = self.size / 24
    local pts = {}
    for _, p in ipairs(Chevron.SHAPE) do
        local px_ = self.right and (24 - p[1]) or p[1]
        pts[#pts + 1] = { px_ * u, p[2] * u }
    end
    fillPolygon(bb, x, y, pts, self.color)
end
-- pointing left, 3-unit stroke on a 24-unit grid
Chevron.SHAPE = { { 15.9, 4.2 }, { 18.0, 6.3 }, { 12.3, 12 }, { 18.0, 17.7 }, { 15.9, 19.8 }, { 8.1, 12 } }
C.Chevron = Chevron

--- Round outlined button (‹ › − +): `child` centred in a circle, greyed when `off`.
function C.roundButton(size, child, col, off, callback)
    local grey = require("ffi/blitbuffer").gray(0.2)
    local box = C.box(size, size, child, { border = Theme.px(4), border_color = off and grey or col.fg,
        radius = math.floor(size / 2), halign = "center", valign = "center", bg = col.bg })
    return C.tappable(box, function() if not off and callback then callback() end end)
end

--[[ Rotation-lock icon: a phone outline with a small lock in it. ]]
local PhoneLockIcon = Widget:extend{ size = 48, color = nil, bg = nil }
function PhoneLockIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function PhoneLockIcon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local u = self.size / 24
    local t = math.max(2, math.floor(2.2 * u + 0.5))
    local px0, py0 = math.floor(x + 6.5 * u), math.floor(y + 2.5 * u)
    local pw, ph = math.floor(11 * u), math.floor(19 * u)
    bb:paintBorder(px0, py0, pw, ph, t, self.color, math.floor(2.2 * u), true)
    -- lock body and shackle
    local lw, lh = math.floor(5 * u), math.floor(4 * u)
    local lx, ly = math.floor(x + 12 * u - lw / 2), math.floor(y + 11.5 * u)
    bb:paintRect(lx, ly, lw, lh, self.color)
    local sw, sh = math.floor(3.4 * u), math.floor(3 * u)
    local st = math.max(1, math.floor(1.3 * u))
    bb:paintBorder(math.floor(x + 12 * u - sw / 2), ly - sh + st, sw, sh, st, self.color, math.floor(sw / 2), true)
end
C.PhoneLockIcon = PhoneLockIcon

--[[ Padlock icon: closed, or open (the shackle's right leg lifted out). ]]
local PadlockIcon = Widget:extend{ size = 48, color = nil, open = false }
function PadlockIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function PadlockIcon:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    local u = self.size / 24
    local t = math.max(2, math.floor(2.4 * u + 0.5))
    -- body
    local bx, by = math.floor(x + 5 * u), math.floor(y + 11 * u)
    local bw, bh = math.floor(14 * u), math.floor(10 * u)
    bb:paintBorder(bx, by, bw, bh, t, self.color, math.floor(2 * u), true)
    -- shackle: an arch over the body, legs down to its top edge
    local sx, sw = math.floor(x + 8 * u), math.floor(8 * u)
    local sy = math.floor(y + (self.open and 2 or 3.5) * u)
    local arch_h = math.floor(sw / 2) + t
    local legs_bottom = by + t
    -- arch: top half of a ring
    for dy = 0, arch_h - 1 do
        local r = sw / 2
        local yy = r - dy - 0.5
        local outer = math.sqrt(math.max(0, r * r - yy * yy))
        local ri = r - t
        local inner = (math.abs(yy) < ri) and math.sqrt(ri * ri - yy * yy) or 0
        local cx = sx + r
        local o, i = math.floor(outer + 0.5), math.floor(inner + 0.5)
        if o > i then
            bb:paintRect(math.floor(cx - o), sy + dy, o - i, 1, self.color)
            bb:paintRect(math.floor(cx + i), sy + dy, o - i, 1, self.color)
        end
    end
    local leg_top = sy + math.floor(sw / 2)
    -- left leg always reaches the body; the right one stops short when open
    bb:paintRect(sx, leg_top, t, math.max(0, legs_bottom - leg_top), self.color)
    local right_bottom = self.open and (leg_top + math.floor(1.5 * u)) or legs_bottom
    bb:paintRect(sx + sw - t, leg_top, t, math.max(0, right_bottom - leg_top), self.color)
end
C.PadlockIcon = PadlockIcon

--- Whether Wi-Fi is on and connected, from KOReader's own idea of the state
--- (cheap: no system calls). False when unknown.
function C.wifiConnected()
    local ok, connected = pcall(function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr.getConnectionState then return NetworkMgr:getConnectionState() end
        return NetworkMgr.is_connected
    end)
    return ok and connected == true
end

--- On/off switch: outlined pill, filled when on (Settings rows, quick panel).
function C.toggle(on, col)
    local OverlapGroup = require("ui/widget/overlapgroup")
    local w, h, bw = Theme.px(112), Theme.px(64), Theme.px(4)
    local knob = Theme.px(44)
    local inset = math.floor((h - knob) / 2)
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        C.box(w, h, nil, { bg = on and col.fg or col.bg, border = bw, border_color = col.fg, radius = math.floor(h / 2) }),
        Rect:new{ w = knob, h = knob, color = on and col.bg or col.fg, radius = math.floor(knob / 2),
            overlap_offset = { on and (w - inset - knob) or inset, inset } },
    }
end

--- Whether the Wi-Fi radio is on (connected or not). True when unknown, so
--- the airplane icon only shows when Wi-Fi is really off.
function C.wifiOn()
    local ok, on = pcall(function()
        local Device = require("device")
        if not Device:hasWifiToggle() then return true end
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr.getWifiState then return NetworkMgr:getWifiState() end
        return NetworkMgr.is_wifi_on
    end)
    return not ok or on ~= false
end

--[[ Lightning bolt drawn over the battery while charging. Painted twice: a
     background-coloured halo, then the bolt, so it shows on the filled part of
     the battery as well as on the empty part. ]]
local BOLT = { { 0.62, 0.0 }, { 0.12, 0.58 }, { 0.46, 0.58 }, { 0.36, 1.0 }, { 0.88, 0.40 }, { 0.54, 0.40 } }
local Bolt = Widget:extend{ w = 0, h = 0, fg = nil, bg = nil }
function Bolt:getSize() return Geom:new{ w = self.w, h = self.h } end
function Bolt:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local function pts(grow)
        local out = {}
        for _, p in ipairs(BOLT) do
            local cx, cy = (p[1] - 0.5) * (self.w + 2 * grow) + self.w / 2, (p[2] - 0.5) * (self.h + 2 * grow) + self.h / 2
            out[#out + 1] = { cx, cy }
        end
        return out
    end
    local halo = math.max(1, Theme.px(2))
    fillPolygon(bb, x, y, pts(halo), self.bg)
    fillPolygon(bb, x, y, pts(0), self.fg)
end
C.Bolt = Bolt

--[[ Status bar: clock on the left, battery on the right (with a Wi-Fi icon in
     front of it when `wifi` is set and Wi-Fi is connected). ]]
function C.statusBar(width, col, size, bold, wifi, clock_only)
    local Device = require("device")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local datetime = require("datetime")
    size = size or 30
    local h = Theme.px(math.floor(size * 4 / 3))
    local clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local kind = bold and "sans_medium" or "sans"
    local left = C.text(clock, kind, size, col.muted)
    local right = C.space(1, 1)
    local powerd = not clock_only and Device:hasBattery() and Device:getPowerDevice()
    if powerd then
        local cap = powerd:getCapacity() or 0
        local k = size / 30
        local bw, bh, bt = Theme.px(46 * k), Theme.px(24 * k), math.max(1, Theme.px((bold and 4.2 or 3) * k))
        local inner = math.max(1, Theme.px(2 * k))
        local fill_w = math.max(0, math.floor((bw - 2 * bt - 2 * inner) * cap / 100))
        local body = C.box(bw, bh, Rect:new{ w = fill_w, h = bh - 2 * bt - 2 * inner, color = col.muted },
            { border = bt, border_color = col.muted, pad = bt + inner }) -- square: small rounded corners break up on e-ink
        local charging = false
        pcall(function() charging = powerd:isCharging() end)
        if charging then
            -- lightning bolt over the battery while it charges
            local bolt_h = bh + Theme.px(8 * k)
            local bolt = Bolt:new{ w = math.floor(bolt_h * 0.62), h = bolt_h, fg = col.muted, bg = col.bg or Blitbuffer.COLOR_WHITE }
            bolt.overlap_offset = { math.floor((bw - bolt.w) / 2), math.floor((bh - bolt_h) / 2) }
            body = OverlapGroup:new{ dimen = Geom:new{ w = bw, h = bh }, allow_mirroring = false, body, bolt }
        end
        local battery = HorizontalGroup:new{
            align = "center",
            body,
            Rect:new{ w = Theme.px(4 * k), h = Theme.px(10 * k), color = col.muted },
        }
        right = HorizontalGroup:new{
            align = "center",
            C.text(cap .. "%", kind, size, col.muted), C.space(Theme.px(14 * k), 1), battery,
        }
        if wifi then
            -- connected: Wi-Fi; radio off: airplane; on but not connected: nothing
            local icon
            if C.wifiConnected() then
                icon = WifiIcon:new{ size = Theme.px(40 * k / 1.2), color = col.muted }
            elseif not C.wifiOn() then
                icon = PlaneIcon:new{ size = Theme.px(40 * k / 1.2), color = col.muted }
            end
            if icon then
                table.insert(right, 1, icon)
                table.insert(right, 2, C.space(Theme.px(28 * k / 1.2), 1))
            end
        end
    end
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = h },
        C.box(left:getSize().w, h, left, { valign = "center" }),
        C.box(right:getSize().w, h, right, { valign = "center", overlap_align = "right" }),
    }
end

return C
