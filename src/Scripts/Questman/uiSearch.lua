-- questman: quest-list filtering.
-- v1 = case-insensitive SUBSTRING match over the quest name (and, optionally, entry text).
-- Pure module with a stable signature so a fuzzy/weighted matcher can later replace it
-- WITHOUT touching the UI: just implement filter(quests, query, opts) -> filtered list.

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

local function contains(haystack, needleLower)
    if not haystack then return false end
    return lower(haystack):find(needleLower, 1, true) ~= nil
end

--- Filter quests whose name (or any seen entry text) contains `query` (case-insensitive).
-- @param quests list of { name, entries = { { text=... }, ... }, ... }
-- @param query  #string  (empty/nil returns the list unchanged)
-- @param opts   { searchEntries = boolean } default true
-- @return filtered list (original order preserved)
function M.filter(quests, query, opts)
    if not query or query == '' then return quests end
    local q = lower(query)
    local searchEntries = not (opts and opts.searchEntries == false)
    local out = {}
    for _, quest in ipairs(quests) do
        local match = contains(quest.name, q)
        if not match and searchEntries and quest.entries then
            for _, e in ipairs(quest.entries) do
                if contains(e.text or e, q) then match = true break end
            end
        end
        if match then out[#out + 1] = quest end
    end
    return out
end

return M
