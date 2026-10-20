-- questman: layout of the Journal tab's feed -- which rows to draw, in what order. Engine-free so it can be
-- unit-tested; ui.lua turns each row into a widget (and measures it), questProvider supplies the entries.

local M = {}

-- 'all' = the whole journal; 'records' = only the entries that belong to no quest in the Quests tab (the
-- "Notes" mode in the UI).
M.MODE_ALL, M.MODE_RECORDS = 'all', 'records'

-- An entry's in-game day. `day` (days passed) is the reliable key; month/dayOfMonth is the fallback for an
-- entry that carries only those. nil = undated.
local function dayKey(e)
    if e.day then return e.day end
    if e.month and e.dayOfMonth then return e.month .. '/' .. e.dayOfMonth end
    return nil
end

--- Build the feed rows, newest first.
-- @param entries oldest -> newest (journal order): { text, day, month, dayOfMonth, questId, record }
--                record = true for an entry outside every quest (questId is then unused)
-- @param mode    M.MODE_ALL | M.MODE_RECORDS
-- @param limit   optional: show only this many newest entries (the tab loads older ones as you scroll)
-- @return { rows = { { kind = 'day'|'label'|'text', entry }, ... },
--           count = the mode's total entries, more = older entries are left out by `limit` }
-- A 'day' row opens each in-game day. A 'label' row names the quest above a RUN of its entries: it repeats
-- only when the quest changes or a new day starts, like the Topics page prints a speaker once per run. All
-- non-quest entries share one label. The records mode has no labels -- every entry there is a record.
function M.rows(entries, mode, limit)
    local recordsOnly = (mode == M.MODE_RECORDS)
    local rows, count = {}, 0
    local prevDay, prevGroup = nil, nil
    for i = #entries, 1, -1 do
        local e = entries[i]
        local inMode = (not recordsOnly) or e.record
        if inMode then count = count + 1 end
        -- Past the limit keep counting (the total feeds the counter) but build no rows.
        if inMode and not (limit and count > limit) then
            local d = dayKey(e)
            local newDay = (d ~= nil and d ~= prevDay)
            if newDay then
                rows[#rows + 1] = { kind = 'day', entry = e }
                prevDay = d
            end
            local group = e.record and '' or e.questId
            if not recordsOnly and (newDay or group ~= prevGroup) then
                rows[#rows + 1] = { kind = 'label', entry = e }
            end
            prevGroup = group
            rows[#rows + 1] = { kind = 'text', entry = e }
        end
    end
    return { rows = rows, count = count, more = (limit ~= nil and count > limit) }
end

return M
