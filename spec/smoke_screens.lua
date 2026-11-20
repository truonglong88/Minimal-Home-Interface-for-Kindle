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
