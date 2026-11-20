--[[--
Settings page (opened from the sliders button on the home screen or the quick
panel), with its sub-pages: Screensaver and Default font.

Every row changes a real KOReader setting through mh/device.lua, so KOReader's
own menus show the same values.
--]]

local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")

local C = require("mh/ui/components")
local D = require("mh/device")
local Library = require("mh/data/library")
local Page = require("mh/ui/page")
local Theme = require("mh/theme")

local px = Theme.px

local Updater = require("mh/updater")

local function deviceName()
    local Device = require("device")
    return Device.model and Device.model:gsub("^Kindle", "Kindle ") or "Kindle"
end

local function notify(text)
    require("mh/ui/snackbar").show(text, 3)
end

--- After picking a font or screensaver: back to Settings, with a short "Updated".
local function pickedAndBack(page)
    page:close() -- Settings refreshes itself through on_close
    require("mh/ui/snackbar").show("Updated")
end

-- Screensaver picker ---------------------------------------------------------------------

local Screensaver = Page:extend{
    back_to_top = false,
    swipe_home = true,
    title = "Screensaver",
    subtitle = "What the screen shows while the Kindle sleeps.",
    back_label = "Back",
}

function Screensaver:thumb(entry, w, h, selected)
    local inner
    local border = selected and px(5) or px(3)
    local frame = selected and self.col.fg or self.col.line
    local path = D.screensaverPath(entry)
    if path then
        local RenderImage = require("ui/renderimage")
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false)
        if ok and bb then
            inner = C.filledImage(bb, w - 2 * border, h - 2 * border)
        else
            inner = ImageWidget:new{ file = path, width = w - 2 * border, height = h - 2 * border,
                scale_factor = 0, crop_to_fit = true }
        end
    else
        -- "Book cover": the cover of the book read last
        local last = G_reader_settings:readSetting("lastfile")
        local bb = last and Library.getCover(last)
        if bb then
            inner = C.filledImage(bb, w - 2 * border, h - 2 * border)
        else
            inner = C.box(w - 2 * border, h - 2 * border, C.text("Book cover", "serif_bold", 34, self.col.fg),
                { bg = self.col.fill, halign = "center", valign = "center" })
        end
    end
    local card = C.box(w, h, inner, { border = border, border_color = frame, pad = border,
        bg = self.col.bg, radius = px(12), outer_bg = self.col.bg })
    if not selected then return card end
    local d = px(60)
    local badge = C.box(d, d, C.text("✓", "sans_bold", 34, self.col.bg), { bg = self.col.fg,
        border = px(4), border_color = self.col.bg, radius = math.floor(d / 2), halign = "center", valign = "center" })
    badge.overlap_offset = { w - d - px(14), px(14) }
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, card, badge }
end

function Screensaver:blocks()
    local list = { function() return self:headerBlock() end }
    local w = self:contentWidth()
    local gap = px(40)
    local col_w = math.floor((w - 2 * gap) / 3)
    local thumb_h = px(440)
    local current = D.currentScreensaver()
    table.insert(list, function() return C.space(1, px(64)) end)
    for r = 0, math.ceil(#D.SCREENSAVERS / 3) - 1 do
        table.insert(list, function()
            local row = HorizontalGroup:new{ align = "top" }
            for c = 1, 3 do
                local e = D.SCREENSAVERS[r * 3 + c]
                if e then
                    local on = e.id == current
                    local item = VerticalGroup:new{
                        align = "left",
                        self:thumb(e, col_w, thumb_h, on),
                        C.space(1, px(18)),
                        C.text(e.label, on and "sans_bold" or "sans_medium", 36, self.col.fg, col_w),
                    }
                    if c > 1 then table.insert(row, C.space(gap, 1)) end
                    table.insert(row, C.tappable(item, function()
                        UIManager:nextTick(function()
                            D.setScreensaver(e.id)
                            pickedAndBack(self)
                        end)
                    end))
                end
            end
            return VerticalGroup:new{ align = "left", r > 0 and C.space(1, px(56)) or C.space(1, 0), row }
        end)
    end
    return list
end

-- Font picker ----------------------------------------------------------------------------

local FontPicker = Page:extend{
    back_to_top = false,
    swipe_home = true,
    title = "Default font",
    subtitle = "Used for books opened from now on.",
    back_label = "Back",
}

function FontPicker:blocks()
    local list = { function() return self:headerBlock() end }
    local current = self.current or D.currentFont()
    local fonts = self.fonts or D.fontList()
    self.fonts = fonts
    if #fonts == 0 then
        table.insert(list, function()
            return VerticalGroup:new{ align = "left", C.space(1, px(72)),
                C.text("No fonts found.", "sans_medium", 34, self.col.muted) }
        end)
        return list
    end
    table.insert(list, function() return C.space(1, px(56)) end)
    for _, face in ipairs(fonts) do
        table.insert(list, function() return self:fontRow(face, face == current) end)
    end
    return list
end

--- One font: its name and a sample line, both in that font (design: Default font).
function FontPicker:fontRow(face, selected)
    local TextWidget = require("ui/widget/textwidget")
    local w = self:contentWidth()
    local check_w = selected and px(64) or 0
    local text_w = w - check_w - px(32)
    local file, idx = D.fontFile(face)
    local name_face = Theme.fileFace(file, 48, idx) or Theme.face(selected and "sans_bold" or "sans", 44)
    local sample_face = Theme.fileFace(file, 32, idx) or Theme.face("sans", 30)
    local texts = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = face, face = name_face, bold = selected, fgcolor = self.col.fg, max_width = text_w, padding = 0 },
        C.space(1, px(10)),
        TextWidget:new{ text = "The quick brown fox jumps over the lazy dog", face = sample_face, fgcolor = self.col.muted,
            max_width = text_w, padding = 0 },
    }
    local h = math.max(px(168), texts:getSize().h + 2 * px(26))
    local content = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
        C.box(text_w, h, texts, { valign = "center" }) }
    if selected then
        local check = C.box(check_w, h, C.text("✓", "sans_bold", 48, self.col.fg), { halign = "right", valign = "center" })
        check.overlap_align = "right"
        table.insert(content, check)
    end
    return VerticalGroup:new{ align = "left",
        C.hline(w, px(3), self.col.line),
        C.tappable(content, function()
            UIManager:nextTick(function()
                if self.on_pick then
                    -- the font for the book being read (from the Font panel)
                    self.on_pick(face)
                    self:close()
                    require("mh/ui/snackbar").show("Updated")
                else
                    D.setFont(face)
                    pickedAndBack(self)
                end
            end)
        end),
    }
