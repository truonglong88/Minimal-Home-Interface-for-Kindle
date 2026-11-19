-- Pretend every book flagged has_cover has one; the cover is identified by path.
local B = {}
function B:getBookInfo(path, get_cover)
    if get_cover then return { cover_bb = { name = path } } end
    return nil
end
function B:extractInBackground() return false end
function B:isExtractingInBackground() return false end
return B
