--[[--
A folder opened from All books › Folders (design: "All books – a folder opened").

‹ Library, the folder's name, "12 volumes · 2 finished · reading vol. 3", then
the folders inside it and its books: being read first (last opened on top),
then not read yet (A → Z, numbers in order), then finished. Rows look and work
like All books (tap to open, hold to delete).
--]]

local UIManager = require("ui/uimanager")

local C = require("mh/ui/components")
local Model = require("mh/data/model")
local Page = require("mh/ui/page")
local Theme = require("mh/theme")
local px = Theme.px

local FolderPage = Page:extend{
    back_label = "Library",
    back_to_top = true,
    swipe_home = true,
    folder = nil, -- { name, path, books }
    home = nil,   -- the Home screen (opens books, reloads the library)
}

function FolderPage:init()
    self:prepare()
    Page.init(self)
end

--- Title, summary line and the rows, from self.folder.
function FolderPage:prepare()
    local f = self.folder
    self.title = f.name
    local folders, loose = Model.groupByFolder(f.books, f.path)
    self.subfolders = folders
    self.books = Model.folderOrder(loose)
    local finished, reading = 0, nil
    for _, b in ipairs(Model.folderOrder(f.books)) do
        if Model.isFinished(b) then finished = finished + 1 end
        if not reading and Model.isInProgress(b) then reading = b end
    end
    local parts = { (#f.books == 1) and "1 volume" or (#f.books .. " volumes") }
    if finished > 0 then parts[#parts + 1] = finished .. " finished" end
    if reading then parts[#parts + 1] = "reading " .. Model.volumeLabel(reading) end
    self.subtitle = table.concat(parts, " · ")
end

-- All books' rows, drawn the same way here.
local Home = require("mh/ui/home")
FolderPage.coverFor = Home.coverFor
FolderPage.bookRow = Home.bookRow
FolderPage.folderRow = Home.folderRow

function FolderPage:blocks()
    local list = { function() return self:headerBlock() end, function() return C.space(1, px(56)) end }
    local row_h = px(Home.ROW_H) + px(Home.LINE)
    local i = 0
    for _, sub in ipairs(self.subfolders) do
        i = i + 1
        local n = i
        table.insert(list, { h = row_h, build = function() return self:folderRow(sub, n) end })
    end
    for _, b in ipairs(self.books) do
        i = i + 1
        local n = i
        table.insert(list, { h = row_h, build = function() return self:bookRow(b, n) end })
    end
    table.insert(list, function() return C.hline(self:contentWidth(), px(Home.LINE), self.col.line) end)
    return list
end

function FolderPage:openFolder(f)
    FolderPage:new{ ui = self.ui, home = self.home, folder = f }:show()
end

--- Close this page (and any folder pages under it), then open the book from Home.
function FolderPage:openBook(path)
    local home = self.home
    -- the folders on the way here, outermost first: ‹ Back in the book returns to them
    local trail = {}
    for _, win in ipairs(UIManager._window_stack or {}) do
        local w = win.widget
        if w and w.folder and w.is_mh_page and not w.closed then trail[#trail + 1] = w.folder.path end
    end
    if #trail == 0 or trail[#trail] ~= self.folder.path then trail[#trail + 1] = self.folder.path end
    for _, win in ipairs(UIManager._window_stack or {}) do
        local w = win.widget
        if w and w ~= self and w.folder and w.is_mh_page and not w.closed then
            w.on_close = nil
            w:close()
        end
    end
    self.on_close = nil
    self:close()
    if home and not home.closed then home:openBook(path, trail) end
end

function FolderPage:confirmDelete(b)
    require("mh/ui/confirm").show{
        title = "Delete this book?",
        text = "“" .. (b.title or "") .. "” will be removed from this Kindle, with its reading progress and highlights. "
            .. "This can’t be undone.",
        ok_text = "Delete",
        ok_callback = function()
            UIManager:nextTick(function()
                if not require("mh/device").deleteBook(self.ui, b.path) then
                    require("mh/ui/snackbar").show("Couldn’t delete this book")
                    return
                end
                for k = #self.folder.books, 1, -1 do
                    if self.folder.books[k].path == b.path then table.remove(self.folder.books, k) end
                end
                if self.home and not self.home.closed then
                    self.home._keep_scroll = self.home.viewport and self.home.viewport.scroll or 0
                    self.home:reload()
                end
                self:prepare()
                self:refresh()
                require("mh/ui/snackbar").show("Book deleted")
            end)
        end,
    }
end

return FolderPage