end

-- Settings ---------------------------------------------------------------------------------

local Settings = Page:extend{
    back_to_top = false,
    swipe_home = true,
    title = "Settings",
    back_label = "Back",
}

function Settings:open(PageClass)
    PageClass:new{ ui = self.ui, on_close = function() self:refresh() end }:show()
end

--- "Update available" card at the top (design: Updates – Settings). While the
--- new build downloads it shows the progress; KOReader then restarts by itself.
function Settings:updateBanner(m)
    local w = self:contentWidth()
    local border, pad_h, pad_v = px(4), px(36), px(30)
    local inner = w - 2 * border - 2 * pad_h
    local job = Updater.job
    local downloading = job ~= nil or Updater.ready ~= nil
    local pct = Updater.ready and 100 or (job and job.pct or 0)
    local btn_w = px(220)
    local text_w = downloading and inner or (inner - btn_w - px(32))
    local title, sub
    if downloading then
        title = "Downloading " .. m.version .. "… " .. pct .. "%"
        sub = "KOReader restarts by itself when it’s done."
    else
        title = "Update available"
        sub = "Version " .. m.version .. " · " .. Updater.channelName()
        if m.size and m.size > 0 then sub = sub .. string.format(" · %.1f MB", m.size / 1048576) end
    end
    local texts = VerticalGroup:new{
        align = "left",
        C.text(title, "sans_bold", 40, self.col.fg, text_w),
        C.space(1, px(6)),
        C.text(sub, "sans_medium", 30, self.col.muted, text_w),
    }
    local row
    if downloading then
        row = texts
    else
        local btn = C.tappable(C.box(btn_w, px(104), C.text("Update", "sans_bold", 38, self.col.bg),
            { bg = self.col.fg, radius = px(10), halign = "center", valign = "center" }),
            function() UIManager:nextTick(function() self:runUpdate(m) end) end)
        row = HorizontalGroup:new{ align = "center", C.box(text_w, math.max(texts:getSize().h, px(104)), texts,
            { valign = "center" }), C.space(px(32), 1), btn }
    end
    local group = VerticalGroup:new{ align = "left", row }
    if downloading then
        table.insert(group, C.space(1, px(24)))
        table.insert(group, C.progress(inner, px(16), pct / 100,
            require("ffi/blitbuffer").gray(0.2), self.col.fg, px(8)))
    end
    local h = group:getSize().h + 2 * pad_v + 2 * border
    return VerticalGroup:new{ align = "left", C.space(1, px(48)),
        C.box(w, h, group, { border = border, border_color = self.col.fg, radius = px(16),
            pad_l = border + pad_h, pad_r = border + pad_h, pad_t = border + pad_v, pad_b = border + pad_v,
            valign = "center" }) }
end

