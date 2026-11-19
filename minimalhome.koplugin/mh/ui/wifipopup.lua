--[[--
Wi-Fi popup (design: "Settings › Wi-Fi popup"), opened from Settings.

* Opens on or off, as Wi-Fi is. The toggle next to the title switches it.
* On: the network in use on top (✓ Connected), then the other networks nearby,
  strongest first. The list scrolls inside the popup; Scan again refreshes it.
* Tap a network that needs no password, or whose password is saved: it joins
  at once ("Connecting…" on its row). A new network with a lock: the popup
  gives way to the password card; Join comes back here.
* Joined or not, a snackbar says so.
* Close, or a tap outside the popup, goes back.
--]]

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
local W = require("mh/wifi")
local px = Theme.px

local WifiPopup = InputContainer:extend{
    networks = nil,    -- last scan (kept when coming back from the password card)
    connecting = nil,  -- ssid being joined
    on_close = nil,
}

WifiPopup.ROW_H = 112
WifiPopup.MAX_H = 1240

function WifiPopup:init()
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
    self.on = W.isOn()
    self.current = self.on and not self.connecting and W.current() or nil
    self.scroll = 0
    self:build()
end

-- Pieces -----------------------------------------------------------------------------------

function WifiPopup:stateLine()
    if not self.on then return "Off" end
    if self.connecting then return "Connecting…" end
    if self.current then return "Connected to " .. self.current end
    return "Not connected"
end

function WifiPopup:rowShell(w, h, content)
    return VerticalGroup:new{ align = "left", C.hline(w, px(3), self.col.line), C.box(w, h - px(3), content, { valign = "center" }) }
end

function WifiPopup:networkRow(w, net, is_current)
    local col = self.col
    local icon = C.signalIcon(px(44), is_current and 3 or W.level(net), col.fg, Theme.colors(false).line)
    local text_w = w - px(44) - px(28) - px(66)
    local sub
    if is_current then sub = "Connected"
    elseif self.connecting == net.ssid then sub = "Connecting…"
    elseif W.known(net) and W.locked(net) then sub = "Saved"
    elseif not W.locked(net) then sub = "Open network" end
    local lines = VerticalGroup:new{ align = "left",
        C.text(net.ssid, "sans_bold", 36, col.fg, text_w) }
    if sub then
        table.insert(lines, C.space(1, px(4)))
        table.insert(lines, C.text(sub, "sans_medium", 28, col.muted, text_w))
    end
    local left = HorizontalGroup:new{ align = "center", icon, C.space(px(28), 1), lines }
    local row = OverlapGroup:new{ dimen = Geom:new{ w = w, h = px(WifiPopup.ROW_H) - px(3) },
        C.box(w - px(66), px(WifiPopup.ROW_H) - px(3), left, { valign = "center" }) }
    local right
    if is_current then
        right = C.text("✓", "sans_bold", 40, col.fg)
    elseif W.locked(net) then
        right = C.PadlockIcon:new{ size = px(38), color = col.fg }
    end
    if right then
        local rb = C.box(px(50), px(WifiPopup.ROW_H) - px(3), right, { halign = "right", valign = "center" })
        rb.overlap_align = "right"
        table.insert(row, rb)
    end
    local shell = self:rowShell(w, px(WifiPopup.ROW_H), row)
    if is_current then return shell end
    return C.tappable(shell, function() UIManager:nextTick(function() self:pick(net) end) end)
end

function WifiPopup:listHeader(w)
    local col = self.col
    local title = C.text(self.current and "OTHER NETWORKS" or "NETWORKS NEARBY", "sans_bold", 28, col.muted)
    local scan_t = C.text("Scan again", "sans_bold", 32, col.fg)
    local scan = C.tappable(C.box(scan_t:getSize().w, px(88), scan_t, { valign = "center" }),
        function() UIManager:nextTick(function() self:rescan() end) end)
    scan.overlap_align = "right"
    local row = OverlapGroup:new{ dimen = Geom:new{ w = w, h = px(88) },
        C.box(w, px(88), title, { valign = "center" }), scan }
    return self:rowShell(w, px(92), row)
end

