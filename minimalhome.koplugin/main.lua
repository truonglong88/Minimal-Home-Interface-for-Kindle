--[[--
Minimal Home: a calm library home screen for KOReader.

When KOReader shows its file browser, this plugin covers it with the home
screen. Opening a book closes the home screen; when the book is closed,
KOReader returns to the file browser and the home screen appears again.

@module koplugin.MinimalHome
--]]

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local BD = require("ui/bidi")
local _ = require("gettext")
local T = require("ffi/util").template

local Prefs = require("mh/data/prefs")

local MinimalHome = WidgetContainer:extend{
    name = "minimalhome",
    is_doc_only = false,
}

-- Plugins are created before the file browser finishes building its layout,
-- so `file_chooser` may not exist yet during init(). A reader always has a document.
local function isFileManager(ui)
    return ui ~= nil and ui.document == nil
end

function MinimalHome:init()
    -- Home at startup and the minimal reading screen are always on (no switch)
    if not Prefs.get("enabled") then Prefs.set("enabled", true) end
    if not Prefs.get("reader_style") then Prefs.set("reader_style", true) end
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    -- front light follows the light sensor, if the user turned that on
    if Prefs.get("auto_brightness") then
        pcall(function() require("mh/device").startAutoBrightness() end)
    end
    pcall(function() require("mh/device").keepLightOff() end)
    -- loading bar along the top edge while a book opens
    pcall(function() require("mh/loadingbar").install() end)
    -- KOReader's own short messages look like our snackbar
    pcall(function() require("mh/messages").install() end)
    if isFileManager(self.ui) then
        -- the screen turns upside down with the device, never sideways
        pcall(function() require("mh/device").keepPortraitRotation(self.ui) end)
        -- "Book cover" screensaver: books without a cover show the two cats
        pcall(function()
            local D = require("mh/device")
            if D.currentScreensaver() == "book" then D.ensureCoverFallback() end
        end)
        -- just updated over Wi-Fi: "Updated to 0.1.37"
        pcall(function() require("mh/updater").announce() end)
        if Prefs.get("reader_style") then
            -- written before any book opens, so the reader picks it up
            pcall(function() require("mh/reader").applyStyle() end)
        end
        if Prefs.get("enabled") then
            UIManager:nextTick(function() self:showHome() end)
        end
    else
        require("mh/reader").attach(self.ui)
    end
end

function MinimalHome:showHome()
    if self.home or not isFileManager(self.ui) or not self.ui.file_chooser then return end
    local ok, err = pcall(function()
        local Home = require("mh/ui/home")
        self.home = Home:new{
            ui = self.ui,
            on_close = function() self.home = nil end,
        }
        UIManager:show(self.home, "flashui")
    end)
    if not ok then
        -- Never leave the user stuck: fall back to KOReader's file browser.
        logger.err("MinimalHome: could not show home screen:", err)
        self.home = nil
    end
end

--- The file browser is being shown (KOReader start, or back from a book): put
--- Home on top straight away, so the browser is never painted first.
function MinimalHome:onShow()
    if isFileManager(self.ui) and Prefs.get("enabled") and not self.home then self:showHome() end
end

function MinimalHome:closeHome()
    if self.home then
        self.home:onClose()
        self.home = nil
    end
end

-- A book has finished opening.
-- KOReader re-registers its menu zones on rotation; keep ours in front.
function MinimalHome:onSetDimensions()
    if not isFileManager(self.ui) then require("mh/reader").reassertZones(self.ui) end
end

function MinimalHome:onReaderReady()
    require("mh/loadingbar").done()
    if not isFileManager(self.ui) then
        require("mh/reader").styleBook(self.ui)
        require("mh/reader").reassertZones(self.ui)
    end
end

-- The file browser or the book is going away.
function MinimalHome:onCloseWidget()
    self:closeHome()
    if not isFileManager(self.ui) then require("mh/reader").stopClock() end
end

-- Waking up: the reading screen's clock must show the new time at once.
-- (The home screen listens for these itself.)
function MinimalHome:onResume()
    pcall(function() require("mh/device").lightAfterSleep() end)
    if not isFileManager(self.ui) then require("mh/reader").onResume() end
    if Prefs.get("auto_brightness") then
        -- restarts the once-a-minute check (stopped while asleep)
        pcall(function() require("mh/device").startAutoBrightness() end)
    end
    -- light switched off in the quick panel: the Kindle relights it on wake
    pcall(function() require("mh/device").keepLightOff() end)
    pcall(function() require("mh/wifi").wake() end)
end

function MinimalHome:onSuspend()
    if not isFileManager(self.ui) then require("mh/reader").onSuspend() end
    pcall(function() require("mh/device").stopAutoBrightness() end)
    -- no lit screensaver all night
    pcall(function() require("mh/device").lightOffForSleep() end)
    -- Wi-Fi off while asleep; back on when waking if it was on
    pcall(function() require("mh/wifi").sleep() end)
end

function MinimalHome:addToMainMenu(menu_items)
    menu_items.minimal_home = {
        text = _("Minimal Home"),
        -- the hint must name a menu that exists here: KOReader v2026.07.1 crashes
        -- on a missing one ("filemanager_settings" is only in the file browser)
        sorting_hint = isFileManager(self.ui) and "filemanager_settings" or "setting",
        sub_item_table = {
            {
                text = _("Show home screen"),
                enabled_func = function() return isFileManager(self.ui) end,
                callback = function(touchmenu_instance)
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                    self:showHome()
                end,
            },
            {
                text_func = function()
                    local folder = Prefs.booksFolder() or "?"
                    return T(_("Books folder: %1"), BD.dirpath(folder))
                end,
                help_text = _("The home screen lists the books in this folder and its subfolders."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local filemanagerutil = require("apps/filemanager/filemanagerutil")
                    local default = filemanagerutil.getHomeFolder()
                    filemanagerutil.showChooseDialog(_("Books folder:"), function(path)
                        Prefs.set("books_folder", path ~= default and path or nil)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        if self.home then
                            self.home:reload()
                            UIManager:setDirty(self.home, "full")
                        end
                    end, Prefs.booksFolder(), default)
                end,
            },
        },
    }
end

return MinimalHome
