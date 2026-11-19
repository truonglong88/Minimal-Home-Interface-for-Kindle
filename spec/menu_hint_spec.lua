-- The plugin's menu entry must name a sorting_hint that exists in the menu it
-- is added to: KOReader v2026.07.1 crashes in MenuSorter on a missing one
-- (that was the crash when swiping down in the reader).
-- Usage: luajit spec/menu_hint_spec.lua /path/to/koreader
local ko = assert(arg[1], "koreader path")
package.loaded["device"] = setmetatable({}, { __index = function() return function() return true end end })

local function ids(order)
    local set = {}
    for k, v in pairs(order) do
        set[k] = true
        if type(v) == "table" then for _, id in ipairs(v) do set[id] = true end end
    end
    return set
end
local reader = ids(dofile(ko .. "/frontend/ui/elements/reader_menu_order.lua"))
local fm = ids(dofile(ko .. "/frontend/ui/elements/filemanager_menu_order.lua"))

local src = io.open("minimalhome.koplugin/main.lua"):read("*a")
local fm_hint, reader_hint = src:match('sorting_hint = isFileManager%(self.ui%) and "([%w_]+)" or "([%w_]+)"')
assert(fm_hint and reader_hint, "sorting_hint must depend on the context")
assert(fm[fm_hint], "file browser menu has no '" .. fm_hint .. "'")
assert(reader[reader_hint], "reader menu has no '" .. reader_hint .. "'")
print("menu hints OK (" .. fm_hint .. " / " .. reader_hint .. ")")