--- The list as blocks for the viewport.
function WifiPopup:listBlocks(w)
    local blocks, y = {}, 0
    local function add(h, build) blocks[#blocks + 1] = { y = y, h = h, build = build }; y = y + h end
    local nets = self.networks or {}
    local cur
    for _, n in ipairs(nets) do if n.ssid == self.current then cur = n end end
    if self.current then
        local n = cur or { ssid = self.current }
        add(px(WifiPopup.ROW_H), function() return self:networkRow(w, n, true) end)
    end
    add(px(92), function() return self:listHeader(w) end)
    if not self.networks then
        add(px(WifiPopup.ROW_H), function()
            return self:rowShell(w, px(WifiPopup.ROW_H), C.text("Looking for networks…", "sans_medium", 32, self.col.muted))
        end)
    elseif #nets == 0 or (#nets == 1 and cur) then
        add(px(WifiPopup.ROW_H), function()
            return self:rowShell(w, px(WifiPopup.ROW_H), C.text("No other networks found", "sans_medium", 32, self.col.muted))
        end)
    else
        for _, n in ipairs(nets) do
            if n ~= cur then add(px(WifiPopup.ROW_H), function() return self:networkRow(w, n, false) end) end
        end
    end
    add(px(3), function() return C.hline(w, px(3), self.col.line) end)
    return blocks
end

function WifiPopup:build()
    local col = self.col
    local W_ = self.dimen.w
    local margin = px(Theme.margin_h)
    local card_w = W_ - 2 * margin
    local pad_h, pad_t, pad_b = px(56), px(44), px(40)
    local inner = card_w - 2 * pad_h
    local card_x, card_y = margin, px(220)

    -- header: title, state, toggle
    local head_text = VerticalGroup:new{ align = "left",
        C.text("Wi-Fi", "serif_bold", 56, col.fg),
        C.space(1, px(8)),
        C.text(self:stateLine(), "sans_medium", 30, col.muted, inner - px(150)) }
    local hh = head_text:getSize().h
    local toggle = C.toggle(self.on, col)
    local toggle_tap = C.tappable(C.box(px(140), hh, toggle, { halign = "right", valign = "center" }),
        function() UIManager:nextTick(function() self:toggleWifi() end) end)
    toggle_tap.overlap_align = "right"
    local head_tap = C.tappable(C.box(inner - px(140), hh, head_text, { valign = "center" }),
        function() UIManager:nextTick(function() self:toggleWifi() end) end)
    local header = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = hh }, head_tap, toggle_tap }

    local close = C.tappable(C.box(inner, px(116), C.text("Close", "sans_bold", 38, col.fg),
        { border = px(4), border_color = col.fg, radius = px(10), halign = "center", valign = "center" }),
        function() UIManager:nextTick(function() self:close() end) end)

    local fixed = pad_t + hh + px(36) + px(4) + px(4) + px(32) + px(116) + pad_b
    local body
    self.viewport = nil
    if self.on then
        local blocks = self:listBlocks(inner)
        local total = blocks[#blocks].y + blocks[#blocks].h
        local body_h = math.min(total, px(WifiPopup.MAX_H) - fixed)
        local vp_y = card_y + pad_t + hh + px(36) + px(4)
        self.viewport = Viewport:new{ x = card_x + pad_h, y = vp_y, w = inner, h = body_h,
            content_x = card_x + pad_h, blocks = blocks, bg = col.bg }
        self.scroll = math.max(0, math.min(self.scroll, self.viewport:maxScroll()))
        self.viewport.scroll = self.scroll
        self.viewport:update()
        body = self.viewport
    else
        body = C.textbox("Turn Wi-Fi on to see the networks nearby. Reading works without it.",
            "sans_medium", 34, col.muted, inner, 4, 0.35, "left")
    end
    local scrolled = self.viewport and self.scroll > 0
    local more = self.viewport and self.scroll < self.viewport:maxScroll()
    local content = VerticalGroup:new{ align = "left",
        header,
        C.space(1, px(36)),
        C.hline(inner, px(4), scrolled and col.line or col.bg),
        body,
        C.hline(inner, px(4), more and col.line or col.bg),
        C.space(1, px(32)),
        close,
    }
    local card_h = pad_t + content:getSize().h + pad_b
    self.card_rect = Geom:new{ x = card_x, y = card_y, w = card_w, h = card_h }
    self.card = C.box(card_w, card_h, content, { bg = col.bg, border = px(4), border_color = col.fg,
        radius = px(20), pad_l = pad_h, pad_t = pad_t })
    self.card.overlap_offset = { card_x, card_y }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = W_, h = self.dimen.h }, self.card }
end

function WifiPopup:rebuild()
    if self.closed then return end
    local old = self.card_rect
    if self[1] then self[1]:free() end
    self:build()
    -- refresh the union of the old and new card (the card can shrink)
    local r = self.card_rect
    if old then
        local y0 = math.min(old.y, r.y)
        local y1 = math.max(old.y + old.h, r.y + r.h)
        UIManager:setDirty("all", "ui", Geom:new{ x = r.x, y = y0, w = r.w, h = y1 - y0 })
    else
        UIManager:setDirty(self, "ui", r)
    end
end

