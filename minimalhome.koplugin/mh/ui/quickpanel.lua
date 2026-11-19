--[[--
Quick settings, pulled down from the top edge (home screen or reading screen):
Wi-Fi · Dark mode · Rotation lock · Settings, and the front light with "Auto".
Tap below the panel, swipe it up, or press Back to close it.
--]]

local Device = require("device")
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
local D = require("mh/device")
local Theme = require("mh/theme")

local px = Theme.px

local QuickPanel = InputContainer:extend{
    ui = nil,
    on_settings = nil, -- opens the Settings page
}

function QuickPanel:init()
    self.col = Theme.boldColors(false)
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local range = function() return self.dimen end
    self.ges_events = {
        MHTapOutside = { GestureRange:new{ ges = "tap", range = range } },
        MHSwipe = { GestureRange:new{ ges = "swipe", range = range } },
        MHPan = { GestureRange:new{ ges = "pan", range = range } },
        MHPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

-- Pieces ---------------------------------------------------------------------------------

local function wifiIcon(size, color)
    return C.WifiIcon:new{ size = size, color = color }
end

--- On: black tile, white text. Off: white tile, grey frame, dark-grey text.
function QuickPanel:tile(w, icon, label, sub, on, action)
    local fg = on and self.col.bg or self.col.muted
    local bg = on and self.col.fg or self.col.bg
    local content = VerticalGroup:new{
        align = "center",
        C.box(px(56), px(56), icon(fg, bg), { halign = "center", valign = "center" }),
        C.space(1, px(14)),
        C.text(label, "sans_bold", 30, fg, w - px(24)),
    }
    if sub and sub ~= "" then
        table.insert(content, C.space(1, px(4)))
        table.insert(content, C.text(sub, "sans_medium", 24, fg, w - px(24)))
    end
    return C.tappable(C.box(w, px(188), content, { bg = bg, border = px(4),
        border_color = on and self.col.fg or self.col.line,
        radius = px(16), halign = "center", valign = "center" }), function()
        UIManager:nextTick(function()
            local ok, err = pcall(action)
            if not ok then logger.err("MinimalHome: quick panel action failed:", err) end
        end)
    end)
end

function QuickPanel:roundButton(glyph, action, color)
    local d = px(100)
    color = color or self.col.fg
    return C.tappable(C.box(d, d, C.text(glyph, "sans_bold", 46, color),
        { border = px(4), border_color = color, radius = math.floor(d / 2), halign = "center", valign = "center" }),
        function() UIManager:nextTick(action) end)
end

function QuickPanel:checkbox(on, color)
    local s = px(48)
    color = color or self.col.fg
    local mark = on and C.text("✓", "sans_bold", 32, self.col.bg) or nil
    return C.box(s, s, mark, { bg = on and color or self.col.bg, border = px(4),
        border_color = color, radius = px(10), halign = "center", valign = "center" })
end

function QuickPanel:brightnessBlock(w)
    local step, steps = D.brightnessStep(), D.LIGHT_STEPS
    local auto = D.autoBrightness()
    local light_on = D.lightOn()
    local level = string.format("%d / %d", step, steps)
    local value = not light_on and "Off" or (auto and ("Auto · " .. level) or level)
    -- light off: Auto and the level are greyed out (and ignore taps)
    local cc = light_on and self.col.fg or self.col.line
    local auto_btn = C.tappable(HorizontalGroup:new{
        align = "center",
        self:checkbox(auto, cc), C.space(px(16), 1), C.text("Auto", "sans_bold", 32, cc),
    }, function()
        if not light_on then return end -- only while the light is on
        UIManager:nextTick(function()
            if not D.setAutoBrightness(not auto) then
                require("mh/ui/snackbar").show("Automatic brightness isn't available",
                    4, "The light sensor can't be read.")
            end
            self:rebuild()
        end)
    end)
    local right = HorizontalGroup:new{ align = "center", auto_btn }
    -- light on/off switch in front of the label
    local power = C.tappable(C.toggle(light_on, self.col), function()
        UIManager:nextTick(function()
            if light_on and D.autoBrightness() then D.setAutoBrightness(false) end
            D.setLightOn(not light_on)
            self:rebuild()
        end)
    end)
    local label = HorizontalGroup:new{
        align = "center",
        power, C.space(px(22), 1), C.text("Brightness", "sans_bold", 34, self.col.fg),
        -- the level right after the label, as "SIZE · 22" in the Font panel
        C.text(" · " .. value, "sans_medium", 34, self.col.muted),
    }
    right.overlap_align = "right"
    local head = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = px(72) },
        C.box(label:getSize().w, px(72), label, { valign = "center" }),
        C.box(right:getSize().w, px(72), right, { valign = "center", overlap_align = "right" }),
    }
    local nudge = function(d)
        return function()
            if not light_on then return end
            if D.autoBrightness() then D.setAutoBrightness(false) end
            D.setBrightnessStep(D.brightnessStep() + d)
            self:rebuild()
        end
    end
    local bar_w = w - 2 * px(100) - 2 * px(40)
    local bar_h = px(20)
    local ratio = step / steps
    -- track, filled part and a round knob (as the page slider)
    local knob = px(52)
    local filled = math.floor(bar_w * ratio)
    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = bar_w, h = knob },
        C.Rect:new{ w = bar_w, h = bar_h, color = Theme.colors(false).line, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.Rect:new{ w = filled, h = bar_h, color = cc, radius = math.floor(bar_h / 2),
            overlap_offset = { 0, math.floor((knob - bar_h) / 2) } },
        C.box(knob, knob, C.space(1, 1), { bg = self.col.bg, border = px(5), border_color = cc,
            radius = math.floor(knob / 2), overlap_offset = { math.max(0, math.min(bar_w - knob, filled - math.floor(knob / 2))), 0 } }),
    }
    local bar_tap = C.tappable(C.box(bar_w, px(100), bar, { valign = "center" }), nil)
    self._bar = bar_tap
    self._bar_live = light_on
    bar_tap.callback = function()
        local ges = self._last_tap
        if ges then UIManager:nextTick(function() self:setFromX(ges.pos.x) end) end
    end
    local controls = HorizontalGroup:new{
        align = "center",
        self:roundButton("−", nudge(-1), cc), C.space(px(40), 1), bar_tap, C.space(px(40), 1),
        self:roundButton("+", nudge(1), cc),
    }
    return VerticalGroup:new{ align = "left", head, C.space(1, px(32)), controls }
