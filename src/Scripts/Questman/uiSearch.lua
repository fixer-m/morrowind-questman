-- questman: list searching (quests, topics).
-- index(items, textOf) + search(index, query): name hits first, then body-text hits ranked by
-- occurrences / sqrt(words); a query counts only from MIN_QUERY characters, and text is built lazily.
-- Pure module (no engine deps) so it stays unit-tested in tests/pure_spec.lua.

local M = {}

-- UTF-8-aware lowercase for ASCII + Cyrillic.
-- WHY this exists: OpenMW's Lua `string.lower` is the stock LuaJIT/5.1 one (sol::lib::string) and
-- folds ASCII byte-by-byte only, so multibyte Cyrillic never folds -> Russian search was
-- case-sensitive. OpenMW HAS the correct logic in C++ (Utf8Stream::toLowerUtf8 in
-- components/misc/utf8stream.hpp — identical codepoint ranges to below) but does not expose it, or
-- any unicode lower / case-insensitive compare, to Lua; the bundled `utf8` library has no case
-- folding. So we replicate the engine's exact ranges here. (Swap for an API call if one ever lands.)
local function lower(s)
    if type(s) ~= 'string' then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then
            if b >= 0x41 and b <= 0x5A then b = b + 0x20 end   -- A-Z -> a-z
            out[#out + 1] = string.char(b)
            i = i + 1
        elseif b == 0xD0 then
            local b2 = s:byte(i + 1) or 0
            if b2 >= 0x90 and b2 <= 0x9F then
                out[#out + 1] = string.char(0xD0, b2 + 0x20)   -- А-П -> а-п
            elseif b2 >= 0xA0 and b2 <= 0xAF then
                out[#out + 1] = string.char(0xD1, b2 - 0x20)   -- Р-Я -> р-я
            elseif b2 == 0x81 then
                out[#out + 1] = string.char(0xD1, 0x91)        -- Ё -> ё
            else
                out[#out + 1] = string.char(0xD0, b2)
            end
            i = i + 2
        else
            local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        end
    end
    return table.concat(out)
end
M.lower = lower

--- `table.sort` comparator: alphabetical ignoring case (ASCII + Cyrillic, via lower). Names that differ only
-- in case fall back to the plain byte order, so the sort stays deterministic.
function M.lessIgnoreCase(a, b)
    local la, lb = lower(a), lower(b)
    if la ~= lb then return la < lb end
    return a < b
end

-- Shortest query that searches at all, names and text alike. Text needs it: a 1-2 letter needle matches
-- nearly every journal entry (noise) and scans the whole journal on every keystroke (cost). Names share it
-- so the results only ever narrow as the player types: with a lower name floor, the 3rd letter would ADD
-- the text hits. Counted in characters.
M.MIN_QUERY = 3

local function charCount(s)
    -- UTF-8 continuation bytes are 10xxxxxx; every other byte starts a character.
    local _, continuation = s:gsub('[\128-\191]', '')
    return #s - continuation
end

--- Is `query` long enough to search? Shorter ones show the whole list, as if the box were empty.
function M.isActive(query)
    return type(query) == 'string' and charCount(query) >= M.MIN_QUERY
end

local function countOccurrences(haystack, needle)
    local count, from = 0, 1
    while true do
        local at = haystack:find(needle, from, true)
        if not at then return count end
        count = count + 1
        from = at + #needle
    end
end

-- Lowered name/text per item, kept per `textOf` function. WHY: the UI rebuilds its list (and so the
-- index) on every refresh -- a click, a pin -- but the item tables live for the whole window open, so
-- caching on them means the journal is lowered once per open, not once per refresh. Weak keys let the
-- cache go when the UI drops its item tables (the next open builds fresh ones).
local cacheByTextOf = setmetatable({}, { __mode = 'k' })

local function cachedRow(textOf, item)
    local cache = cacheByTextOf[textOf]
    if not cache then
        cache = setmetatable({}, { __mode = 'k' })
        cacheByTextOf[textOf] = cache
    end
    local row = cache[item]
    if not row then
        row = { item = item, name = lower(item.name or ''), text = nil, words = nil }
        cache[item] = row
    end
    return row
end

--- Prepare items for searching. Names are lowered up front (cheap); body text is built and lowered
-- lazily on the first query long enough to need it -- so a session that never searches text (or a huge
-- topic list) never pays for it. Both are cached on the item tables (see cacheByTextOf).
-- @param items  list of { name = string, ... }
-- @param textOf function(item) -> string, the item's searchable body text
function M.index(items, textOf)
    local rows = {}
    for i, item in ipairs(items) do rows[i] = cachedRow(textOf, item) end
    return { rows = rows, textOf = textOf }
end

--- Split the indexed items into name hits and text hits.
-- byName: the name contains the query, in input order (the caller's display order is kept).
-- byText: only the body contains it, best score first; ties keep input order.
--   score = occurrences / sqrt(words): twice the mentions = twice the score, a 4x longer text = half the
--   score. So a short quest that keeps naming the word beats a long one that mentions it in passing,
--   while a long quest that is really about it still beats a tiny one-off mention.
-- @return { byName = list, byText = list }
function M.search(index, query)
    if not M.isActive(query) then
        local all = {}
        for i, row in ipairs(index.rows) do all[i] = row.item end
        return { byName = all, byText = {} }
    end
    local needle = lower(query)
    local byName, textRows = {}, {}
    for position, row in ipairs(index.rows) do
        if row.name:find(needle, 1, true) then
            byName[#byName + 1] = row.item
        else
            if not row.text then
                row.text = lower(index.textOf(row.item) or '')
                local _, words = row.text:gsub('%S+', '')
                row.words = math.max(1, words)   -- >= 1: a hit implies a word, but keep the division safe
            end
            local hits = countOccurrences(row.text, needle)
            if hits > 0 then
                local score = hits / math.sqrt(row.words)
                textRows[#textRows + 1] = { item = row.item, score = score, position = position }
            end
        end
    end
    -- table.sort is not stable, so the input position breaks ties explicitly.
    table.sort(textRows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.position < b.position
    end)
    local byText = {}
    for i, hit in ipairs(textRows) do byText[i] = hit.item end
    return { byName = byName, byText = byText }
end

--- Colour every case-insensitive match of `query` in `text` with MyGUI inline colour tags:
-- `#<onHex>match#<offHex>`, where offHex must be the widget's own text colour (a tag has no "end", it
-- only switches colour). Same MIN_QUERY floor as the search, so a 1-2 letter query does not paint every
-- other word. Returns `text` untouched when nothing matches.
-- Match positions found in lower(text) are valid in `text`: lower() keeps every character's byte length.
function M.highlight(text, query, onHex, offHex)
    if not text or not M.isActive(query) then return text end
    local needle, haystack = lower(query), lower(text)
    local parts, from = {}, 1
    while true do
        local at = haystack:find(needle, from, true)
        if not at then break end
        local to = at + #needle - 1
        parts[#parts + 1] = text:sub(from, at - 1):gsub('#', '##')   -- '##' = a literal '#' once tags are on
        parts[#parts + 1] = '#' .. onHex .. text:sub(at, to):gsub('#', '##') .. '#' .. offHex
        from = to + 1
    end
    if #parts == 0 then return text end
    parts[#parts + 1] = text:sub(from):gsub('#', '##')
    return table.concat(parts)
end

return M