--- Update: the download runs in the background; this page (and any page opened
--- later) follows its progress. The screen stays usable meanwhile.
function Settings:runUpdate(m)
    if Updater.job then return end
    if not require("mh/wifi").isConnected() then
        require("mh/ui/snackbar").show("Connect to Wi-Fi to update")
        return
    end
    local ok, err = Updater.start(m)
    if not ok then
        logger.warn("MinimalHome: update failed:", err)
        require("mh/ui/snackbar").show("Couldn’t update · still on " .. Updater.version(), 4)
    end
    self:refresh()
end

function Settings:show()
    Updater.listeners[self] = function() if not self.closed then self:refresh() end end
    return Page.show(self)
end

--- Wi-Fi just connected (e.g. after waking): look for a new build now.
function Settings:onNetworkConnected()
    self:refresh()
    Updater.checkSoon(Updater.SETTINGS_EVERY, function() if not self.closed then self:refresh() end end)
end

function Settings:onCloseWidget()
    Updater.listeners[self] = nil
    Page.onCloseWidget(self)
end

function Settings:blocks()
    local ui = self.ui
    local list = { function() return self:headerBlock() end }
    local found = (Updater.job and Updater.job.m) or Updater.ready or Updater.available()
    if found then
        table.insert(list, function() return self:updateBanner(found) end)
    end
    local function section(label, rows) table.insert(list, function() return self:section(label, rows) end) end

    local conn = {}
    if D.hasWifi() then
        local W = require("mh/wifi")
        local state = W.isOn() and (W.current() or "Not connected") or "Off"
        table.insert(conn, { label = "Wi-Fi", value = state,
            action = function()
                require("mh/ui/wifipopup"):new{ on_close = function() self:refresh() end }:show()
            end })
    end
    if D.hasSSH(ui) then
        table.insert(conn, { label = "SSH access", sub = D.sshInfo(ui), toggle = D.sshRunning(ui),
            action = function() D.toggleSSH(ui); self:refresh() end })
    end
    if #conn > 0 then section("CONNECTIVITY", conn) end

    section("DISPLAY", {
        { label = "Full refresh", sub = "Clears ghosting on e-ink", value = D.refreshLabel(D.refreshEvery()),
          action = function() D.cycleRefresh(); self:refresh() end },
        { label = "Screensaver", sub = "Shown when the device sleeps", value = D.screensaverLabel(),
          action = function() self:open(Screensaver) end },
    })

    local reading = {
        { label = "Default font", value = D.currentFont(), action = function() self:open(FontPicker) end },
    }
    if D.hasPageButtons() then
        local swapped = D.pageButtonsSwapped()
        table.insert(reading, { label = "Swap page-turn buttons",
            sub = swapped and "Top button: previous page" or "Top button: next page",
            toggle = swapped, action = function() D.toggleSwapPageButtons(); self:refresh() end })
    end
    section("READING", reading)

    local device = {
        { label = "Sleep after", sub = "When not in use", value = D.sleepLabel(D.sleepMinutes()),
          action = function() D.cycleSleep(ui); self:refresh() end },
    }
    if ui and ui.menu then
        table.insert(device, { label = "All KOReader settings", sub = "The full KOReader menu",
            action = function() ui.menu:onShowMenu() end })
    end
    section("DEVICE", device)

    table.insert(list, function()
        local w = self:contentWidth()
        local gap = px(28)
        local half = math.floor((w - gap) / 2)
        return VerticalGroup:new{
            align = "center",
            C.space(1, px(72)),
            HorizontalGroup:new{
                align = "center",
                self:button("↻  Restart KOReader", half, function() D.restartKOReader(ui) end),
                C.space(gap, 1),
                self:button("⇥  Exit to Kindle", half, function() D.exitKOReader(ui) end),
            },
            C.space(1, px(24)),
            C.text("Version " .. Updater.version() .. " · " .. Updater.channelName() .. " · " .. deviceName(),
                "sans_medium", 28, self.col.muted),
        }
    end)
    return list
end

Settings.Screensaver = Screensaver
Settings.FontPicker = FontPicker

function Settings.openPage(ui, opts)
    opts = opts or {}
    logger.info("MinimalHome: opening Settings")
    local ok, page = pcall(function()
        return Settings:new{ ui = ui, on_close = opts.on_close, on_library_changed = opts.on_library_changed }:show()
    end)
    if not ok then
        logger.err("MinimalHome: could not open Settings:", page)
        notify("Settings could not open:\n" .. tostring(page))
        return nil
    end
    logger.info("MinimalHome: Settings shown")
    -- a new build on GitHub? (only with Wi-Fi on; the card appears when it is found)
    Updater.checkSoon(Updater.SETTINGS_EVERY, function()
        if not page.closed then page:refresh() end
    end)
    return page
end

return Settings
