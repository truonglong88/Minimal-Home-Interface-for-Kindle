return { attributes = function(p, what) if p:match("%.ttf$") then return "file" end return nil end,
    dir = function() return function() return nil end end,
    currentdir = function() return "/mnt/us/koreader" end, mkdir = function() end }