end

-- Layout ----------------------------------------------------------------------------------

function QuickPanel:build()
    local W = self.dimen.w
    local margin = px(Theme.margin_h)
    local inner = W - 2 * margin

    -- status line with the date
    local cap = D.battery()
    local clock = os.date("%H:%M · %a, %b ") .. tonumber(os.date("%d"))
    if G_reader_settings:isTrue("twelve_hour_clock") then
        clock = os.date("%I:%M %p · %a, %b "):gsub("^0", "") .. tonumber(os.date("%d"))
    end
    local status_l = C.text(clock, "sans_medium", 36, self.col.muted)
    local status_r = C.text(cap and (cap .. "%") or "", "sans_medium", 36, self.col.muted)
    status_r.overlap_align = "right"
    local status = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = px(48) }, status_l, status_r }

    -- tiles
    local tiles = {}
    if D.hasWifi() then
        local on = D.wifiOn()
        table.insert(tiles, { function(c)
                if on then return wifiIcon(px(52), c) end
                return C.PlaneIcon:new{ size = px(52), color = c }
            end, "Wi-Fi",
            D.wifiConnected() and "Connected" or (on and "On" or "Off"), on,
            function() D.toggleWifi(function() self:rebuild() end); self:rebuild() end })
    end
    table.insert(tiles, { function(c, b) return C.DarkIcon:new{ size = px(56), color = c, bg = b } end, "Dark mode",
        D.nightMode() and "On" or "Off", D.nightMode(), function() D.toggleNightMode(); self:rebuild() end })
    if D.hasGSensor() then
        local locked = D.rotationLocked()
        table.insert(tiles, { function(c) return C.PadlockIcon:new{ size = px(56), color = c, open = not locked } end,
            "Rotation",
            locked and "Locked" or "Unlocked", locked, function() D.toggleRotationLock(); self:rebuild() end })
    end
    table.insert(tiles, { function(c, b) return C.slidersIcon(px(56), c, b) end,
        "All Settings", "", false, function()
            self:close()
            if self.on_settings then self.on_settings() end
        end })
    local gap = px(24)
    local tile_w = math.floor((inner - (#tiles - 1) * gap) / #tiles)
    local row = HorizontalGroup:new{ align = "top" }
    for i, t in ipairs(tiles) do
        if i > 1 then table.insert(row, C.space(gap, 1)) end
        table.insert(row, self:tile(tile_w, t[1], t[2], t[3], t[4], t[5]))
    end

    local content = VerticalGroup:new{ align = "left", status, C.space(1, px(44)), row }
    if D.hasFrontlight() then
        table.insert(content, C.space(1, px(72)))
        table.insert(content, self:brightnessBlock(inner))
    end
    table.insert(content, C.space(1, px(36)))
    local handle = C.Rect:new{ w = px(140), h = px(10), color = self.col.line, radius = px(5) }
    table.insert(content, C.box(inner, px(10), handle, { halign = "center" }))

    local h = px(Theme.margin_top) + content:getSize().h + px(28)
    self.panel_h = h
    self.panel = C.box(W, h, content, { bg = self.col.bg, pad_l = margin, pad_t = px(Theme.margin_top) })
    self[1] = self.panel
end

function QuickPanel:rebuild(dragging)
    if self.closed then return end
    if self[1] then self[1]:free() end
    self:build()
    -- While dragging, refresh only the brightness row, in the normal "ui" waveform:
    -- the fast (black and white) one flashes the grey bar black on e-ink.
    local r = dragging and self._bar_rect
    local region = r and Geom:new{ x = 0, y = r.y - px(40), w = self.dimen.w, h = r.h + px(80) }
        or Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.panel_h + px(4) }
    UIManager:setDirty(self, "ui", region)
end

function QuickPanel:paintTo(bb)
    local W = self.dimen.w
    self.panel:paintTo(bb, 0, 0)
    -- where the brightness bar is on screen (kept across rebuilds while dragging)
    if self._bar and self._bar.dimen then self._bar_rect = self._bar.dimen:copy() end
    -- black line along the bottom edge
    bb:paintRect(0, self.panel_h, W, px(4), self.col.fg)
end

-- Input ---------------------------------------------------------------------------------------

function QuickPanel:handleEvent(event)
    if event.handler == "onGesture" and event.args and event.args[1] and event.args[1].ges == "tap" then
        self._last_tap = event.args[1]
    end
    return InputContainer.handleEvent(self, event)
end

function QuickPanel:onMHTapOutside(_, ges)
    if ges and ges.pos and ges.pos.y > self.panel_h + px(4) then self:close() end
    return true
end

--- Brightness from a screen x on the bar (tap, drag or flick).
function QuickPanel:setFromX(x, fast)
    local d = self._bar_rect
    if not d or not self._bar_live then return end
    local r = math.max(0, math.min(1, (x - d.x) / d.w))
    local step = math.floor(r * D.LIGHT_STEPS + 0.5)
    if D.autoBrightness() then D.setAutoBrightness(false) end
    if step == D.brightnessStep() and fast then return end
    D.setBrightnessStep(step)
    self:rebuild(fast)
end

--- Is a point on the brightness bar (with some room above and below for a finger)?
function QuickPanel:onBar(pos)
    local d = self._bar_rect
    return d and pos and pos.x >= d.x - px(20) and pos.x <= d.x + d.w + px(20)
        and pos.y >= d.y - px(30) and pos.y <= d.y + d.h + px(30)
end

-- Dragging along the bar sets the brightness as the finger moves.
function QuickPanel:onMHPan(_, ges)
    if not ges then return true end
    if self._dragging or self:onBar(ges.start_pos) then
        self._dragging = true
        self:setFromX(ges.pos.x, true)
    end
    return true
end

function QuickPanel:onMHPanRelease(_, ges)
    if self._dragging then
        self._dragging = nil
        if ges and ges.pos then self:setFromX(ges.pos.x) end
    end
    return true
end

function QuickPanel:onMHSwipe(_, ges)
    if not ges then return true end
    -- a quick flick along the bar: jump to where it ended
    if (ges.direction == "east" or ges.direction == "west") and self:onBar(ges.pos) then
        local x = ges.pos.x + (ges.direction == "east" and 1 or -1) * (ges.distance or 0)
        self:setFromX(x)
        return true
    end
    if ges.direction == "north" then self:close() end
    return true
end

function QuickPanel:show()
    UIManager:show(self, "ui")
    return self
end

function QuickPanel:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
end

function QuickPanel:onClose()
    self:close()
    return true
end

-- Power button: the panel never survives sleep, so waking shows the page underneath.
-- (Not returning true: every other widget still gets the event.)
function QuickPanel:onSuspend() self:close() end

--- Auto brightness moved the light while the panel is open: show the new level.
function QuickPanel:onMHBrightnessChanged()
    if not self.closed then self:rebuild() end
end
function QuickPanel:onResume() self:close() end

function QuickPanel:onSetRotationMode(mode)
    self:close()
    if self.ui and self.ui.handleEvent then
        local Event = require("ui/event")
        self.ui:handleEvent(Event:new("SetRotationMode", mode))
    end
    return true
end

function QuickPanel:onCloseWidget()
    self.closed = true
    if self[1] then self[1]:free() end
end

return QuickPanel
