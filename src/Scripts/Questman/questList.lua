-- questman: quest-list operations — single-facet filtering plus the display orders (recency, A-Z, and the
-- faction / category groups).
-- The player picks ONE filter value (e.g. "Tribunal", "Mages Guild", "Daedric") from the same facets
-- the Stats page groups by: add-on, coarse category, faction. A selection is { axis, key }.
-- Pure module -> unit-testable: the data layer (questProvider.getFilterOptions) builds labeled+ordered
-- options from counts(); the UI applies the active selection in its row-building via apply()/matches().

local uiSearch = require('scripts.questman.uiSearch')

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

-- A-Z order: PINNED first and COMPLETED last, as in sortByRecency, so only the order inside each tier changes.
-- Ignores case (Cyrillic too): quest names are typed by hand and their capitalisation is inconsistent.
-- Input is not mutated.
function M.sortByName(quests)
    local out = {}
    for i, q in ipairs(quests) do out[i] = q end
    table.sort(out, function(a, b)
        local pa, pb = a.pinned == true, b.pinned == true
        if pa ~= pb then return pa end
        if (a.completed == true) ~= (b.completed == true) then return not a.completed end
        local na, nb = a.name or '', b.name or ''
        if na ~= nb then return uiSearch.lessIgnoreCase(na, nb) end
        return (a.id or '') < (b.id or '')               -- same name: still a deterministic order
    end)
    return out
end

-- Group keys that are not faction ids: the pinned quests (always on top) and the quests without a faction.
M.GROUP_PINNED = '@pinned'
M.GROUP_NONE = '@none'

-- Category display order (the Stats page and the filter use it too): Main Quest first; Miscellaneous then
-- Unknown last; everything else alphabetical.
local CAT_ORDER = { main_quest = 1, misc = 98, unknown = 99 }
function M.categoryRank(key) return CAT_ORDER[key] or 50 end

-- Split a sorted quest list into groups: the pinned quests first, then the groups by rank, equal ranks A-Z by
-- label. `groupOf(quest)` -> key, label, rank. Every group keeps the input order, so the chosen sort still
-- applies inside it.
-- @return { { key, label, quests } } -- no empty groups; the pinned group has no label
function M.groupBy(quests, groupOf)
    local pinned, byKey, groups = {}, {}, {}
    for _, q in ipairs(quests) do
        if q.pinned then
            pinned[#pinned + 1] = q
        else
            local key, label, rank = groupOf(q)
            local g = byKey[key]
            if not g then
                g = { key = key, label = label, rank = rank, quests = {}, seen = #groups }
                byKey[key] = g
                groups[#groups + 1] = g
            end
            g.quests[#g.quests + 1] = q
        end
    end
    table.sort(groups, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        local la, lb = a.label or '', b.label or ''
        if la ~= lb then return uiSearch.lessIgnoreCase(la, lb) end
        return a.seen < b.seen                           -- same label: first seen first (table.sort isn't stable)
    end)
    local out = {}
    if #pinned > 0 then out[#out + 1] = { key = M.GROUP_PINNED, quests = pinned } end
    for _, g in ipairs(groups) do out[#out + 1] = g end
    return out
end

-- Groups: pinned, each faction A-Z by its display label, then the quests without a faction (GROUP_NONE, no label).
function M.groupByFaction(quests)
    return M.groupBy(quests, function(q)
        if q.factionId then return q.factionId, q.faction or q.factionId, 1 end
        return M.GROUP_NONE, nil, 2
    end)
end

-- Groups: each category in its display order (Main Quest first, Misc then Unknown last, the rest A-Z).
-- `categoryLabel(key)` -> the category's display name.
function M.groupByCategory(quests, categoryLabel)
    return M.groupBy(quests, function(q)
        local cat = q.category or 'unknown'
        return cat, categoryLabel(cat), M.categoryRank(cat)
    end)
end

-- Groups: the faction where a quest has one, else its category. Main Quest first, then the factions A-Z, then
-- the other categories in their display order -- so nothing lands in a catch-all "no faction" pile.
-- `categoryLabel(key)` -> the category's display name. Keys are prefixed: a faction id may equal a category key.
local FACTION_RANK = 10   -- after Main Quest (1), before the alphabetical categories (50)
function M.groupByFactionOrCategory(quests, categoryLabel)
    return M.groupBy(quests, function(q)
        if q.factionId then return 'faction:' .. q.factionId, q.faction or q.factionId, FACTION_RANK end
        local cat = q.category or 'unknown'
        return 'category:' .. cat, categoryLabel(cat), M.categoryRank(cat)
    end)
end

-- Pinned items first, each group keeping its input order (a stable partition). For the Topics list: its
-- order is the name sort (vanilla or ignore-case) and must survive, while a bookmarked topic floats up.
-- Input is not mutated.
function M.pinnedFirst(items)
    local pinned, rest = {}, {}
    for _, item in ipairs(items) do
        if item.pinned then pinned[#pinned + 1] = item else rest[#rest + 1] = item end
    end
    for _, item in ipairs(rest) do pinned[#pinned + 1] = item end
    return pinned
end

-- The three filterable facets. Order here = the order option groups appear in the dropdown.
local AXES = { 'addon', 'category', 'faction' }

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
