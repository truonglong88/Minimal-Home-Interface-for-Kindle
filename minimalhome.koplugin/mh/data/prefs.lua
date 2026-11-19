--[[--
Plugin settings, stored inside KOReader's own settings file under the
"minimalhome" key, so they survive plugin updates.
--]]

local KEY = "minimalhome"

local DEFAULTS = {
    enabled = true,        -- show the home screen instead of the file browser
    sort_key = "recent",   -- recent | added | title | author
    sort_asc = true,       -- default direction (newest first / A to Z)
    books_folder = nil,    -- nil = KOReader's home folder
    reader_style = true,   -- style the reading screen (top bar, status bar, typography)
    finished_screen = true, -- show our "Finished" screen at the end of a book
    auto_brightness = false, -- set the front light from the light sensor
}

local Prefs = {}

local function load()
    local t = G_reader_settings:readSetting(KEY) or {}
    for k, v in pairs(DEFAULTS) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

function Prefs.get(name)
    return load()[name]
end

function Prefs.set(name, value)
    local t = load()
    t[name] = value
    G_reader_settings:saveSetting(KEY, t)
end

function Prefs.booksFolder()
    local folder = Prefs.get("books_folder")
    if folder then return folder end
    return require("apps/filemanager/filemanagerutil").getHomeFolder()
end

return Prefs
