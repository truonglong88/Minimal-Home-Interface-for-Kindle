local function noop() end
return { dbg = noop, info = noop, warn = function(...) print("WARN", ...) end, err = function(...) print("ERR", ...) end }