function WifiPopup:paintTo(bb, x, y)
    self.card:paintTo(bb, x + self.card_rect.x, y + self.card_rect.y)
end

-- Actions ----------------------------------------------------------------------------------

function WifiPopup:rescan()
    if self.closed or not self.on then return end
    self.networks = nil
    self:rebuild()
    UIManager:forceRePaint()
    local list = W.scan()
    if self.closed then return end
    self.networks = list or {}
    if not self.connecting then self.current = W.current() end
    self:rebuild()
end

function WifiPopup:toggleWifi()
    if self.on then
        self.on = false
        self.current, self.connecting, self.networks = nil, nil, nil
        self:rebuild()
        W.turnOff(function() if not self.closed then self:rebuild() end end)
    else
        self.on = true
        self.networks = nil
        self:rebuild()
        W.turnOn(function(ok, ssid)
            if ok then W.report(true, ssid) end
            local live = WifiPopup.active
            if live and not live.closed then
                live.current = ok and ssid or nil
                live:rebuild()
            end
        end)
        -- give the radio a moment before asking what is around
        UIManager:scheduleIn(2, function() self:rescan() end)
    end
end

--- Result of a connection attempt, for whichever popup is showing by then.
function WifiPopup.connectDone(ok, ssid)
    W.report(ok, ssid)
    local live = WifiPopup.active
    if live and not live.closed then
        live.connecting = nil
        live.current = W.current()
        live:rebuild()
    end
end

function WifiPopup:pick(net)
    if self.connecting then return end
    if W.known(net) then
        self.connecting = net.ssid
        self.current = nil
        self:rebuild()
        W.connect(net, nil, WifiPopup.connectDone)
        return
    end
    -- a new network with a lock: ask for the password, then come back here
    local networks, on_close = self.networks, self.on_close
    self.on_close = nil
    self:close()
    require("mh/ui/wifipassword"):new{
        network = net,
        on_join = function(password)
            WifiPopup:new{ networks = networks, connecting = net.ssid, on_close = on_close }:show()
            W.connect(net, password, WifiPopup.connectDone)
        end,
        on_cancel = function()
            WifiPopup:new{ networks = networks, on_close = on_close }:show()
        end,
    }:show()
end

-- Input ------------------------------------------------------------------------------------

function WifiPopup:inList(pos)
    local vp = self.viewport
    return vp and pos and pos.x >= vp.x and pos.x < vp.x + vp.w and pos.y >= vp.y and pos.y < vp.y + vp.h
end

function WifiPopup:scrollBy(dy)
    if not self.viewport then return end
    local before = self.scroll
    self.scroll = math.max(0, math.min(self.viewport:maxScroll(), self.scroll + dy))
    if self.scroll ~= before then self:rebuild() end
end

function WifiPopup:onMHTapOutside(_, ges)
    local p, r = ges and ges.pos, self.card_rect
    if p and not (p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h) then self:close() end
    return true
end

function WifiPopup:onMHSwipe(_, ges)
    self._pan_dy = nil
    if not ges or not self:inList(ges.pos) then return true end
    local dist = (ges.distance or 0) * 1.5
    if ges.direction == "north" then self:scrollBy(dist) elseif ges.direction == "south" then self:scrollBy(-dist) end
    return true
end

function WifiPopup:onMHPan(_, ges)
    if ges and ges.relative and self:inList(ges.pos) then self._pan_dy = ges.relative.y end
    return true
end

function WifiPopup:onMHPanRelease()
    if self._pan_dy then
        local dy = self._pan_dy
        self._pan_dy = nil
        self:scrollBy(-dy)
    end
    return true
end

function WifiPopup:show()
    WifiPopup.active = self
    UIManager:show(self, "ui")
    if self.on and not self.networks then
        UIManager:scheduleIn(0.1, function() self:rescan() end)
    end
    return self
end

function WifiPopup:close()
    if self.closed then return end
    self.closed = true
    if WifiPopup.active == self then WifiPopup.active = nil end
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
end

function WifiPopup:onSuspend() self:close() end

function WifiPopup:onClose()
    self:close()
    return true
end

function WifiPopup:onCloseWidget()
    self.closed = true
    if WifiPopup.active == self then WifiPopup.active = nil end
    if self[1] then self[1]:free() end
    if self.viewport then self.viewport:free() end
end

-- Wi-Fi changed elsewhere (quick panel, KOReader): keep the popup right.
function WifiPopup:onNetworkConnected()
    if not self.connecting then
        self.current = W.current()
        self:rebuild()
    end
end

function WifiPopup:onNetworkDisconnected()
    self.on = W.isOn()
    self.current = nil
    self:rebuild()
end

return WifiPopup
