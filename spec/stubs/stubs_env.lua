local settings = {}
G_reader_settings = {
    readSetting = function(_, k, default) if settings[k] == nil then return default end return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    isTrue = function(_, k) return settings[k] == true end,
    nilOrTrue = function(_, k) return settings[k] == nil or settings[k] == true end,
    flush = function() end,
    has = function(_, k) return settings[k] ~= nil end,
    hasNot = function(_, k) return settings[k] == nil end,
    makeTrue = function(_, k) settings[k] = true end,
    makeFalse = function(_, k) settings[k] = false end,
    flipNilOrFalse = function(_, k) settings[k] = not settings[k] end,
    delSetting = function(_, k) settings[k] = nil end,
}
G_defaults = { readSetting = function() return nil end }
