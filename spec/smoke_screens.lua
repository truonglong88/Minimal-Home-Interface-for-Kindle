-- Smoke test for Settings, Screensaver, Font picker, quick panel and Finished screen.
-- Usage: luajit spec/smoke_screens.lua /path/to/koreader
local KO = arg[1] or error("pass the path to a KOReader checkout")
package.path = table.concat({ "spec/stubs/?.lua", "minimalhome.koplugin/?.lua", KO .. "/frontend/?.lua", package.path }, ";")
require("stubs_env")
local Blitbuffer = require("ffi/blitbuffer")

local failed, passed = 0, 0
local current = "screen"
local function check(name, fn)
    current = name:gsub("%s", "-")
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local OUT = arg[2]
local ops = Blitbuffer._ops
local results = {}
local function paint(w)
    if Blitbuffer._resetScreen then Blitbuffer._resetScreen() end
    ops.reset()
    w:paintTo(Blitbuffer.new(1264, 1680), 0, 0)
    results[#results + 1] = { scenario = current, page = #results + 1, scroll = 0, max = 0, ops = ops.list() }
end

local Library = require("mh/data/library")
Library.getCover = function() return nil end
Library.upNext = function()
    return { path = "/b/next.epub", title = "Số đỏ", authors = "Vũ Trọng Phụng", percent = 0.42,
        status = "reading", last_opened = os.time(), has_cover = false }
end

local fake_ui = {
    menu = { onShowMenu = function() end, exitOrRestart = function() end },
    SSH = { isRunning = function() return false end, start = function() end, stop = function() end },
}

check("storage label and row", function()
    local D = require("mh/device")
    assert(D.storageLabel(2.3e9, 4e9) == "2.3 GB free of 4 GB", D.storageLabel(2.3e9, 4e9))
    assert(D.storageLabel(850e6, 4e9) == "850 MB free of 4 GB", D.storageLabel(850e6, 4e9))
    local util = require("util")
    local orig = util.diskUsage
    util.diskUsage = function() return { total = 4e9, used = 1.7e9, available = 2.3e9 } end
    local free, total = D.storage("/mnt/us/documents")
    assert(free == 2.3e9 and total == 4e9, "storage read")
    local Settings = require("mh/ui/settings")
    local page = Settings:new{ ui = fake_ui }
    paint(page)
    util.diskUsage = orig
end)

check("settings page", function()
    local Settings = require("mh/ui/settings")
    local page = Settings:new{ ui = fake_ui }
    paint(page)
    page:scrollBy(2000)
    paint(page)
    page:refresh()
    assert(page.viewport:totalHeight() > 1680, "settings scrolls")
end)

check("settings opens from the home button and the quick panel", function()
    local UIManager = require("ui/uimanager")
    local shown = {}
    local orig_show, orig_tick = UIManager.show, UIManager.nextTick
    UIManager.show = function(_, w) shown[#shown + 1] = w end
    UIManager.nextTick = function(_, f) f() end
    local Settings = require("mh/ui/settings")
    local page = Settings.openPage(fake_ui, {})
    assert(page and shown[#shown] == page, "openPage shows the Settings page")
    -- the quick panel's Settings tile goes through the same entry point
    local QP = require("mh/ui/quickpanel")
    local opened = false
    local p = QP:new{ ui = fake_ui, on_settings = function() opened = Settings.openPage(fake_ui) ~= nil end }
    p:close()
    p.on_settings()
    assert(opened, "quick panel opens Settings")
    -- sub-pages open from Settings
    page:open(Settings.Screensaver)
    assert(shown[#shown].title == "Screensaver", "Screensaver page opens")
    UIManager.show, UIManager.nextTick = orig_show, orig_tick
end)

check("screensaver page", function()
    local Settings = require("mh/ui/settings")
    local D = require("mh/device")
    D.setScreensaver("cats")
    assert(D.currentScreensaver() == "cats", "image screensaver remembered")
    assert(G_reader_settings:readSetting("screensaver_type") == "document_cover")
    D.setScreensaver("book")
    assert(D.currentScreensaver() == "book" and D.screensaverLabel() == "Book cover")
    assert((G_reader_settings:readSetting("screensaver_dir") or ""):match("/screensavers/fallback$"),
        "coverless books fall back to the cats")
    local page = Settings.Screensaver:new{ ui = fake_ui }
    paint(page)
end)

check("font picker", function()
    local Settings = require("mh/ui/settings")
    local page = Settings.FontPicker:new{ ui = fake_ui, fonts = { "Literata", "Noto Serif" } }
    paint(page)
end)

check("device helpers", function()
    local D = require("mh/device")
    G_reader_settings:saveSetting("full_refresh_count", 6)
    D.cycleRefresh()
    assert(G_reader_settings:readSetting("full_refresh_count") == 12, "refresh cycles")
    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", 600)
    D.cycleSleep({})
    assert(G_reader_settings:readSetting("auto_suspend_timeout_seconds") == 900, "sleep cycles")
    assert(D.brightnessForLux(5000, 0, 24) == 0, "daylight: light off")
    assert(D.brightnessForLux(0, 0, 24) > 0, "dark: some light")
    assert(D.setAutoBrightness(true) == false, "no sensor reading: auto refused")
    D.setBrightness(30)
    assert(D.brightness() == 24, "brightness clamped")
    D.setBrightnessStep(6)
    assert(D.brightness() == 12 and D.brightnessStep() == 6, "12 steps over 0-24")
    D.setBrightnessStep(D.brightnessStep() + 1)
    assert(D.brightness() == 14, "one step = two hardware levels")
    D.ipAddress = function() return "192.168.1.6" end
    local ssh_ui = { SSH = { SSH_port = "2222", isRunning = function() return true end } }
    assert(D.sshInfo(ssh_ui) == "IP 192.168.1.6 · port 2222", "ssh line shows the address")
end)

check("cover white bands trimmed", function()
    package.loaded["mh/data/library"] = nil
    local Lib = require("mh/data/library")
    -- 100x150 cover: white 20 px left/right and 30 px top/bottom around the art
    local fake = { w = 100, h = 150, freed = false }
    function fake:getWidth() return self.w end
    function fake:getHeight() return self.h end
    function fake.getType() return 1 end
    function fake:free() self.freed = true end
    function fake.getPixel(_, x, y)
        local white = x < 20 or x >= 80 or y < 30 or y >= 120
        return { getColor8 = function() return { a = white and 255 or 40 } end }
    end
    local out = Lib.trimWhite(fake)
    assert(out ~= fake and fake.freed, "a new, trimmed buffer")
    assert(out:getWidth() == 60 and out:getHeight() == 90, "trimmed to the art: " .. out:getWidth() .. "x" .. out:getHeight())
    -- a cover with no white bands is left alone
    local plain = { w = 100, h = 150 }
    setmetatable(plain, { __index = fake })
    plain.getPixel = function() return { getColor8 = function() return { a = 40 } end } end
    assert(Lib.trimWhite(plain) == plain, "nothing to trim")
    Library = Lib
    Library.getCover = function() return nil end
end)

check("covers fill their frame (centre crop)", function()
    local scaled_to
    package.loaded["ui/renderimage"] = { scaleBlitBuffer = function(_, _bb, w, h) scaled_to = { w, h } return Blitbuffer.new(w, h) end }
    local C = require("mh/ui/components")
    -- a wide 400x300 image into a 340x480 frame: scale to 640x480, keep the middle 340
    local out = C.cropToFill(Blitbuffer.new(400, 300), 340, 480)
    assert(out and out:getWidth() == 340 and out:getHeight() == 480, "exact frame size")
    assert(scaled_to[1] == 640 and scaled_to[2] == 480, "scaled to cover: " .. scaled_to[1] .. "x" .. scaled_to[2])
    package.loaded["ui/renderimage"] = nil
end)

check("loading bar", function()
    local Screen = require("device").screen
    local refreshed
    Screen.bb = Blitbuffer.new(1264, 1680)
    Screen.refreshFast = function(_, x, y, w, h) refreshed = { x, y, w, h } end
    local LB = require("mh/loadingbar")
    LB.show(0.5, true)
    assert(refreshed and refreshed[2] == 0 and refreshed[3] == 1264 and refreshed[4] > 0, "bar painted along the top")
    LB.done()
end)

check("quick panel", function()
    local QP = require("mh/ui/quickpanel")
    local p = QP:new{ ui = fake_ui }
    paint(p)
    p:rebuild()
    assert(p.panel_h > 300 and p.panel_h < 1000, "panel height " .. tostring(p.panel_h))
end)

check("brightness bar drags", function()
    local D = require("mh/device")
    local QP = require("mh/ui/quickpanel")
    local p = QP:new{ ui = fake_ui }
    paint(p)
    local r = assert(p._bar_rect, "bar position known after paint")
    assert(p._bar_live, "light on in the stub")
    local y = r.y + math.floor(r.h / 2)
    local function at(x) return { x = x, y = y } end
    p:onMHPan(nil, { start_pos = at(r.x + 5), pos = at(r.x + math.floor(r.w * 0.25)) })
    paint(p)
    assert(D.brightnessStep() == 3, "dragged to a quarter: " .. D.brightnessStep())
    p:onMHPanRelease(nil, { pos = at(r.x + r.w) })
    assert(D.brightnessStep() == D.LIGHT_STEPS, "released at the end: " .. D.brightnessStep())
    paint(p)
    p:onMHSwipe(nil, { direction = "west", pos = at(r.x + r.w), distance = r.w })
    assert(D.brightnessStep() == 0, "flicked to the start: " .. D.brightnessStep())
end)

check("search screen", function()
    local UIManager = require("ui/uimanager")
    local tasks = {}
    local orig = { UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close }
    UIManager.scheduleIn = function(_, _, f) tasks[#tasks + 1] = f end
    UIManager.nextTick = function(_, f) tasks[#tasks + 1] = f end
    local shown = {}
    UIManager.show = function(_, w) shown[w] = true end
    UIManager.close = function(_, w) shown[w] = nil end
    local function run() while #tasks > 0 do table.remove(tasks, 1)() end end
    local Prefs = require("mh/data/prefs")
    Prefs.set("recent_searches", { "sapiens" })
    local opened
    local S = require("mh/ui/search")
    local s = S:new{
        books = {
            { path = "/b/1.epub", title = "Nhà giả kim", authors = "Paulo Coelho" },
            { path = "/b/2.epub", title = "Ông già và biển cả", authors = "Ernest Hemingway" },
            { path = "/b/3.epub", title = "Giã từ vũ khí", authors = "Ernest Hemingway" },
            { path = "/b/4.epub", title = "Đất rừng phương Nam", authors = "Đoàn Giỏi" },
            { path = "/b/5.epub", title = "Gió lạnh đầu mùa", authors = "Thạch Lam" },
            { path = "/b/6.epub", title = "Sapiens" },
        },
        cover_for = function(_, w, h) return require("mh/ui/components").space(w, h) end,
        on_open = function(p) opened = p end,
    }
    s:show(); run()
    assert(s.kb_visible and shown[s.keyboard], "keyboard comes up with the screen")
    paint(s)
    s.inputbox:addChars("g"); s.inputbox:addChars("i"); run()
    assert(#s.matches == 5 and not s.submitted, "matches as you type: " .. #s.matches)
    paint(s)
    s.inputbox:addChars("\n"); run()
    assert(s.submitted and not s.kb_visible, "Search lowers the keyboard")
    assert(Prefs.get("recent_searches")[1] == "gi", "remembered as a recent search")
    paint(s)
    s.inputbox:delChar(); s.inputbox:delChar(); s.inputbox:addChars("zzz"); run()
    assert(#s.matches == 0, "no matches")
    paint(s)
    s:openBook("/b/1.epub"); run()
    assert(opened == "/b/1.epub" and s.closed, "opening a book closes search")
    UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close = orig[1], orig[2], orig[3], orig[4]
end)

table.pack = table.pack or function(...) return { n = select("#", ...), ... } end

check("our keyboard types, shifts, switches modes", function()
    local UIManager = require("ui/uimanager")
    local orig = UIManager.scheduleIn
    UIManager.scheduleIn = function() end
    local typed, acted = "", false
    local box = { addChars = function(_, c) typed = typed .. c end, delChar = function() typed = typed:sub(1, -2) end }
    local K = require("mh/ui/keyboard")
    local kb = K:new{ inputbox = box, action = "Search", on_action = function() acted = true end, allow_vi = false }
    paint(kb)
    local function tap(key)
        for _, k in ipairs(kb.keys) do
            if k.key == key then
                kb:onMHKey(nil, { pos = { x = k.rect.x + 5, y = k.rect.y + 5 } })
                return
            end
        end
        error("no key " .. key)
    end
    assert(#kb.keys == 10 + 9 + 9 + 5, "letter layout: " .. #kb.keys)
    tap("⇧"); tap("h"); tap("i"); tap("space"); tap("⌫"); tap(".")
    assert(typed == "Hi.", "typed: " .. typed)
    tap("?123"); assert(kb.mode == "symbols"); paint(kb)
    tap("7"); assert(typed == "Hi.7")
    tap("ABC"); assert(kb.mode == "alpha")
    tap("action"); assert(acted, "action key")
    UIManager.scheduleIn = orig
end)

check("go to page dialog", function()
    local UIManager = require("ui/uimanager")
    local orig = { UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close }
    local tasks = {}
    UIManager.scheduleIn = function() end
    UIManager.nextTick = function(_, f) tasks[#tasks + 1] = f end
    UIManager.show = function() end
    UIManager.close = function() end
    local went
    local ui = {
        document = { getPageCount = function() return 300 end },
        getCurrentPage = function() return 12 end,
        toc = { getTocTitleByPage = function() return "Chapter 2" end },
        handleEvent = function(_, ev) went = ev end,
    }
    local G = require("mh/ui/gotopage")
    local g = G:new{ ui = ui }:show()
    assert(g.keyboard.mode == "numpad" and g.keyboard.action == "Go" and #g.keyboard.keys == 12, "number keypad")
    paint(g.keyboard)
    g.inputbox:addChars("4"); g.inputbox:addChars("x"); g.inputbox:addChars("2")
    assert(g.value == "42", g.value)
    paint(g)
    g.inputbox:addChars("\n")
    while #tasks > 0 do table.remove(tasks, 1)() end
    assert(went and went.handler == "onGotoPage" and went.args[1] == 42, "went to 42")
    UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close = orig[1], orig[2], orig[3], orig[4]
end)

check("font panel", function()
    local UIManager = require("ui/uimanager")
    local orig = UIManager.nextTick
    local events = {}
    UIManager.nextTick = function(_, f) f() end
    local ui = {
        font = { configurable = { font_size = 22, line_spacing = 100 }, font_face = "Literata" },
        typeset = { unscaled_margins = { 46, 15, 46, 15 } },
        styletweak = { isTweakEnabled = function() return false end,
            onToggleStyleTweak = function(_, id) events[#events + 1] = id end },
        handleEvent = function(_, ev) events[#events + 1] = ev.handler end,
    }
    local F = require("mh/ui/fontpanel")
    local f = F:new{ ui = ui }
    paint(f)
    f:setSize(24); f:setSpacing(120); f:setMargin(70); f:setLeft(true)
    assert(events[1] == "onSetFontSize" and events[2] == "onSetLineSpace" and events[3] == "onSetPageHorizMargins"
        and events[4] == "text_align_most_left", table.concat(events, ","))
    UIManager.nextTick = orig
end)

check("contents page", function()
    local toc = {
        { title = "One", page = 1, depth = 1 },
        { title = "Two", page = 20, depth = 1 },
        { title = "Two a", page = 25, depth = 2 },
        { title = "Three", page = 40, depth = 1 },
    }
    local ui = {
        toc = { toc = toc, fillToc = function() end },
        document = { getPageCount = function() return 60 end, info = {} },
        getCurrentPage = function() return 27 end,
        handleEvent = function() end,
    }
    local Contents = require("mh/ui/contents")
    assert(#Contents.entries(ui) == 4, "entries")
    assert(Contents.currentIndex(Contents.entries(ui), 27) == 3, "current chapter")
    local c = Contents:new{ ui = ui }
    paint(c)
    -- a long table of contents: laid out without building rows; the chapter being
    -- read sits two thirds of the way down
    local long = {}
    for i = 1, 400 do long[i] = { title = "Chapter " .. i, page = i * 2, depth = 1 } end
    ui.toc.toc = long
    ui.getCurrentPage = function() return 500 end
    local built = 0
    local orig_row = Contents.row
    Contents.row = function(...) built = built + 1; return orig_row(...) end
    local c2 = Contents:new{ ui = ui }
    Contents.row = orig_row
    assert(#c2.viewport.blocks >= 400, "every chapter listed: " .. #c2.viewport.blocks)
    assert(built < 30, "only visible rows built: " .. built)
    local b = c2.viewport.blocks[c2.current_block]
    local y = c2.view_top + b.y + b.h / 2 - c2.viewport.scroll
    local H = require("device").screen:getHeight()
    assert(math.abs(y - H * 2 / 3) < 4, "current chapter at 2/3: " .. y)
    -- a row half hidden under the header must not catch the tap on "‹ Back"
    local Theme = require("mh/theme")
    c2.viewport:scrollTo(b.y + math.floor(b.h / 2))
    paint(c2)
    local events = {}
    ui.handleEvent = function(_, ev) events[#events + 1] = ev.handler end
    local Geom = require("ui/geometry")
    local Event = require("ui/event")
    local UIManager = require("ui/uimanager")
    local orig_tick = UIManager.nextTick
    local ticks = {}
    UIManager.nextTick = function(_, f) ticks[#ticks + 1] = f end
    c2:handleEvent(Event:new("Gesture", { ges = "tap",
        pos = Geom:new{ x = Theme.px(Theme.margin_h) + Theme.px(60), y = c2.view_top - math.floor(b.h / 4), w = 0, h = 0 } }))
    UIManager.nextTick = orig_tick
    for _, f in ipairs(ticks) do f() end
    assert(c2.closed, "Back closes the contents")
    for _, h in ipairs(events) do assert(h ~= "onGotoPage" and h ~= "onGotoXPointer", "tap went through to a row: " .. h) end
    assert(Contents.swipe_home, "swipe up goes Home from the contents")
end)

if io.open("frontend/ui/data/keyboardlayouts/vi_keyboard.lua") then
    check("VI key types Telex", function()
        package.loaded["ffi/utf8proc"] = package.loaded["ffi/utf8proc"] or { uppercase_dumb = string.upper }
        local UIManager = require("ui/uimanager")
        local orig = UIManager.scheduleIn
        UIManager.scheduleIn = function() end
        local text = ""
        local box = {}
        function box:addChars(c) text = text .. c end
        function box:delChar() text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") end
        local kb = require("mh/ui/keyboard"):new{ inputbox = box }
        if kb.lang ~= "VI" then kb:press("lang") end
        for ch in ("vieejt"):gmatch(".") do kb:press(ch) end
        kb:press("lang") -- back to EN
        UIManager.scheduleIn = orig
        assert(text == "việt", "telex: " .. text)
    end)
end

check("KOReader messages look like the snackbar", function()
    local Prefs = require("mh/data/prefs")
    Prefs.set("enabled", true)
    local M = require("mh/messages")
    M.install()
    local InfoMessage = require("ui/widget/infomessage")
    local face = require("ui/font"):getFace("cfont", 20)
    local m = InfoMessage:new{ text = "Connecting to Wi-Fi…", face = face }
    assert(m.show_icon == false, "no (i) icon")
    assert(m.movable.box, "drawn as a snackbar")
    local H = require("device").screen:getHeight()
    assert(m.movable.dimen.y + m.movable.dimen.h == H - math.floor(H / 3), "a third from the bottom")
    paint(m)
    local long = InfoMessage:new{ text = string.rep("long text ", 60), face = face }
    assert(long.show_icon == false and not long.movable.box, "long message keeps KOReader's box")
    assert(M.fits("Wi-Fi off") and M.fits("a\nb\nc") and not M.fits("1\n2\n3\n4\n5\n6\n7"))
end)

check("Home ignores the drag that brought it up", function()
    local Home = require("mh/ui/home")
    local scrolled = 0
    local h = setmetatable({ calm_until = require("ui/time").now() + require("ui/time").s(5),
        scrollBy = function(_, d) scrolled = scrolled + d end, startsOnStatusBar = function() return false end },
        { __index = Home })
    h:onMHPan(nil, { relative = { x = 0, y = -300 }, pos = { x = 10, y = 900 } })
    h:onMHPanRelease()
    h:onMHSwipe(nil, { direction = "north", distance = 400 })
    assert(scrolled == 0, "no scroll: " .. scrolled)
    h.calm_until = 0
    h:onMHSwipe(nil, { direction = "north", distance = 400, pos = { x = 10, y = 900 } })
    assert(scrolled > 0, "scrolls afterwards")
end)

local function withUI(fn)
    local UIManager = require("ui/uimanager")
    local orig = { UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close, UIManager.forceRePaint, UIManager.broadcastEvent }
    local tasks, shown = {}, {}
    UIManager.scheduleIn = function(_, _, f, ...) local a = { ... }; tasks[#tasks + 1] = function() f(table.unpack and table.unpack(a) or unpack(a)) end end
    UIManager.nextTick = function(_, f) tasks[#tasks + 1] = f end
    UIManager.show = function(_, w) shown[#shown + 1] = w end
    UIManager.close = function(_, w) for i, x in ipairs(shown) do if x == w then table.remove(shown, i) break end end end
    UIManager.forceRePaint = function() end
    UIManager.broadcastEvent = function() end
    local function run(n)
        n = n or 200
        while #tasks > 0 and n > 0 do n = n - 1; table.remove(tasks, 1)() end
    end
    local ok, err = pcall(fn, run, shown)
    UIManager.scheduleIn, UIManager.nextTick, UIManager.show, UIManager.close, UIManager.forceRePaint, UIManager.broadcastEvent =
        orig[1], orig[2], orig[3], orig[4], orig[5], orig[6]
    if not ok then error(err, 0) end
end

local function fakeNetwork()
    local nm = { on = true, cur = "Home 5G", saved = {}, joined = {} }
    function nm:isWifiOn() return self.on end
    function nm:isConnected() return self.on and self.cur ~= nil end
    function nm:getCurrentNetwork() return self.cur and { ssid = self.cur } end
    function nm:getNetworkList()
        return {
            { ssid = "Home 5G", signal_quality = 81, flags = "WPA2-PSK", password = "x", connected = self.cur == "Home 5G" },
            { ssid = "Cafe Wi-Fi", signal_quality = 56, flags = "WPA2-PSK", password = "y" },
            { ssid = "Neighbour-2G", signal_quality = 31, flags = "WPA2-PSK" },
            { ssid = "Free", signal_quality = 6, flags = "NONE" },
        }
    end
    function nm:saveNetwork(n) self.saved[#self.saved + 1] = n end
    function nm:authenticateNetwork(n) self.joined[#self.joined + 1] = n.ssid; if self.fail then self.cur = nil else self.cur = n.ssid end; return true end
    function nm:obtainIP() end
    function nm:queryNetworkState() end
    function nm:disableWifi(cb) self.on = false; self.cur = nil; if cb then cb() end end
    function nm:toggleWifiOn(cb) self.on = true; if cb then cb() end end
    package.loaded["ui/network/manager"] = nm
    return nm
end

check("Wi-Fi popup: list, join a saved network, password for a new one", function()
    withUI(function(run, shown)
        local nm = fakeNetwork()
        local snacks = {}
        local Snackbar = require("mh/ui/snackbar")
        local orig_show = Snackbar.show
        Snackbar.show = function(t) snacks[#snacks + 1] = t end
        local P = require("mh/ui/wifipopup")
        local p = P:new{}:show()
        run(5)
        assert(p.on and p.current == "Home 5G" and #p.networks == 4, "scanned")
        paint(p)
        -- saved network: joins at once, snackbar after
        p:pick(p.networks[2])
        assert(p.connecting == "Cafe Wi-Fi")
        paint(p)
        run()
        assert(snacks[1] == "Connected to Cafe Wi-Fi", tostring(snacks[1]))
        assert(P.active.current == "Cafe Wi-Fi" and not P.active.connecting)
        -- new locked network: popup gives way to the password card
        P.active:pick(P.active.networks[3])
        local card = shown[#shown - 1]
        assert(card.network and card.network.ssid == "Neighbour-2G", "password card")
        assert(not card.hidden, "password shown by default")
        card.inputbox:addChars("a"); card.inputbox:addChars("b")
        paint(card)
        card.hidden = true; card:rebuild(); paint(card)
        card:join()
        assert(P.active and P.active.connecting == "Neighbour-2G", "back to the popup, connecting")
        run()
        assert(nm.saved[#nm.saved].password == "ab", "password saved")
        assert(snacks[2] == "Connected to Neighbour-2G", tostring(snacks[2]))
        -- failure
        nm.fail = true
        P.active:pick(P.active.networks[4])
        run(300)
        assert(snacks[3] == "Couldn’t connect to Free", tostring(snacks[3]))
        -- off
        P.active:toggleWifi()
        assert(not P.active.on)
        paint(P.active)
        P.active:close()
        Snackbar.show = orig_show
    end)
    package.loaded["ui/network/manager"] = nil
end)

check("confirm card and KOReader's yes / no questions", function()
    withUI(function(run)
        local yes
        local Confirm = require("mh/ui/confirm")
        local c = Confirm.show{ title = "Delete this book?", text = "Gone for good.", ok_text = "Delete",
            ok_callback = function() yes = true end }
        paint(c)
        c:answer(true)
        assert(yes, "ok runs")
        require("mh/data/prefs").set("enabled", true)
        local M = require("mh/messages")
        M.install()
        local ok_ran
        local ConfirmBox = require("ui/widget/confirmbox")
        local box = ConfirmBox:new{ text = "Turn on Wi-Fi?\nThis needs a network connection.", ok_text = "Turn on",
            ok_callback = function() ok_ran = true end, face = require("ui/font"):getFace("cfont", 20) }
        assert(box.movable.dimen.w > 0, "drawn as our card")
        paint(box)
        assert(M.rewrite("No reader engine for this file or invalid file.") == "Couldn’t open this book")
        run()
        assert(not ok_ran)
    end)
end)

check("delete a book", function()
    local gone
    local ui = { deleteFile = function(_, path, is_file) gone = is_file and path; return true end }
    assert(require("mh/device").deleteBook(ui, "/b/x.epub") and gone == "/b/x.epub")
end)

check("Settings: swipe up from the bottom edge goes Home; overlays close on sleep", function()
    withUI(function(run)
        local UIManager = require("ui/uimanager")
        local Settings = require("mh/ui/settings")
        local s1 = Settings:new{ ui = {} }
        local fp = Settings.FontPicker:new{ ui = {} }
        UIManager._window_stack = { { widget = s1 }, { widget = fp } }
        local H = require("device").screen:getHeight()
        fp:onMHSwipe(nil, { direction = "north", distance = 300, pos = { x = 500, y = H - 50 } })
        run()
        assert(s1.closed and fp.closed, "both pages closed")
        UIManager._window_stack = nil
        -- scrolling a list near the bottom is not "Home": only a 150 px pull from the edge strip is
        local c2 = Settings:new{ ui = {} }
        UIManager._window_stack = { { widget = c2 } }
        c2:onMHSwipe(nil, { direction = "north", distance = 300, pos = { x = 500, y = H - 180 } })
        run()
        assert(not c2.closed, "a swipe that starts on the list scrolls it")
        c2:onMHSwipe(nil, { direction = "north", distance = 100, pos = { x = 500, y = H - 30 } })
        run()
        assert(not c2.closed, "a short swipe from the edge scrolls")
        c2:onMHPan(nil, { relative = { x = 0, y = -120 }, pos = { x = 500, y = H - 150 } })
        c2:onMHPanRelease()
        run()
        assert(not c2.closed, "a short drag from the edge scrolls")
        c2:onMHPan(nil, { relative = { x = 0, y = -160 }, pos = { x = 500, y = H - 30 - 160 } })
        c2:onMHPanRelease()
        run()
        assert(c2.closed, "a 150 px drag from the edge strip goes Home")
        UIManager._window_stack = nil
        local c = require("mh/ui/confirm"):new{ title = "x" }
        c:onSuspend()
        assert(c.closed, "confirm closes on sleep")
    end)
end)

check("Wi-Fi off while asleep, back on when waking only if it was on", function()
    withUI(function(run)
        local nm = fakeNetwork()
        local W = require("mh/wifi")
        local radio = {}
        nm.toggleWifiOn = function(self, cb) self.on = true; radio[#radio + 1] = "on"; if cb then cb() end end
        local Device = require("device")
        local orig = Device.isKindle
        Device.isKindle = function() return false end
        W.sleep(); run()
        assert(not nm.on, "off while asleep")
        W.sleep(); run() -- a second "going to sleep"
        W.wake(); run()
        assert(nm.on and radio[1] == "on", "back on")
        nm.on = false
        W.sleep(); W.wake(); run()
        assert(not nm.on and #radio == 1, "stays off")
        Device.isKindle = orig
    end)
    package.loaded["ui/network/manager"] = nil
end)

check("light goes out when the Kindle sleeps and comes back on wake", function()
    withUI(function(run)
        local p = require("device"):getPowerDevice()
        local hw = 12
        p.isFrontlightOnHW = function() return hw > 0 end
        p.fl_intensity = 12
        p.is_fl_on = true
        local offs = 0
        p.turnOffFrontlightHW = function(self) offs = offs + 1; hw = 0; self.is_fl_on = false end
        p.turnOnFrontlightHW = function(self) hw = self.fl_intensity end
        require("mh/data/prefs").set("light_off", false)
        local D = require("mh/device")
        D.lightOffForSleep()
        run()
        assert(offs == 4 and hw == 0, "off now and three times more: " .. offs)
        assert(p.is_fl_on == true, "KOReader still thinks it is on")
        -- the Kindle says "going to sleep" twice: the second must not forget the light was on
        D.lightOffForSleep(); run()
        p.turnOnFrontlight = function(self) if self.is_fl_on then return end; hw = self.fl_intensity; self.is_fl_on = true end
        D.lightAfterSleep()
        run()
        assert(hw == 12, "back on after waking")
        -- the toggle works even when KOReader's flag is stale (says on, light is off)
        hw = 0; p.is_fl_on = true
        D.setLightOn(true)
        assert(hw == 12, "toggle relights")
        -- light was off before sleeping: stays off
        hw = 0; p.is_fl_on = false
        D.lightOffForSleep(); run(); D.lightAfterSleep(); run()
        assert(hw == 0, "stays off")
        p.turnOffFrontlightHW, p.turnOnFrontlightHW, p.isFrontlightOnHW, p.turnOnFrontlight = nil, nil, nil, nil
    end)
end)

check("reading menu: ‹ › step a page, greyed at the ends", function()
    withUI(function(run)
        local events = {}
        local page = 1
        local ui = {
            document = { getPageCount = function() return 3 end, info = {} },
            getCurrentPage = function() return page end,
            handleEvent = function(_, ev) events[#events + 1] = ev end,
            doc_props = { display_title = "Book" },
        }
        local RM = require("mh/ui/readermenu")
        local m = RM:new{ ui = ui }
        m.currentPage = function() return page end
        paint(m)
        m:step(-1)
        assert(#events == 0, "no page before the first")
        m:step(1)
        assert(events[1] and events[1].handler == "onGotoViewRel" and events[1].args[1] == 1, "next page")
        page = 3
        m:step(1)
        assert(#events == 1, "no page after the last")
        run()
    end)
end)

check("low battery: snackbar at 20 %, popup at 5 % that only OK closes", function()
    withUI(function(run, shown)
        local Device = require("device")
        local p = Device:getPowerDevice()
        local orig_cap, orig_chg = p.getCapacity, p.isCharging
        local cap, chg = 50, false
        p.getCapacity = function() return cap end
        p.isCharging = function() return chg end
        local Prefs = require("mh/data/prefs")
        Prefs.set("battery_warned", nil)
        local Snackbar = require("mh/ui/snackbar")
        local orig_show = Snackbar.show
        local snacks = {}
        Snackbar.show = function(t) snacks[#snacks + 1] = t end
        local B = require("mh/battery")
        B.check()
        assert(#snacks == 0 and not B.popup, "nothing at 50 %")
        cap = 20; B.check()
        assert(snacks[1] == "Battery low · 20%", tostring(snacks[1]))
        cap = 19; B.check()
        assert(#snacks == 1, "shown once")
        cap = 5; B.check()
        local pop = B.popup
        assert(pop and pop.sticky and shown[#shown] == pop, "5 %: popup")
        paint(pop)
        local Geom = require("ui/geometry")
        pop:onMHTapOutside(nil, { pos = Geom:new{ x = 5, y = 5, w = 0, h = 0 } })
        pop:onClose()
        pop:onSuspend()
        assert(not pop.closed, "only OK closes it")
        assert(pop:onMHSwallowKey(), "page buttons swallowed")
        cap = 4; B.check()
        assert(B.popup == pop, "not shown twice")
        chg = true; B.check()
        run()
        assert(pop.closed and not B.popup, "charger closes it")
        cap = 30; B.check()
        assert(Prefs.get("battery_warned") == nil, "charged above 25 %: armed again")
        chg = false; cap = 5; B.check()
        local pop2 = B.popup
        assert(pop2, "warns again on the next discharge")
        pop2:answer(false)
        run()
        assert(pop2.closed and not B.popup, "OK closes it")
        Snackbar.show = orig_show
        p.getCapacity, p.isCharging = orig_cap, orig_chg
        Prefs.set("battery_warned", nil)
    end)
end)

check("Sync books: reads the folder again and says how many are new", function()
    withUI(function(run)
        local Library = require("mh/data/library")
        local orig = Library.load
        local list = {
            { path = "/b/a.epub", title = "A", authors = "X", status = "new", has_cover = false },
            { path = "/b/b.epub", title = "B", authors = "Y", status = "new", has_cover = false },
        }
        Library.load = function()
            local out = {}
            for i, b in ipairs(list) do out[i] = b end
            return out, {}
        end
        local Snackbar = require("mh/ui/snackbar")
        local orig_show = Snackbar.show
        local snacks = {}
        Snackbar.show = function(t) snacks[#snacks + 1] = t end
        local Home = require("mh/ui/home")
        local h = Home:new{ ui = {} }
        paint(h)
        list[3] = { path = "/b/c.epub", title = "C", authors = "Z", status = "new", has_cover = false }
        list[4] = { path = "/b/d.epub", title = "D", authors = "Z", status = "new", has_cover = false }
        h:syncBooks()
        assert(h.syncing, "Syncing… while it reads")
        paint(h)
        run()
        assert(not h.syncing and #h.books == 4, "four books now")
        assert(snacks[#snacks] == "2 new books", tostring(snacks[#snacks]))
        h:syncBooks(); run()
        assert(snacks[#snacks] == "No new books", tostring(snacks[#snacks]))
        Library.load, Snackbar.show = orig, orig_show
        h:onClose()
    end)
end)

check("comic mode: found by sampling, full screen, Auto / On / Off", function()
    local Comic = require("mh/comic")
    local function fakeUI(text_for)
        local store = {}
        local events = {}
        local ui
        ui = {
            rolling = true,
            doc_settings = {
                readSetting = function(_, k) return store[k] end,
                saveSetting = function(_, k, v) store[k] = v end,
            },
            document = {
                configurable = {},
                getPageCount = function() return 200 end,
                getPageXPointer = function(_, p) return p end,
                getTextFromXPointers = function(_, a) return text_for(a) end,
            },
            styletweak = { getCssText = function() return "/* tweaks */" end },
            view = { footer = { mode = 1, mode_list = { off = 0 },
                applyFooterMode = function(f, m) f.mode = m end } },
            handleEvent = function(_, ev) events[#events + 1] = ev.handler end,
        }
        return ui, store, events
    end
    local prose = string.rep("lorem ipsum dolor sit amet ", 40)
    -- a comic whose first pages are text (title, credits): still a comic
    local ui, store, events = fakeUI(function(p) return p <= 6 and prose or "" end)
    Comic.prepare(ui)
    Comic.onReady(ui)
    assert(store.minimalhome_comic_auto == true, "picture book found")
    assert(ui._minimalhome_comic and ui.view.footer.mode == 0, "status line hidden")
    assert(ui.document.configurable.t_page_margin == 0, "no margins")
    assert(ui.styletweak:getCssText():find("margin: 0", 1, true), "comic CSS added")
    local n = #events
    -- next time the book opens: decided already, set up before layout, nothing re-rendered
    local ui2 = fakeUI(function() return "" end)
    ui2.doc_settings = ui.doc_settings
    Comic.prepare(ui2)
    assert(ui2._minimalhome_comic and ui2.view.footer.mode == 0, "remembered")
    Comic.onReady(ui2)
    -- a novel with a few picture pages stays a text book
    local ui3, store3 = fakeUI(function(p) return (p % 50 == 0) and "" or prose end)
    Comic.prepare(ui3); Comic.onReady(ui3)
    assert(store3.minimalhome_comic_auto == false and not ui3._minimalhome_comic, "novel untouched")
    -- On / Off by hand
    Comic.setMode(ui3, "on")
    assert(ui3._minimalhome_comic and ui3.view.footer.mode == 0, "On")
    Comic.setMode(ui3, "off")
    assert(ui3._minimalhome_comic == false and ui3.view.footer.mode == 1, "Off: status line back")
    assert(ui3.document.configurable.t_page_margin == require("mh/reader").MARGINS.t, "Off: our margins back")
    assert(Comic.hint(ui3) == "Always as a text book", Comic.hint(ui3))
    assert(n > 0, "events sent on the first open")
    -- blank page check: an all-white page is blank; one dark pixel in a sampled cell is not
    local white = { getPixel = function() return { a = 255 } end }
    assert(Comic.isBlank(white, 0, 0, 1264, 1680), "white page is blank")
    local ink = { getPixel = function(_, x, y) return { a = (x > 600 and y > 800) and 20 or 255 } end }
    assert(not Comic.isBlank(ink, 0, 0, 1264, 1680), "a picture is not blank")
    -- after a blank page is drawn in comic mode, the reader goes on in the same direction
    local UIManager = require("ui/uimanager")
    local orig_tick = UIManager.nextTick
    local ticks = {}
    UIManager.nextTick = function(_, f) ticks[#ticks + 1] = f end
    local sent = {}
    local ui4 = { _minimalhome_comic = true,
        document = { _document = {}, getCurrentPage = function() return 5 end, getPageCount = function() return 50 end },
        view = { dimen = { w = 1264, h = 1680 }, paintTo = function() end },
        handleEvent = function(_, ev) sent[#sent + 1] = ev end }
    Comic.hookBlankPages(ui4)
    ui4.view:onPageUpdate(4); ui4.view:onPageUpdate(5)
    ui4.view:paintTo(white, 0, 0)
    for _, f in ipairs(ticks) do f() end
    UIManager.nextTick = orig_tick
    assert(sent[1] and sent[1].handler == "onGotoViewRel" and sent[1].args[1] == 1, "blank page skipped forward")

    -- known blank pages (found ahead from the HTML) are passed over before being drawn
    local html = { [3] = '<div><img src="p3.jpg"/></div>', [4] = "<p> </p>", [5] = "<p>Chapter 2</p>" }
    local doc = { _document = {}, getPageXPointer = function(_, p) return p end,
        getHTMLFromXPointers = function(_, a) return html[a] or "<img/>" end,
        getPageCount = function() return 10 end, getCurrentPage = function() return 4 end }
    assert(not Comic.pageIsBlank(doc, 3, 10), "picture page")
    assert(Comic.pageIsBlank(doc, 4, 10), "empty page")
    assert(not Comic.pageIsBlank(doc, 5, 10), "words are not blank")
    local sent5 = {}
    local ui5 = { _minimalhome_comic = true, document = doc, view = { paintTo = function() end },
        handleEvent = function(_, ev) sent5[#sent5 + 1] = ev end }
    Comic.hookBlankPages(ui5)
    ui5._minimalhome_blank, ui5._minimalhome_blank_total = { [4] = true }, 10
    ui5.view:onPageUpdate(3)
    assert(ui5.view:onPageUpdate(4) == true and sent5[1] and sent5[1].args[1] == 1, "page 4 skipped before drawing")
    -- a book closed while the scan runs (KOReader sets _document to false): no more calls
    local calls = 0
    local doc6 = { _document = {}, getPageCount = function() return 100 end,
        getPageXPointer = function(_, p) calls = calls + 1; return p end,
        getHTMLFromXPointers = function() return "<img/>" end }
    local ui6 = { _minimalhome_comic = true, document = doc6 }
    local orig_in = UIManager.scheduleIn
    local queued = {}
    UIManager.scheduleIn = function(_, _, f) queued[#queued + 1] = f end
    Comic.scan(ui6)
    table.remove(queued, 1)() -- first step runs while open
    local before = calls
    doc6._document = false   -- KOReader closed the book
    while #queued > 0 do table.remove(queued, 1)() end
    UIManager.scheduleIn = orig_in
    assert(before > 0 and calls == before, "no calls on a closed book: " .. calls .. " vs " .. before)
    assert(not Comic.pageIsBlank(doc6, 5, 100), "closed book: nothing read")
    -- CBZ: page mode (never scrolled into the next picture), whole page, no status line
    local function pagingUI(file)
        local store, ev = {}, {}
        return { paging = true, document = { file = file },
            doc_settings = { readSetting = function(_, k) return store[k] end, saveSetting = function(_, k, v) store[k] = v end },
            view = { footer = { mode = 1, mode_list = { off = 0 }, applyFooterMode = function(f, m) f.mode = m end } },
            handleEvent = function(_, e) ev[#ev + 1] = e end }, ev
    end
    local cbz, ev7 = pagingUI("/mnt/us/documents/Hirayasumi.cbz")
    Comic.prepare(cbz)
    assert(cbz.view.footer.mode == 0, "CBZ: status line hidden from the start")
    Comic.onReady(cbz)
    local got = {}
    for _, e in ipairs(ev7) do got[e.handler] = e.args[1] end
    assert(got.onSetScrollMode == false and got.onSetZoomMode == "page", "CBZ: page mode, whole page")
    local pdf, ev8 = pagingUI("/mnt/us/documents/manual.pdf")
    Comic.prepare(pdf); Comic.onReady(pdf)
    assert(#ev8 == 0 and pdf.view.footer.mode == 1, "PDF untouched")
    -- clock and % of the book on white labels over the picture
    local Blitbuffer = require("ffi/blitbuffer")
    local Prefs = require("mh/data/prefs")
    local was_style = Prefs.get("reader_style")
    Prefs.set("reader_style", true)
    local ov = { paging = { current_page = 19 }, _minimalhome_comic = true,
        document = { _document = {}, getPageCount = function() return 50 end },
        view = { paintTo = function(_, b) b:fill(Blitbuffer.COLOR_BLACK) end } }
    assert(Comic.percent(ov) == "38%", tostring(Comic.percent(ov)))
    Comic.hookOverlay(ov)
    local ops = Blitbuffer._ops
    local bb = setmetatable({ w = 1264, h = 1680 }, getmetatable(Blitbuffer.new(1, 1)))
    bb.offscreen, bb._list = nil, nil
    ops.reset(); ov.view:paintTo(bb, 0, 0)
    local white_rects, texts = {}, {}
    for _, op in ipairs(ops.list()) do
        if op[1] == "rect" and op[6] == 0 and (op[7] or 0) > 0 then white_rects[#white_rects + 1] = op end
        if op[1] == "text" then texts[#texts + 1] = op end
    end
    assert(#white_rects == 2, "two white labels: " .. #white_rects)
    local tl, br = white_rects[1], white_rects[2]
    assert(tl[2] == 72 and tl[3] == 26 and tl[5] == 60, "clock label top left")
    assert(br[2] + br[4] == 1264 - 81 and br[3] + br[5] == 1680 - 21, "% label bottom right")
    local found = false
    for _, t in ipairs(texts) do if tostring(t[4]):find("38%%") then found = true end end
    assert(found or #texts >= 2, "label text drawn")
    ov._minimalhome_comic = false
    ops.reset(); ov.view:paintTo(bb, 0, 0)
    for _, op in ipairs(ops.list()) do assert(not (op[1] == "rect" and op[6] == 0 and (op[7] or 0) > 0), "no labels when off") end
    Prefs.set("reader_style", was_style)
end)

check("Folders view: folder rows, order inside a folder, folder page", function()
    local Model = require("mh/data/model")
    local root = "/mnt/us/documents"
    local function bk(p, title, status, pct, opened)
        return { path = root .. "/" .. p, title = title, authors = "", status = status, percent = pct,
            last_opened = opened, has_cover = false }
    end
    local books = {
        bk("Ninja loan thi/Ninja 10.cbz", "Ninja 10", "new"),
        bk("Ninja loan thi/Ninja 2.cbz", "Ninja 2", "complete", 1, 100),
        bk("Ninja loan thi/Ninja 3.cbz", "Ninja 3", "reading", 0.45, 300),
        bk("Ninja loan thi/Ninja 4.cbz", "Ninja 4", "reading", 0.1, 200),
        bk("Ninja loan thi/Ninja 1.cbz", "Ninja 1", "complete", 1, 50),
        bk("Ninja loan thi/Ninja 5.cbz", "Ninja 5", "new"),
        bk("Bac si quai di/Tap 1.cbz", "Bác sĩ 1", "new"),
        bk("Hirayasumi.cbz", "Hirayasumi", "reading", 0.12, 400),
    }
    local folders, loose = Model.groupByFolder(books, root)
    assert(#folders == 2 and folders[1].name == "Bac si quai di" and folders[2].name == "Ninja loan thi", "folders A → Z")
    assert(#loose == 1 and loose[1].title == "Hirayasumi", "single books after")
    local order = {}
    for i, b in ipairs(folders[2].ordered) do order[i] = b.title end
    assert(table.concat(order, ",") == "Ninja 3,Ninja 4,Ninja 5,Ninja 10,Ninja 1,Ninja 2",
        "reading (last opened first), unread (2 before 10), finished: " .. table.concat(order, ","))
    assert(folders[2].top.title == "Ninja 3", "folder cover = the top book")
    local count, reading = Model.folderSummary(folders[2])
    assert(count == "6 volumes" and reading.title == "Ninja 3" and Model.volumeLabel(reading) == "vol. 3", "summary")
    -- KOReader's home is /mnt/us and every book is in documents/: start inside it
    assert(Model.foldersRoot(books, "/mnt/us") == root, "steps into documents: " .. Model.foldersRoot(books, "/mnt/us"))
    -- every series inside one Comics folder: step into it too
    local comics = {}
    for i, b in ipairs(books) do
        if b.path:find("/Ninja") or b.path:find("/Bac si") then
            comics[#comics + 1] = { path = b.path:gsub("/documents/", "/documents/Comics/"), title = b.title }
        end
    end
    assert(Model.foldersRoot(comics, "/mnt/us") == root .. "/Comics", Model.foldersRoot(comics, "/mnt/us"))
    -- a single series stays a folder row
    local one = { { path = root .. "/Ninja loan thi/a.cbz", title = "a" }, { path = root .. "/Ninja loan thi/b.cbz", title = "b" } }
    assert(Model.foldersRoot(one, "/mnt/us") == root, Model.foldersRoot(one, "/mnt/us"))

    withUI(function(run, shown)
        local Library = require("mh/data/library")
        local orig = Library.load
        Library.load = function() return books, {} end
        local Prefs = require("mh/data/prefs")
        Prefs.set("books_folder", root)
        Prefs.set("sort_key", "folders")
        local Home = require("mh/ui/home")
        local h = Home:new{ ui = {} }
        assert(h.entries and h.entries[1].folder and h.entries[3].book, "entries: 2 folders then 1 book")
        h.viewport:scrollTo(h.list_header_y or 0)
        paint(h)
        h:openFolder(folders[2])
        local page = shown[#shown]
        assert(page and page.title == "Ninja loan thi", "folder page opened")
        assert(page.subtitle == "6 volumes · 2 finished · reading vol. 3", page.subtitle)
        paint(page)
        -- open a book from the folder: Home remembers the way back
        local opened
        local orig_open = h.openBook
        h.openBook = function(_, path, trail) opened = { path = path, trail = trail } end
        page:openBook(page.books[1].path)
        h.openBook = orig_open
        assert(opened and opened.trail and opened.trail[1] == root .. "/Ninja loan thi", "folder trail kept")
        assert(page.closed, "folder page closed for the book")
        -- ‹ Back in the book: the new Home opens that folder again
        Home.return_folders, Home.back_pressed = opened.trail, true
        local n0 = #shown
        local h2 = Home:new{ ui = {} }
        run()
        local reopened = shown[#shown]
        assert(#shown > n0 and reopened.folder and reopened.folder.path == root .. "/Ninja loan thi", "back to the folder")
        assert(Home.back_pressed == nil and Home.return_folders == nil, "used once")
        reopened:close()
        h2:onClose()
        -- swiping up for Home (no ‹ Back): plain Home
        Home.return_folders, Home.back_pressed = opened.trail, nil
        local n1 = #shown
        local h3 = Home:new{ ui = {} }
        run()
        assert(#shown == n1, "swipe Home stays on Home")
        h3:onClose()
        Library.load = orig
        Prefs.set("sort_key", "recent")
        Prefs.set("books_folder", nil)
        h:onClose()
    end)
end)

check("scrollbars: only the thumb is grabbed; other drags scroll as usual", function()
    withUI(function()
        local C = require("mh/ui/components")
        local Settings = require("mh/ui/settings")
        local page = Settings:new{ ui = fake_ui }
        paint(page)
        local W, H = page.dimen.w, page.dimen.h
        local vp = page.viewport
        local max = vp:maxScroll()
        assert(max > 0, "settings scrolls")
        -- at the top the bar is hidden: a drag near the edge scrolls the page
        assert(not page:barReach({ x = W - 20, y = page.view_top + 20 }), "hidden bar: not grabbed")
        page:scrollBy(200)
        local track_h = H - page.view_top - require("mh/theme").px(48)
        local thumb_h = C.barThumb(track_h, vp)
        local ty = page.view_top + math.floor((track_h - thumb_h) * vp.scroll / max) + math.floor(thumb_h / 2)
        -- near the right edge but far from the thumb: an ordinary scroll
        assert(not page:barReach({ x = W - 20, y = H - 200 }), "edge, not thumb: not grabbed")
        assert(not page:barReach({ x = W - 120, y = ty }), "too far from the edge: not grabbed")
        -- on the thumb: drag it to the middle
        page:onMHPan(nil, { start_pos = { x = W - 20, y = ty }, pos = { x = W - 20, y = H / 2 }, relative = { x = 0, y = H / 2 - ty } })
        assert(page._bar_drag, "thumb grabbed")
        page:onMHPanRelease(nil, { pos = { x = W - 20, y = H / 2 } })
        local mid = vp.scroll
        assert(mid > max * 0.25 and mid < max * 0.75, "middle of the page: " .. mid .. " of " .. max)
        -- a swipe near the edge that does not start on the thumb scrolls normally
        local before = vp.scroll
        page:onMHSwipe(nil, { direction = "north", distance = 300, pos = { x = W - 20, y = H - 300 } })
        assert(vp.scroll ~= before and vp.scroll ~= max, "normal scroll, no jump")
    end)
end)

check("battery shows a bolt while charging", function()
    local Device = require("device")
    local p = Device:getPowerDevice()
    local orig = p.isCharging
    p.isCharging = function() return true end
    local C = require("mh/ui/components")
    local bar = C.statusBar(1088, require("mh/theme").boldColors(false), 36, true, true)
    paint(bar)
    local found = false
    local function walk(w)
        if type(w) ~= "table" then return end
        if getmetatable(w) and w.fg ~= nil and w.w and w.h and w.paintTo == C.Bolt.paintTo then found = true end
        for _, c in ipairs(w) do walk(c) end
    end
    walk(bar)
    p.isCharging = orig
    assert(found, "bolt drawn")
end)

check("updates: check GitHub, dot on Home, card in Settings, failed update keeps the old one", function()
    local U = require("mh/updater")
    assert(U.newer("0.1.37", "0.1.36") and U.newer("0.2.0", "0.1.99") and not U.newer("0.1.36", "0.1.36")
        and not U.newer("0.1.9", "0.1.10"), "version compare")
    assert(U.manifestUrl("dev"):find("/download/dev/latest.json", 1, true), "dev manifest url")
    assert(U.manifestUrl("stable"):find("/latest/download/latest.json", 1, true), "stable manifest url")
    local Prefs = require("mh/data/prefs")
    local nm = fakeNetwork()
    local hops = {}
    package.loaded["socket"] = { skip = function(n, ...) return select(n + 1, ...) end }
    package.loaded["socket.url"] = { absolute = function(_, loc) return loc end }
    package.loaded["socketutil"] = { set_timeout = function() end, reset_timeout = function() end, USER_AGENT = "t" }
    package.loaded["ltn12"] = { sink = { table = function(t) return function(c) if c then t[#t + 1] = c end return 1 end end } }
    package.loaded["ssl.https"] = { request = function(req)
        hops[#hops + 1] = req.url
        if #hops == 1 then return 1, 302, { location = "https://objects.example/latest.json" }, "302" end
        req.sink("{json}")
        return 1, 200, {}, "200"
    end }
    package.loaded["rapidjson"] = { decode = function(text)
        assert(text == "{json}", "redirect body must not reach the manifest")
        return { version = "9.9.9", file = "minimalhome-9.9.9.zip", sha256 = string.rep("a", 64), size = 2621440 }
    end }
    Prefs.set("update_checked_at", nil)
    Prefs.set("update_found", nil)
    local found
    U.check(3600, function(m) found = m end)
    assert(#hops == 2 and found and found.version == "9.9.9", "found the new build through a redirect")
    assert(U.available(), "remembered")
    -- once an hour: a second look right away does not touch the network
    U.check(3600, function() end)
    assert(#hops == 2, "throttled")
    -- Wi-Fi off: no check at all
    nm.on = false
    Prefs.set("update_checked_at", nil)
    U.check(0)
    assert(#hops == 2, "no check without Wi-Fi")
    nm.on = true; nm.cur = "Home 5G"

    local Home = require("mh/ui/home")
    paint(Home:new{ ui = {} })

    withUI(function()
        local Settings = require("mh/ui/settings")
        local page = Settings:new{ ui = fake_ui }:show()
        paint(page)
        -- Update starts a background download; the page follows it and stays usable
        local start = U.start
        U.start = function(m)
            U.job = { m = m, pct = 0 }
            return true
        end
        page:runUpdate(U.available())
        U.start = start
        assert(U.job, "download started")
        U.job.pct = 40
        for _, fn in pairs(U.listeners) do fn() end
        paint(page)
        page:scrollBy(300)
        -- Check update in Device: Checking…, then "Up to date" when GitHub has nothing newer
        U.job = nil
        local orig_soon = U.checkSoon
        local cb
        U.checkSoon = function(every, done) assert(every == 0, "a manual check ignores the hourly limit"); cb = done; return true end
        page:checkNow()
        assert(page.check_state == "checking", "button shows Checking…")
        paint(page)
        cb(nil, true, false)
        assert(page.check_state == "done", "up to date")
        paint(page)
        U.checkSoon = orig_soon
        page:close()
        assert(not U.listeners[page] or page.closed, "closed pages stop listening")
        U.job = nil
        assert(U.available(), "the update is still offered")
    end)
    Prefs.set("update_found", nil)
    Prefs.set("update_checked_at", nil)
end)

check("finished screen", function()
    local Finished = require("mh/ui/finished")
    local ui = {
        doc_props = { display_title = "Dế Mèn phiêu lưu ký", authors = "Tô Hoài" },
        document = { file = "/b/demen.epub", getPageCount = function() return 148 end },
        annotation = { annotations = { { drawer = "lighten" }, { drawer = "underscore" } } },
        doc_settings = { readSetting = function() return {} end },
    }
    local f = Finished:new{ ui = ui }
    assert(f.stats.pages == 148 and f.stats.highlights == 2, "stats gathered")
    paint(f)
end)

if OUT then
    local f = io.open(OUT, "w")
    f:write(require("json_min").encode(results))
    f:close()
end
print(passed .. " screens OK, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
