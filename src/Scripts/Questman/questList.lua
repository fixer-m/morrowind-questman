-- questman: quest-list operations — single-facet filtering plus the default display ordering.
-- The player picks ONE filter value (e.g. "Tribunal", "Mages Guild", "Daedric") from the same facets
-- the Stats page groups by: add-on, coarse category, faction. A selection is { axis, key }.
-- Pure module -> unit-testable: the data layer (questProvider.getFilterOptions) builds labeled+ordered
-- options from counts(); the UI applies the active selection in its row-building via apply()/matches().

local M = {}

-- Default display order: PINNED first, then ACTIVE, then COMPLETED (shown grayed), each by recency
-- (most recently updated on top), ties broken alphabetically. Input is not mutated.
function M.sortByRecency(quests)
    local out = {}
    for i, q in ipairs(quests) do out[i] = q end
    table.sort(out, function(a, b)
        local pa, pb = a.pinned == true, b.pinned == true
        if pa ~= pb then return pa end                   -- pinned float to the very top
        if a.completed ~= b.completed then
            return not a.completed                       -- active before completed
        end
        local ra, rb = a.recency or 0, b.recency or 0
        if ra ~= rb then return ra > rb end              -- most recent first
        return (a.name or '') < (b.name or '')           -- stable, alphabetical
    end)
    return out
end
M.sortDefault = M.sortByRecency

-- The three filterable facets. Order here = the order option groups appear in the dropdown.
local AXES = { 'addon', 'category', 'faction' }
M.AXES = AXES

-- A quest's key on a given axis. addon/category always classify (unrecognised -> the 'unknown' catch-all,
-- matching Stats: "Other" for add-ons, "Unknown" for categories); faction is nil when the quest has no
-- derivable giver/faction -> excluded from counts & matches.
local function keyOf(quest, axis)
    if axis == 'addon' then return quest.addon or 'unknown' end
    if axis == 'category' then return quest.category or 'unknown' end
    if axis == 'faction' then return quest.factionId end
    return nil
end
M.keyOf = keyOf

--- Does a quest match the selected filter? A nil selection (or one without an axis) matches everything.
function M.matches(quest, sel)
    if not sel or not sel.axis then return true end
    return keyOf(quest, sel.axis) == sel.key
end

--- Filter a quest list by the selection (original order preserved). nil sel -> the list unchanged.
function M.apply(quests, sel)
    if not sel or not sel.axis then return quests end
    local out = {}
    for _, q in ipairs(quests) do
        if M.matches(q, sel) then out[#out + 1] = q end
    end
    return out
end

--- Per-axis distinct-key counts over a quest list (nil keys excluded).
-- @return { addon = { key = count }, category = { key = count }, faction = { key = count } }
function M.counts(quests)
    local res = { addon = {}, category = {}, faction = {} }
    for _, q in ipairs(quests or {}) do
        for _, axis in ipairs(AXES) do
            local k = keyOf(q, axis)
            if k ~= nil then res[axis][k] = (res[axis][k] or 0) + 1 end
        end
    end
    return res
end

return M
