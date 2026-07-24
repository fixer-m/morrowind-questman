-- questman: quest data provider (PLAYER context) — reads engine state, derives the model, serves it.
-- Responsibilities:
--   * enumerate the player's quests, collapse them by name into the displayed GameQuest list
--   * classify each (add-on / category / faction) via scripts/questman/questMetadata
--   * gather the player's journal entries, in order
--   * persist last-viewed / pins / hidden across saves
-- Exposes the `QuestmanData` interface consumed by ui.lua.

local types = require('openmw.types')
local core = require('openmw.core')
local self = require('openmw.self')
local storage = require('openmw.storage')
local async = require('openmw.async')    -- background prebuild timer (schedulePrewarm)
local I = require('openmw.interfaces')   -- for the optional SSQN icon-pack interface (I.SSQN.getQIcon)

local icons = require('scripts.questman.icons')
local questMetadata = require('scripts.questman.questMetadata')
local givers = require('scripts.questman.givers')
local questList = require('scripts.questman.questList')
local uiSearch = require('scripts.questman.uiSearch')   -- Cyrillic-aware lower() for topic-link matching

-- Cross-save settings (registered in settings.lua). Read here for the quest-list icon set (IconPack).
local settings = storage.playerSection('Settings/Questman/Options')

-- Strip '@'/'#' hyperlink delimiters from journal/dialogue text (heavy in the RU release; left in, the
-- text widget renders them as garbled overlapping colored link spans). Keeps the inner words; nil passes
-- through. (Turning these into real clickable topics is a deferred feature.)
local function sanitizeText(s)
    if type(s) ~= 'string' then return s end
    return (s:gsub('[@#]', ''))
end

local l10n = core.l10n('Questman')
local settings = storage.playerSection('Settings/Questman/Options')

-- ---------------------------------------------------------------------------
-- Quest classification (scripts/questman/questMetadata.lua): questMetadata.get(id) -> { addon, category,
-- faction, factionId } from prefix masks. Unknown ids (mods we don't
-- recognise) return nil and fall back to sane defaults below.
-- ---------------------------------------------------------------------------

-- classification category (full English string) -> l10n slug key; the UI renders it via l10n('cat_'..key).
-- Add-on categories (Bounty / Narsis Arena / Abecette Fight Pit) fall back to the misc icon until they
-- get dedicated art (icons.forCategory handles that automatically).
local CAT_KEY = {
    ['Main Quest'] = 'main_quest',              ['Great House Quests'] = 'great_house',
    ['Guild Faction Quests'] = 'guild_faction', ['Vampire Quests'] = 'vampire',
    ['Daedric Quests'] = 'daedric',             ['Miscellaneous Quests'] = 'misc',
    ['Bounty'] = 'bounty',                      ['Narsis Arena'] = 'narsis_arena',
    ['Abecette Fight Pit'] = 'abecette_fight_pit',
}

-- Classification for a journal id, or nil (unknown mod id). See questMetadata.
local function metaFor(id) return id and questMetadata.get(id) or nil end

-- Category slug for a quest id: from the classifier where mapped, else 'unknown'.
local function categoryKeyFor(id)
    local m = metaFor(id)
    return (m and CAT_KEY[m.category]) or 'unknown'
end

-- Add-on slug for a quest id: the classifier emits it directly, else 'unknown'.
local function addonKeyFor(id)
    local m = metaFor(id)
    return (m and m.addon) or 'unknown'
end

-- Choose a name-group's MAIN id and return the member ids ordered with it first. OpenMW keys a journal log
-- by name, not id, so several ids share one log; `mainId` is the id that supplies the group's metadata
-- (category / faction / icon / add-on) and heads the tech-info list. It's the lexicographically-first
-- member of the id list passed in (sorted for stability across saves). buildQuests passes the FINISHABLE
-- members, so the main id is a finishable one even after non-finished sub-ids join the group. `preferId`
-- (optional) forces a specific member first, re-ordering the full member list around the chosen main.
local function groupMainId(memberIds, preferId)
    local ordered = {}
    for _, m in ipairs(memberIds) do ordered[#ordered + 1] = m end
    table.sort(ordered, function(a, b) return a:lower() < b:lower() end)
    local idx = 1
    if preferId then
        for i, mid in ipairs(ordered) do if mid == preferId then idx = i; break end end
    end
    local main = ordered[idx]
    table.remove(ordered, idx)
    table.insert(ordered, 1, main)   -- main first (tech-info shows it on top)
    return main, ordered
end

-- Merge the journal entries of several ids into one chronological list (oldest->newest by global journal
-- index). `journalEntries` is keyed by lower id. Returns the merged list + the max lastIndex (recency).
local function unionEntries(journalEntries, ids)
    local merged, lastIndex = {}, 0
    for _, mid in ipairs(ids) do
        local b = journalEntries[mid:lower()]
        if b then
            for _, e in ipairs(b.entries) do merged[#merged + 1] = e end
            if b.lastIndex > lastIndex then lastIndex = b.lastIndex end
        end
    end
    table.sort(merged, function(x, y) return (x.index or 0) < (y.index or 0) end)
    return merged, lastIndex
end

-- SINGLE SOURCE OF TRUTH for add-ons. Keyed by the stable `slug` questMetadata emits (never renamed -- it's
-- the persisted quest-filter key); `title` is the ONLY user-facing add-on name and is defined here and
-- nowhere else. Order = release chronology (drives the Stats "By add-ons" rows and the filter list). Add a
-- new supported add-on by appending one row here (+ its icon in icons.lua, keyed by the same slug). Titles
-- are untranslated by design (expansion / mod proper names). The 'unknown' catch-all ("Other") is handled
-- separately below (rank 99, last).
local ADDONS = {
    { slug = 'morrowind',        title = 'Morrowind' },
    { slug = 'tribunal',         title = 'Tribunal' },
    { slug = 'bloodmoon',        title = 'Bloodmoon' },
    { slug = 'tamriel_rebuilt',  title = 'Tamriel Rebuilt' },
    { slug = 'project_cyrodiil', title = 'Project Cyrodiil' },
    { slug = 'province_skyrim',  title = 'Skyrim: Home of the Nords' },
}
local ADDON_LABELS, ADDON_ORDER = { unknown = 'Other' }, {}
for i, a in ipairs(ADDONS) do ADDON_LABELS[a.slug] = a.title; ADDON_ORDER[a.slug] = i end
-- any unlisted add-on sorts alphabetical (rank 50); the 'unknown' catch-all ("Other") always last.
local function addonRank(key) return ADDON_ORDER[key] or (key == 'unknown' and 99) or 50 end
local function addonRowLess(x, y)
    local rx, ry = addonRank(x.key), addonRank(y.key)
    if rx ~= ry then return rx < ry end
    return x.label < y.label
end

-- Category display order: Main Quest first; Miscellaneous then Unknown last; everything else alphabetical.
local CAT_ORDER = { main_quest = 1, misc = 98, unknown = 99 }
local function catRank(key) return CAT_ORDER[key] or 50 end
local function catRowLess(x, y)
    local rx, ry = catRank(x.key), catRank(y.key)
    if rx ~= ry then return rx < ry end
    return x.label < y.label
end

-- Detail-pane add-on suffix: surface the expansion / province add-on next to a quest (Morrowind and the
-- 'unknown' catch-all show nothing).
local function addonSuffix(akey)
    if not akey or akey == 'morrowind' or akey == 'unknown' then return nil end
    return ADDON_LABELS[akey]
end

-- Main-quest "finished" marker per add-on lives in questMetadata.finalQuests (add-on -> list of finale
-- ids; completing ANY marks that add-on's main quest done -> the Stats-page checkmark, case-insensitive).
local function dbg(...)
    if settings:get('Debug') ~= false then print('[questman]', ...) end
end

-- Persistent state (saved into the player's save game via onSave/onLoad).
local state = {
    lastViewed = nil,      -- questId (Quests page)
    lastViewedTopic = nil, -- topic id (Topics page)
    pinned = {},           -- set of questId -> true; pinned quests float to the top of the list
    hidden = {},           -- set of questId -> true; hidden quests are kept out of the list by default
}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function questRecord(id)
    return core.dialogue.journal.records[id]
end

-- Giver map: derived once from dialogue (the scan is ~50ms on a full load) and cached for the session.
local giverMapCache
local function giverMap()
    if not giverMapCache then
        -- PERF (temp): the dialogue scan is the plugin's heaviest one-time init (seconds on TR+PC+SHOTN), so
        -- time it as "Init". Fires once per session -- today lazily on the first window open; after the planned
        -- background prebuild it will run right after save-load, and this same line reports it.
        local t0 = core.getRealTime()
        giverMapCache = givers.resolve({ core.dialogue.topic, core.dialogue.greeting })
        dbg(('Init: %.0f ms'):format((core.getRealTime() - t0) * 1000))
    end
    return giverMapCache
end

-- Resolve an actor id to a display name (some givers are creatures, not NPCs — e.g. Dagoth Ur,
-- Almalexia's boss form — so check both stores before falling back to the raw id).
local function actorName(id)
    local rec = types.NPC.records[id] or types.Creature.records[id]
    if rec and rec.name and rec.name ~= '' then return rec.name end
    return id
end

-- Faction display names, read live from the game's faction data (already localized) and cached —
-- no bundled list needed. Falls back to the raw id if the record/name is missing.
local factionNameCache = {}
local function factionName(fid)
    if not fid or fid == '' then return nil end
    local cached = factionNameCache[fid]
    if cached == nil then
        local ok, name = pcall(function()
            local r = core.factions.records[fid]
            return r and r.name
        end)
        cached = (ok and name and name ~= '' and name) or false
        factionNameCache[fid] = cached
    end
    return cached or fid
end

-- Resolved quest giver (display only) -- name + id for the "quest giver" line. Faction is classified from the id
-- (see enrichWithMetadata), not the giver. Returns nil when no giver is derivable.
local function giverFor(questId)
    local gid = givers.giverId(giverMap(), questId)
    if not gid then return nil end
    return { id = gid, name = actorName(gid) }
end

-- A record is a "real" quest if it has a name and at least one finishing stage
-- (mirrors questmenu's blacklist of placeholder/fake journal records).
local function isRealQuest(rec)
    if not rec or not rec.questName or rec.questName == '' then return false end
    if not rec.infos then return false end
    for _, info in pairs(rec.infos) do
        if info.isQuestFinished then return true end
    end
    return false
end

-- Per quest NAME (lowercased): every catalog record id sharing it (sorted for stability) + the name's
-- `mainId` -- the lexicographically-first FINISHABLE record, or nil when the name never finishes.
-- OpenMW keys a journal log by name; some mods (SHOTN) split one quest across several same-named records
-- where the finishing record is started only at completion, so BOTH "can this quest finish?" and "what is
-- its stable identity?" must be answered from the catalog, not the player's started records. The main
-- id doesn't shift as the player progresses, so pin/hide/last-viewed keyed on it stay put. Immutable game
-- data (dialogue records don't change at runtime) -> cached for the session, like buildCatalog.
local nameGroupsCache
local function nameGroups()
    if nameGroupsCache then return nameGroupsCache end
    local groups = {}
    for _, rec in pairs(core.dialogue.journal.records) do
        local nm = rec.questName
        if nm and nm ~= '' and rec.id then
            local key = nm:lower()
            local g = groups[key]
            if not g then g = { ids = {} }; groups[key] = g end
            g.ids[#g.ids + 1] = rec.id
            if isRealQuest(rec) and (not g.mainId or rec.id:lower() < g.mainId:lower()) then
                g.mainId = rec.id   -- lex-first finishable record = the quest's stable main id
            end
        end
    end
    for _, g in pairs(groups) do
        table.sort(g.ids, function(a, b) return a:lower() < b:lower() end)
    end
    nameGroupsCache = groups
    return groups
end

-- Quest giver for a collapsed quest: the OPENER across ALL catalog records sharing the name -- the giver-map
-- entry with the lowest journal stage (who sets the quest's first entry) -- independent of the main id. Some
-- quests start on a different record than the one that finishes, so keying the giver to quest.id was wrong.
-- Falls back to the id-based lookup when the name-group yields nothing. (giverFor / giverMap / actorName are
-- defined above; nameGroups just above.)
local function giverForQuest(name, fallbackId)
    local grp = name and nameGroups()[name:lower()]
    local gid = grp and givers.giverForIds(giverMap(), grp.ids)
    if gid then return { id = gid, name = actorName(gid) } end
    return giverFor(fallbackId)
end

-- ---------------------------------------------------------------------------
-- per-open cache
-- ---------------------------------------------------------------------------
-- The journal is static while the menu is open (the player reads; they don't gain quests/topics/entries
-- mid-view), so the heavy scans below are computed ONCE per open and shared by every consumer (quest
-- list, stats, filter options, entries, links, diagnostics). ui.lua calls invalidate() at the START of each
-- open (and onLoad clears it too), so the NEXT open always re-reads -> a new journal entry / quest / topic
-- shows up. buildCatalog is intentionally NOT here: it's immutable game data, cached permanently.
-- The *Links maps memoize per-id results so reselecting a quest/topic is free (the keyword scan is the
-- heaviest click-path work); cachedTopicNames is their shared, static input.
local cachedQuests, cachedJournalEntries, cachedTopics, cachedRecords
local cachedTopicNames, cachedQuestLinks, cachedTopicLinks
local function invalidateCache()
    cachedQuests, cachedJournalEntries, cachedTopics, cachedRecords = nil, nil, nil, nil
    cachedTopicNames, cachedQuestLinks, cachedTopicLinks = nil, nil, nil
end

-- Group the player's journal entries by quest (keyed by LOWER id), preserving order.
-- journalTextEntries is globally ordered oldest -> newest, so the index of a quest's LAST entry is a
-- cheap recency score; each entry also carries its global `index` so a meta page can merge several
-- quests' entries back into chronological order. Cached per open (see above).
-- TODO: fallback for entries whose questId is nil (map stage -> rec.infos[].text).
local function collectJournalEntries()
    if cachedJournalEntries then return cachedJournalEntries end
    local byQuest = {}
    local journal = types.Player.journal(self)
    local list = (journal and journal.journalTextEntries) or {}
    for i, entry in ipairs(list) do
        local qid = entry.questId
        if qid then
            local key = qid:lower()
            local bucket = byQuest[key]
            if not bucket then
                bucket = { id = qid, entries = {}, lastIndex = 0 }   -- id: original-case journal id (Records classify/title from it)
                byQuest[key] = bucket
            end
            -- month/dayOfMonth power the Records tab's per-entry date labels; unused by the Quests pipeline.
            bucket.entries[#bucket.entries + 1] = {
                text = sanitizeText(entry.text), day = entry.day,
                month = entry.month, dayOfMonth = entry.dayOfMonth, index = i,
            }
            bucket.lastIndex = i
        end
    end
    cachedJournalEntries = byQuest
    return byQuest
end

-- ---------------------------------------------------------------------------
-- interface
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- quest model pipeline: raw engine quests -> collapse by name -> keep finishable -> enrich with metadata
-- ---------------------------------------------------------------------------

-- 1. Read the engine's per-id quests as "raw" quests: id + journal name + engine state + whether the
-- record can finish. Only named records seed the list (drops journal noise like book_history/greetings).
local function readRawQuests()
    local out = {}
    for _, q in pairs(types.Player.quests(self)) do
        local rec = q.id and questRecord(q.id)
        if rec and rec.questName and rec.questName ~= '' then
            out[#out + 1] = {
                id = q.id, name = rec.questName,
                stage = q.stage, started = q.started, finished = q.finished,
                finishable = isRealQuest(rec),
            }
        end
    end
    return out
end

-- 2. Collapse raw quests sharing a journal NAME into one GameQuest (OpenMW keys a log by name, not id --
-- a quest's parallel sub-ids, e.g. each Hortator councilor or Sixth House citadel, live under one name but
-- only the completion id carries "Finished"). `finishable` = ANY same-named record can finish (catalog-wide,
-- see nameGroups); `id` = the name's stable main id (nameGroups.mainId); `completed` = ANY started
-- member finished; `entries`/`recency` = union across members. Keeps the started member ids in `ids`.
local function collapseByName(quests, journalEntries)
    local groups, order = {}, {}
    for _, rq in ipairs(quests) do
        local key = rq.name:lower()
        local g = groups[key]
        if not g then g = { name = rq.name, members = {} }; groups[key] = g; order[#order + 1] = g end
        g.members[#g.members + 1] = rq
    end

    local out = {}
    local groups = nameGroups()
    for _, g in ipairs(order) do
        local memberIds, finishableIds, rawById = {}, {}, {}
        local completed = false
        for _, rq in ipairs(g.members) do
            memberIds[#memberIds + 1] = rq.id
            rawById[rq.id] = rq
            if rq.finished then completed = true end
            if rq.finishable then finishableIds[#finishableIds + 1] = rq.id end
        end
        local grp = groups[g.name:lower()]
        -- STABLE identity (`mainId`) = the catalog's main (lex-first finishable) record for this name. It
        -- doesn't flip as the player progresses (unlike a started-member pick), so pin/hide/last-viewed keyed
        -- on quest.id stay put even once the finishing record finally starts. Finishable names always have one.
        -- `activeId` = the STARTED branch supplying the live stage / id order (the main record may not be
        -- started yet in SHOTN's split quests). Both classify identically (same-named ids share a prefix).
        local activeId = groupMainId(#finishableIds > 0 and finishableIds or memberIds)
        local mainId   = (grp and grp.mainId) or activeId
        local _, ordered = groupMainId(memberIds, activeId)

        local techRows = {}   -- {id, stage} per STARTED constituent, active branch first (console use)
        for _, mid in ipairs(ordered) do
            techRows[#techRows + 1] = { id = mid, stage = rawById[mid].stage }
        end
        local entries, recency = unionEntries(journalEntries, memberIds)

        out[#out + 1] = {
            id = mainId,                 -- stable main id (identity / pin-hide key / metadata source)
            name = g.name,
            ids = ordered,               -- the player's started member ids, active branch first
            -- Catalog-wide: some record under this NAME can finish, not just the player's STARTED members.
            -- Keeps an in-progress quest visible when its finishing record only starts at completion.
            finishable = (grp and grp.mainId) ~= nil,
            completed = completed,        -- ANY member finished -- exactly OpenMW's log rule
            stage = rawById[activeId] and rawById[activeId].stage,   -- the active (started) branch's stage
            techRows = techRows,
            recency = recency,
            entries = entries,
        }
    end
    return out
end

-- 3. Keep only GameQuests whose NAME can finish somewhere in the catalog (drops journal noise: named
-- records that never finish under any same-named record). `finishable` is set catalog-wide in step 2, so an
-- in-progress quest survives even when only its non-finishing branch is currently started.
local function getOnlyFinishable(quests)
    local out = {}
    for _, q in ipairs(quests) do if q.finishable then out[#out + 1] = q end end
    return out
end

-- SSQN's iconlist is keyed by VANILLA quest-id prefixes. A non-vanilla id either doesn't match
-- (Cyrodiil/Skyrim -> SSQN's default) or, worse, FALSE-matches (Tamriel Rebuilt's 'tr_' hits Tribunal's
-- 'tr' -> the wrong expansion icon). So in plain 'SSQN' mode we only ask SSQN with a real id for vanilla
-- add-ons; every non-vanilla add-on gets SSQN's own default 'misc' banner, consistent across all mods.
-- In 'SSQN+' mode (`plus`) we ask SSQN by real id for EVERY add-on, relying on the user's installed SSQN
-- extension packs (e.g. the Great Patch Hub's Tamriel Rebuilt icons) to supply them.
local VANILLA_ADDON = { morrowind = true, tribunal = true, bloodmoon = true }
-- SSQN icon for a quest whose classified add-on is `addonKey`. Returns nil if SSQN isn't providing its
-- interface (the caller picks the fallback).
local function ssqnIcon(questId, addonKey, plus)
    local ssqn = I.SSQN
    if not (ssqn and ssqn.getQIcon) then return nil end
    if questId and (plus or VANILLA_ADDON[addonKey]) then return ssqn.getQIcon(questId) end
    return ssqn.getQIcon('')   -- non-vanilla in plain SSQN mode (or missing id) -> SSQN DEFAULT
end

-- Current icon-set selection from the IconPack setting, returned as (useSSQN, plus): `useSSQN` = draw SSQN's
-- icons at all ('ssqn' or 'ssqn_plus'); `plus` = the 'SSQN+' extended mode (see ssqnIcon). Read once per build
-- (icons are recomputed per open), so both the quest list and Stats stay on the same set.
local function iconMode()
    local pack = settings:get('IconPack')
    return (pack == 'ssqn' or pack == 'ssqn_plus'), pack == 'ssqn_plus'
end

-- Quest-list row icon. Built-in mode uses the pure classifier; SSQN mode reads it from SSQN (see ssqnIcon).
-- No fallback to built-in art when SSQN icons are selected: if SSQN isn't installed (load order is
-- irrelevant -- we read this at menu-open time), warn once and return SSQN's default path, which renders
-- blank without SSQN so the broken setup is visible rather than masked.
local ssqnWarned = false
local function rowIcon(questId, addonKey, useSSQN, plus)
    if not useSSQN then return icons.forQuest(questId) end
    local ic = ssqnIcon(questId, addonKey, plus)
    if ic then return ic end
    if not ssqnWarned then
        ssqnWarned = true
        print("[questman] Icon pack uses SSQN but the SSQN interface is unavailable -- is SSQN installed?")
    end
    return 'Icons\\SSQN\\DEFAULT.dds'
end

-- Stats-row icon. SSQN mode resolves the group's icon from a REPRESENTATIVE quest id + its add-on (see
-- ssqnIcon) -- SSQN's per-quest icons ARE faction/category/main-quest art, so any vanilla Mages Guild
-- quest id yields the guild icon, and finalQuests[addon] yields the add-on's main-quest icon; non-vanilla
-- groups get SSQN's default. Falls back to our built-in `builtin` when SSQN mode is off or SSQN is
-- unavailable (the quest LIST already surfaces a missing SSQN loudly, so Stats staying built-in there is
-- fine, not hiding anything).
local function statIcon(repId, addonKey, builtin, useSSQN, plus)
    if useSSQN then
        local ic = ssqnIcon(repId, addonKey, plus)
        if ic then return ic end
    end
    return builtin
end

-- 4. Enrich a GameQuest with its classification (add-on / category / faction) + icon + giver. Faction is
-- classified from the id now (not the giver): the mask gives the logical faction + its FACT id, which the
-- engine turns into a localized display name (Russian etc.); the giver supplies only the "quest giver" line.
-- `useSSQN`/`plus` select the icon set (read once per build via iconMode, see buildQuests).
local function enrichWithMetadata(quest, useSSQN, plus)
    local m = metaFor(quest.id)
    local cat = (m and CAT_KEY[m.category]) or 'unknown'
    local akey = (m and m.addon) or 'unknown'
    -- Faction is only meaningful for the two faction-based categories; elsewhere it's dropped so the detail
    -- pane hides the Faction line and Stats/filter grouping ignores it.
    local facCat = (cat == 'great_house' or cat == 'guild_faction')
    local factionDisplay, factionId
    if facCat and m and m.factionId then
        factionId = m.factionId
        factionDisplay = m.faction                       -- logical English name, base display
        local resolved = factionName(m.factionId)        -- the game's localized name, if the faction loads
        if resolved and resolved ~= m.factionId then factionDisplay = resolved end
        -- Great House names read "Great House Hlaalu" / "Великий Дом Хлаалу"; drop the leading qualifier
        -- word so they render compactly ("House Hlaalu" / "Дом Хлаалу"). Language-agnostic. Guilds untouched.
        if cat == 'great_house' then factionDisplay = factionDisplay:gsub('^%s*%S+%s+', '') end
    end

    local gi = giverForQuest(quest.name, quest.id)   -- opener across the name-group, not the main id
    quest.category   = cat                       -- six-way taxonomy slug, or 'unknown'
    quest.addon      = akey                      -- 'morrowind' | 'tribunal' | 'bloodmoon' | 'unknown'
    quest.addonLabel = addonSuffix(akey)         -- "Bloodmoon" / "Tribunal" (untranslated) or nil
    quest.faction    = factionDisplay            -- faction display name (faction categories only)
    quest.factionId  = factionId                 -- raw faction id (grouping key; faction categories only)
    quest.icon       = rowIcon(quest.id, akey, useSSQN, plus)
    quest.giver      = gi and gi.name            -- derived quest giver (display name), or nil
    quest.giverId    = gi and gi.id              -- raw npc id (for grouping)
end

-- Build the real quest-model list (the heavy path). Pin/hide flags are NOT set here -- getQuests stamps
-- them fresh on every call so toggles reflect at once.
local function buildQuests()
    local journalEntries = collectJournalEntries()
    local quests = readRawQuests()                      -- RawQuest[]
    quests = collapseByName(quests, journalEntries)     -- GameQuest[] (name-grouped)
    quests = getOnlyFinishable(quests)                  -- drop never-finishable groups
    local useSSQN, plus = iconMode()   -- read once per build (icons computed per open)
    for _, quest in ipairs(quests) do enrichWithMetadata(quest, useSSQN, plus) end
    return quests
end

-- Cached per open (see the per-open cache note above). Pin/hide state is re-stamped on EVERY call — a cheap
-- flag loop — so ctrl+click pin / eye-hide reflect instantly even when the heavy list came from the cache.
local function getQuests()
    if not cachedQuests then
        cachedQuests = buildQuests()
    end
    for _, q in ipairs(cachedQuests) do
        q.pinned = state.pinned[q.id] == true      -- ctrl+click pin -> floats to the top
        q.hidden = state.hidden[q.id] == true      -- Del / eye button -> kept out of the list
    end
    return cachedQuests
end

-- Single quest model for the detail pane (name/stage/category/entries/...).
local function getQuest(questId)
    for _, q in ipairs(getQuests()) do
        if q.id == questId then return q end
    end
    return nil
end

-- All real quests in the game (distinct by name), classified -> per-group TOTALS. Immutable -> cached.
local catalogCache
local function buildCatalog()
    if catalogCache then return catalogCache end
    local seenName, total, totA, totC, totF = {}, 0, {}, {}, {}
    for _, rec in pairs(core.dialogue.journal.records) do
        -- Dedupe by journal NAME (same identity rule as getQuests) so same-name variant ids count
        -- once. Classification keys off the record's id (see questMetadata).
        if isRealQuest(rec) and rec.questName and not seenName[rec.questName:lower()] then
            seenName[rec.questName:lower()] = true
            total = total + 1
            local a, c = addonKeyFor(rec.id), categoryKeyFor(rec.id)
            totA[a] = (totA[a] or 0) + 1
            totC[c] = (totC[c] or 0) + 1
            -- faction totals only for the faction-based categories (mirrors the per-quest model)
            local facCat = (c == 'great_house' or c == 'guild_faction')
            if facCat then
                local m = metaFor(rec.id)
                if m and m.factionId then totF[m.factionId] = (totF[m.factionId] or 0) + 1 end
            end
        end
    end
    catalogCache = { total = total, totA = totA, totC = totC, totF = totF }
    return catalogCache
end

-- Background prebuild, time-sliced. The heavy giver scan (the whole dialogue corpus) is the only init big
-- enough to stutter a frame, so we run it in a coroutine and spread it across frames: givers.resolve polls the
-- frame budget (below) and yields when it's spent. The cheaper scans (name groups / catalog -- journal records
-- only) stay lazy; they cost a few ms on the first open, no slicing needed. Immutable game data -> the map is
-- valid for the whole session. Driven by drivePrewarm in onUpdate.
--
-- Each frame's slice budget is a FRACTION of that frame's real duration (not a fixed ms), so it self-tunes to
-- the hardware: a high-refresh rig spends a gentle sliver of each short frame; a weak CPU spends a bigger slice
-- of each long frame, so the scan still finishes in a bounded number of frames instead of dragging on (which
-- would widen the window where an early open hits the synchronous fallback). The clamp floors progress on very
-- fast frames and caps the add on very slow ones, so no single slice can cause a visible hitch.
local PREWARM_FRAME_FRACTION = 0.30   -- share of the last frame's real time spent scanning
local PREWARM_MIN_SLICE = 0.002       -- s: floor, so high-FPS (short) frames still make progress
local PREWARM_MAX_SLICE = 0.008       -- s: ceiling, so one slice can't stall a frame enough to hitch (safe at 60 FPS)
local prewarmCo                -- the running coroutine while slicing; nil when idle or done
local prewarmStart             -- wall-clock start (for the sliced "Init" report)
local prewarmWork              -- scan time only, summed across frames (excludes the idle between them)
local frameDeadline            -- refreshed each driven frame; budgetSpent compares against it

-- Polled from inside givers.resolve: true once this frame's slice budget is spent.
local function budgetSpent()
    return core.getRealTime() >= frameDeadline
end

local function prewarmScan()
    giverMapCache = givers.resolve({ core.dialogue.topic, core.dialogue.greeting }, budgetSpent)
end

-- Advance the sliced prebuild by one frame's budget. A cheap no-op once idle/done. If a resume ever errors
-- (e.g. an unexpected yield boundary), we drop the coroutine and leave giverMapCache nil, so the next open
-- falls back to the synchronous giverMap() path -- degraded to the old behavior, never a crash.
local function drivePrewarm()
    if not prewarmCo then return end
    if giverMapCache then prewarmCo = nil; return end   -- a menu open already built it synchronously: drop the slicer
    -- getRealFrameDuration is wall time and ticks even while paused (unlike onUpdate's simulation dt)
    local slice = core.getRealFrameDuration() * PREWARM_FRAME_FRACTION
    slice = math.max(PREWARM_MIN_SLICE, math.min(PREWARM_MAX_SLICE, slice))
    frameDeadline = core.getRealTime() + slice
    local t0 = core.getRealTime()
    local ok, err = coroutine.resume(prewarmCo)
    prewarmWork = prewarmWork + (core.getRealTime() - t0)
    if not ok then
        dbg('prewarm error: ' .. tostring(err))
        prewarmCo = nil
    elseif coroutine.status(prewarmCo) == 'dead' then
        dbg(('Init: %.0f ms work, sliced over %.1f s'):format(prewarmWork * 1000, core.getRealTime() - prewarmStart))
        prewarmCo = nil
    end
end

-- Arm the background prebuild a beat after the world is live. Simulation time is paused during the loading
-- screen, so it starts ~1s into actual gameplay -- past the load spike, not on the load frame. Unsavable +
-- guarded so onInit (new game / freshly installed) and onLoad (loaded save) can't both arm it.
local PREWARM_DELAY = 1   -- simulation seconds of gameplay before slicing starts
local prewarmArmed = false
local function schedulePrewarm()
    if prewarmArmed then return end
    prewarmArmed = true
    async:newUnsavableSimulationTimer(PREWARM_DELAY, function()
        if prewarmCo or giverMapCache then return end   -- already slicing / already built
        prewarmStart = core.getRealTime()
        prewarmWork = 0
        prewarmCo = coroutine.create(prewarmScan)
    end)
end

-- factionId -> rank index that counts as "completed" (default = #ranks, the top named rank). Empty for
-- vanilla: every joinable faction's top rank is player-reachable (the only limit is that the three Great
-- Houses are mutually exclusive). Populate only if some faction is found to cap the player below its top.
local FACTION_TOP_RANK = {}

-- Has the player reached the highest rank of a faction? The faction questline's final promotion gates the
-- top rank, so this means "head of the faction — no further quests". `getFactionRank` is 1-based and the
-- engine's `ranks` list already excludes empty slots, so rank == #ranks is exactly the top named rank.
-- Branch-proof (unlike a per-sub-section "final quest" flag).
local function factionTopRankReached(fid)
    if not fid then return false end
    local ok, rank = pcall(types.NPC.getFactionRank, self, fid)
    if not ok or not rank or rank == 0 then return false end
    local rec = core.factions.records[fid]
    if not rec or #rec.ranks == 0 then return false end
    return rank >= (FACTION_TOP_RANK[fid] or #rec.ranks)
end

-- Stats for the Stats page: overall active/completed/total, and per addon/category/faction
-- done/total (touched groups only; done = completed). Totals = the whole-game catalog.
local function getStats()
    local quests = getQuests()
    local useSSQN, plus = iconMode()   -- Stats icons follow the same set as the quest list
    local active, completed = 0, 0
    -- add-ons list ALL catalog add-ons (touched or not), so no touched-set is needed for them.
    local doneA, doneC, doneF, touchC, touchF, facLabel = {}, {}, {}, {}, {}, {}
    -- Representative quest (id + add-on) per category / faction -> SSQN mode resolves the group icon from it
    -- (built-in mode ignores it). PREFER a vanilla rep: SSQN resolves a group's real icon only from vanilla
    -- ids (non-vanilla ids false-match, see ssqnIcon), so a vanilla rep keeps e.g. the Daedric row on the
    -- skull icon even if a Tamriel Rebuilt daedric quest was seen first.
    local catRepId, catRepAddon, facRepId, facRepAddon = {}, {}, {}, {}
    local houseF = {}   -- factionIds whose category is 'great_house' (mutually exclusive — see below)
    local function pickRep(id, addon, curId, curAddon)   -- keep the current rep unless we can upgrade to vanilla
        if not curId or (not VANILLA_ADDON[curAddon] and VANILLA_ADDON[addon]) then return id, addon end
        return curId, curAddon
    end
    for _, q in ipairs(quests) do
        local a, c = q.addon or 'unknown', q.category or 'unknown'
        if q.completed then completed = completed + 1 else active = active + 1 end
        touchC[c] = true
        catRepId[c], catRepAddon[c] = pickRep(q.id, a, catRepId[c], catRepAddon[c])
        if q.factionId then
            touchF[q.factionId] = true; facLabel[q.factionId] = q.faction
            facRepId[q.factionId], facRepAddon[q.factionId] = pickRep(q.id, a, facRepId[q.factionId], facRepAddon[q.factionId])
            if c == 'great_house' then houseF[q.factionId] = true end
        end
        if q.completed then
            doneA[a] = (doneA[a] or 0) + 1
            doneC[c] = (doneC[c] or 0) + 1
            if q.factionId then doneF[q.factionId] = (doneF[q.factionId] or 0) + 1 end
        end
    end
    -- totals = the whole-game catalog
    local cat = buildCatalog()
    local total, totA, totC, totF = cat.total, cat.totA, cat.totC, cat.totF
    local function rows(touch, done, tot, labelFn, orderFn)
        local out = {}
        for k in pairs(touch) do
            out[#out + 1] = { label = labelFn(k), done = done[k] or 0, total = tot[k] or 0, key = k }
        end
        table.sort(out, orderFn or function(x, y) return x.total > y.total end)
        return out
    end
    -- Add-ons: list ALL with quests in the catalog (not just touched ones), in fixed order, each with a
    -- main-quest-finished flag for the checkmark. We read that flag straight off `quests` — our own
    -- already-loaded, name-grouped models — instead of re-scanning the engine quest list once per id.
    -- Map every constituent journal id to whether ITS quest log is completed; since a log counts as
    -- completed when ANY of its ids finished, the "any alternative ending counts" rule falls out for free.
    local logCompletedByMemberId = {}
    for _, q in ipairs(quests) do
        logCompletedByMemberId[q.id:lower()] = q.completed
        for _, row in ipairs(q.techRows or {}) do logCompletedByMemberId[row.id:lower()] = q.completed end
    end
    local function mainQuestDone(ids)   -- ids: a single id, or a list of alternative-ending ids
        for _, id in ipairs(type(ids) == 'table' and ids or { ids }) do
            if logCompletedByMemberId[id:lower()] then return true end
        end
        return false
    end
    local mainDone = {}
    for akey, ids in pairs(questMetadata.finalQuests) do mainDone[akey] = mainQuestDone(ids) end
    local function addonRows()
        local out = {}
        for k, tot in pairs(totA) do
            if tot > 0 then
                local finalIds = questMetadata.finalQuests[k]   -- add-on icon = its main-quest icon (SSQN)
                out[#out + 1] = { label = ADDON_LABELS[k] or k, done = doneA[k] or 0, total = tot, key = k,
                                  mainDone = mainDone[k] == true,
                                  icon = statIcon(finalIds and finalIds[1], k, icons.forAddon(k), useSSQN, plus) }
            end
        end
        table.sort(out, addonRowLess)   -- Morrowind, Tribunal, Bloodmoon, then others alphabetical, Other last
        return out
    end
    local function byLabel(x, y) return x.label < y.label end   -- alphabetical (categories / factions)
    local byFaction = rows(touchF, doneF, totF, function(k) return facLabel[k] or k end, byLabel)
    for _, r in ipairs(byFaction) do
        r.topRank = factionTopRankReached(r.key)   -- highest-rank checkmark
        r.icon = statIcon(facRepId[r.key], facRepAddon[r.key], icons.forQuest(facRepId[r.key]), useSSQN, plus)
    end
    -- Great Houses are mutually exclusive: reaching one house's top rank permanently locks out the others.
    -- So instead of leaving the other touched houses blank (as if just unfinished), mark them with the
    -- completed house's name — the UI shows a grayed "completed elsewhere" check for them.
    local doneHouse
    for _, r in ipairs(byFaction) do
        if houseF[r.key] and r.topRank then doneHouse = r.label; break end
    end
    if doneHouse then
        for _, r in ipairs(byFaction) do
            if houseF[r.key] and not r.topRank then r.otherHouseDone = doneHouse end
        end
    end
    -- categories: Main Quest first, Miscellaneous last, the rest alphabetical (see catRowLess)
    local byCategory = rows(touchC, doneC, totC, function(k) return l10n('cat_' .. k) end, catRowLess)
    for _, r in ipairs(byCategory) do
        r.icon = statIcon(catRepId[r.key], catRepAddon[r.key], icons.forCategory(r.key), useSSQN, plus)
    end
    return {
        overall = { active = active, completed = completed, total = total },
        byAddon = addonRows(),
        byCategory = byCategory,
        byFaction = byFaction,
    }
end

-- Filter dropdown options: a single flat, ordered list of { axis, key, label, count } spanning the same
-- facets the Stats page groups by — add-ons (fixed order), then categories and factions (by count desc,
-- then label). Only facets present in the player's quests appear (an empty filter is never offered).
-- The UI groups consecutive same-axis options under section headers and applies one via questList.
local function getFilterOptions()
    local quests = getQuests()
    local c = questList.counts(quests)
    local opts = {}

    -- add-ons: same order as the Stats page (Morrowind/Tribunal/Bloodmoon, then others alphabetical, Other last)
    local addonKeys = {}
    for k in pairs(c.addon) do addonKeys[#addonKeys + 1] = k end
    table.sort(addonKeys, function(a, b)
        local ra, rb = addonRank(a), addonRank(b)
        if ra ~= rb then return ra < rb end
        return (ADDON_LABELS[a] or a) < (ADDON_LABELS[b] or b)
    end)
    for _, k in ipairs(addonKeys) do
        opts[#opts + 1] = { axis = 'addon', key = k, label = ADDON_LABELS[k] or k, count = c.addon[k] }
    end

    -- categories: same order as the Stats page (Main Quest first, Miscellaneous last, else alphabetical)
    local catKeys = {}
    for k in pairs(c.category) do catKeys[#catKeys + 1] = k end
    table.sort(catKeys, function(a, b)
        local ra, rb = catRank(a), catRank(b)
        if ra ~= rb then return ra < rb end
        return l10n('cat_' .. a) < l10n('cat_' .. b)
    end)
    for _, k in ipairs(catKeys) do
        opts[#opts + 1] = { axis = 'category', key = k, label = l10n('cat_' .. k), count = c.category[k] }
    end

    -- factions: display names already live on the quests (q.faction); alphabetical by label (matches Stats)
    local facLabel = {}
    for _, q in ipairs(quests) do if q.factionId then facLabel[q.factionId] = q.faction or q.factionId end end
    local facKeys = {}
    for k in pairs(c.faction) do facKeys[#facKeys + 1] = k end
    table.sort(facKeys, function(a, b) return (facLabel[a] or a) < (facLabel[b] or b) end)
    for _, k in ipairs(facKeys) do
        opts[#opts + 1] = { axis = 'faction', key = k, label = facLabel[k] or k, count = c.faction[k] }
    end

    return opts
end

-- The dialogue topics the player has accumulated through conversation (the vanilla journal "Topics"
-- index): a map keyed by topic name in types.Player.journal(self).topics. Returns { { id, name }, ... }
-- sorted CASE-SENSITIVELY by name (raw byte order -> capitalised proper nouns first, lowercase generic
-- topics like "my trade" last), mirroring the journal's own Topics list.
-- Cached per open (see the per-open cache note above).
local function getTopics()
    if cachedTopics then return cachedTopics end
    local journal = types.Player.journal(self)
    local topics = (journal and journal.topics) or {}
    local list = {}
    for _, t in pairs(topics) do list[#list + 1] = t end
    local out = {}
    for _, t in ipairs(list) do
        -- Some journal topics carry stray leading/trailing whitespace in the data (notably the Russian
        -- release, e.g. " Двемер"); untrimmed it sorts them to the very top (space < letters). Trim the
        -- DISPLAY name only — `id` stays as the journal's own key so getTopicLines/links still match.
        local name = t.name and t.name:gsub('^%s*(.-)%s*$', '%1')
        if name and name ~= '' then out[#out + 1] = { id = t.id, name = name } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    cachedTopics = out
    return out
end

-- The DISTINCT conversation lines the player heard for one topic (the first speaker of each unique line
-- wins), in accumulation order. Returns { { actor, text }, ... }; `text` has the @keyword# hyperlink markup
-- stripped, like journal entries.
local function distinctTopicLines(entries)
    local out, unique = {}, {}
    for _, e in ipairs(entries or {}) do
        local text = sanitizeText(e.text)
        if text and text ~= '' and not unique[text] then
            unique[text] = true
            out[#out + 1] = { actor = e.actor, text = text }
        end
    end
    return out
end

-- The RAW heard entries for one topic (text still carries the @keyword# hyperlink markup, needed for
-- link extraction). Returns { actor, text } entries as distinct/links read them.
local function rawTopicEntries(topicId)
    if not topicId then return {} end
    local journal = types.Player.journal(self)
    local topics = (journal and journal.topics) or {}
    for _, t in pairs(topics) do
        if t.id and t.id:lower() == topicId:lower() then return t.entries end
    end
    return {}
end

local function getTopicLines(topicId)
    return distinctTopicLines(rawTopicEntries(topicId))
end

-- lowercased-id -> proper name for every topic the player has accumulated. Used to resolve the
-- @keyword# hyperlinks embedded in topic text down to topics the player actually knows (dead links,
-- e.g. topics not yet learned, are dropped — we never offer a link that opens nothing).
local function accumulatedTopicNames()
    if cachedTopicNames then return cachedTopicNames end
    local byKey = {}
    local journal = types.Player.journal(self)
    local topics = (journal and journal.topics) or {}
    for _, t in pairs(topics) do
        -- Key by the CASE-FOLDED id so lowercase @keyword# markers match a capitalised Russian topic id
        -- (uiSearch.lower folds Cyrillic too; stock :lower() only folds ASCII). Keep the ORIGINAL id in the
        -- value: it's what getTopics/rawTopicEntries/openTopic match on, so links must emit it, not the fold.
        if t.id and t.name and t.name ~= '' then byKey[uiSearch.lower(t.id)] = { id = t.id, name = t.name } end
    end
    cachedTopicNames = byKey
    return byKey
end

-- A byte counts as part of a "word" if it's an ASCII letter/digit OR any non-ASCII byte (so Cyrillic and
-- other UTF-8 letters bound a word too). Used for whole-word matching so a topic name only matches when
-- flanked by spaces/punctuation, never inside a larger word.
local function isWordByte(c)
    if c == '' then return false end
    local b = string.byte(c)
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b > 127
end

-- Whole-word occurrence of `needle` in `blob` (both already lowercased).
local function containsWord(blob, needle)
    local from = 1
    while true do
        local s, e = blob:find(needle, from, true)
        if not s then return false end
        local before = (s > 1) and blob:sub(s - 1, s - 1) or ''
        local after = (e < #blob) and blob:sub(e + 1, e + 1) or ''
        if not isWordByte(before) and not isWordByte(after) then return true end
        from = s + 1
    end
end

-- Universal "chatter" topics (service / rumor / faction-admin topics attached to ~every NPC) that would just
-- add noise to a quest's / topic's "Related topics" list. Hand-curated, keyed by lowercased topic id; filtered
-- out of BOTH link sources in take() below. A fixed vanilla set (mods pile responses onto these rather than
-- adding new universal topics); province-mod generics (TR/PC/SHOTN) aren't covered until listed here. English
-- and Russian ids share one set — they never collide, so only the active language's ids ever match. Derived
-- from the dev known-topic stats dump (dev_features.lua) — response counts made the universal topics obvious.
local GENERIC_TOPICS = {
    -- English (Morrowind / Tribunal / Bloodmoon universal topics)
    ['background'] = true, ['latest rumors'] = true, ['my trade'] = true, ['little advice'] = true,
    ['little secret'] = true, ['someone in particular'] = true, ['duties'] = true, ['services'] = true,
    ['specific place'] = true, ['advancement'] = true, ['orders'] = true,
    -- Russian
    ['свежие сплетни'] = true, ['небольшой совет'] = true, ['маленький секрет'] = true, ['мое занятие'] = true,
    ['кто-то особенный'] = true, ['определенное место'] = true, ['задания'] = true, ['задание'] = true,
    ['приказы'] = true, ['повышение'] = true, ['услуги'] = true, ['услуга'] = true, ['биография'] = true,
    ['работа'] = true, ['дела'] = true, ['пойти вместе'] = true, ['направление'] = true, ['поговорить'] = true,
    ['долг'] = true, ['мудрость морроувинда'] = true, ['крепость'] = true, ['некромантия'] = true,
    ['загадка'] = true, ['рабство'] = true, ['вампиры'] = true,
}

-- Split a UTF-8 string into characters (Lua 5.1 has no utf8 lib). Needed because Cyrillic is 2 bytes/char,
-- so a byte-level prefix comparison could split a character mid-way; we compare whole characters.
local function utf8Chars(s)
    local chars, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
        chars[#chars + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

-- Russian @keyword# markers embed the topic name in a DECLINED grammatical case (genitive/dative/…),
-- which differs from the topic record's id (the nominative "standard form" — e.g. marker "озеру Фьялдинг"
-- vs topic id "Озеро Фьялдинг"). The engine folds these via a per-plugin .top translation file that Lua
-- can't read, so we approximate: Russian inflects word ENDINGS, not stems, so two words are the same word
-- in different cases when they share a long common prefix and differ only by a short (≤3-char) ending.
local STEM_MAX_ENDING = 3
local function wordStemMatch(a, b)   -- a, b: char arrays (from utf8Chars), already folded
    local shorter = math.min(#a, #b)
    if math.max(#a, #b) - shorter > STEM_MAX_ENDING then return false end
    local common = 0
    for i = 1, shorter do
        if a[i] == b[i] then common = common + 1 else break end
    end
    return common >= math.max(3, shorter - STEM_MAX_ENDING)
end

local function hasCyrillic(s) return s:find('[\208\209]') ~= nil end   -- UTF-8 lead bytes for U+0400..U+04FF

-- Collect the topics a sequence of { text=... } entries links to, resolved against `known` (folded-id
-- -> { id, name }), excluding `excludeKey` (self) and GENERIC_TOPICS. Two sources, merged + kept distinct, sorted:
--   1. Explicit @keyword# markers — hand-curated by localizers (heavy in the Russian release, ~absent in
--      English). Matched against `known` by exact fold first; a Cyrillic marker that misses (because it's in
--      a declined case) is resolved to its nominative topic id by word-stem matching (see resolveDeclined).
--   2. Keyword scan — mirrors the engine's auto-linking (English embeds no @-markers; it links by matching
--      known topic names in the plain text). Restricted to LATIN-script topics (name starts A-Z or a-z) so it
--      runs for English (incl. lowercase specifics like "trouble in the catacombs") but not Cyrillic — Russian
--      relies on the curated @-markers instead (its declension makes a nominative-only scan unreliable). Generic
--      chatter is dropped by GENERIC_TOPICS regardless of source, so lowercase no longer implies generic.
local function collectLinks(entries, known, excludeKey)
    local seen, out = {}, {}
    excludeKey = excludeKey and uiSearch.lower(excludeKey) or nil   -- fold to match `known`'s folded keys
    local function take(key)
        local rec = known[key]
        if rec and key ~= excludeKey and not seen[key] and not GENERIC_TOPICS[key] then
            seen[key] = true
            out[#out + 1] = { id = rec.id, name = rec.name }
        end
    end

    -- Known topic ids pre-split into folded words, built lazily (only when a declined marker needs resolving).
    local knownWords
    local function knownWordList()
        if not knownWords then
            knownWords = {}
            for key in pairs(known) do
                local words = {}
                for w in key:gmatch('%S+') do words[#words + 1] = utf8Chars(w) end
                knownWords[#knownWords + 1] = { key = key, words = words }
            end
        end
        return knownWords
    end

    -- Resolve a declined Cyrillic marker to its nominative topic id: the known topic with the same word
    -- count whose every word stem-matches. Only when EXACTLY ONE candidate matches — ambiguity drops the
    -- link rather than guessing wrong (mirrors "never offer a link that opens nothing").
    local function resolveDeclined(markerKey)
        local mWords = {}
        for w in markerKey:gmatch('%S+') do mWords[#mWords + 1] = utf8Chars(w) end
        if #mWords == 0 then return nil end
        local found
        for _, t in ipairs(knownWordList()) do
            if #t.words == #mWords and t.key ~= excludeKey and not GENERIC_TOPICS[t.key] then
                local all = true
                for i = 1, #mWords do
                    if not wordStemMatch(mWords[i], t.words[i]) then all = false; break end
                end
                if all then
                    if found then return nil end   -- ambiguous: two topics fit, don't guess
                    found = t.key
                end
            end
        end
        return found
    end

    for _, e in ipairs(entries or {}) do
        for kw in (e.text or ''):gmatch('@(.-)#') do
            -- fold + trim the marked phrase. An exact known topic wins; a Cyrillic miss is a declined case
            -- form (genitive/dative/…), resolved to its nominative topic id by stem matching.
            local key = uiSearch.lower(kw):gsub('^%s+', ''):gsub('%s+$', '')
            if known[key] then
                take(key)
            elseif hasCyrillic(key) then
                local resolved = resolveDeclined(key)
                if resolved then take(resolved) end
            end
        end
    end
    -- Keyword scan (Latin-script topics). Build the search blob lazily — many texts have no candidate.
    local blob
    for key, rec in pairs(known) do
        if not seen[key] and key ~= excludeKey and not GENERIC_TOPICS[key] and rec.name:match('^%s*[A-Za-z]') then
            if not blob then
                local parts = {}
                for _, e in ipairs(entries or {}) do parts[#parts + 1] = sanitizeText(e.text or '') end
                blob = table.concat(parts, '\n'):lower()
            end
            if containsWord(blob, rec.name:lower()) then take(key) end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The other topics this topic's lines hyperlink to (Morrowind embeds them as @keyword# in the raw text).
-- Returns { { id, name }, ... } — the "Related topics" list shown under the conversation.
local function getTopicLinks(topicId)
    if not topicId then return {} end
    cachedTopicLinks = cachedTopicLinks or {}
    local key = topicId:lower()
    if cachedTopicLinks[key] then return cachedTopicLinks[key] end   -- reselecting the same topic is free
    local links = collectLinks(rawTopicEntries(topicId), accumulatedTopicNames(), key)
    cachedTopicLinks[key] = links
    return links
end

-- The journal ids whose entries make up one quest LOG (OpenMW keys a log by name, not id, so several
-- variant ids can share it; same grouping getQuests uses). Falls back to the single id when
-- the quest is unnamed/unknown.
local function questMemberIds(questId)
    local rec = questRecord(questId)
    local name = rec and rec.questName
    if not name or name == '' then return { questId } end
    local ids = {}
    for _, q in pairs(types.Player.quests(self)) do
        if q.id then
            local r = questRecord(q.id)
            if r and r.questName == name then ids[#ids + 1] = q.id end
        end
    end
    return ids
end

-- RAW journal entries for one quest log — text still carries the @keyword# markup (collectJournalEntries
-- sanitizes its copy, so we read journalTextEntries directly here). Union across the log's name-group ids.
local function rawQuestEntries(questId)
    if not questId then return {} end
    local ids = {}
    for _, id in ipairs(questMemberIds(questId)) do ids[id:lower()] = true end
    local journal = types.Player.journal(self)
    local list = (journal and journal.journalTextEntries) or {}
    local out = {}
    for _, e in ipairs(list) do
        if e.questId and ids[e.questId:lower()] then out[#out + 1] = e end
    end
    return out
end

-- The accumulated topics this quest's journal entries hyperlink to — the "Related topics" list on the
-- quest detail page (clicking one jumps to the Topics page). Mirrors getTopicLinks but sources the
-- quest's journal entries instead of a topic's lines.
local function getQuestLinks(questId)
    if not questId then return {} end
    cachedQuestLinks = cachedQuestLinks or {}
    local key = questId:lower()
    if cachedQuestLinks[key] then return cachedQuestLinks[key] end   -- reselecting the same quest is free
    local links = collectLinks(rawQuestEntries(questId), accumulatedTopicNames(), nil)
    cachedQuestLinks[key] = links
    return links
end

-- ---------------------------------------------------------------------------
-- Records: journal records the player has entries for that AREN'T real quests (no QSTN name / never
-- shown in the Quests tab). Mirrors getTopics/getQuests, but sources the already-scanned journal
-- buckets (collectJournalEntries) so there's no second entry scan.
-- ---------------------------------------------------------------------------

-- Shorten `s` to about `maxChars` UTF-8 chars WITHOUT cutting a word: keep whole words until the next
-- would overflow the budget, then append " ...". The first word is always kept whole (never split), so a
-- lone over-long word is shown in full rather than mid-cut. Uses ASCII "..." not the "…" glyph -- the
-- Morrowind bitmap font has no U+2026 and renders it as a stray ".".
local function truncate(s, maxChars)
    if #utf8Chars(s) <= maxChars then return s end
    local out, count = {}, 0
    for word in s:gmatch('%S+') do
        local wlen = #utf8Chars(word)
        local sep = (count > 0) and 1 or 0
        if count > 0 and count + sep + wlen > maxChars then break end
        out[#out + 1] = word
        count = count + sep + wlen
    end
    return table.concat(out, ' ') .. '...'
end

-- A record's first info reads like a heading (a real title, e.g. "Blood Ties") rather than a narrative
-- entry: short and not ending in sentence punctuation.
local function isTitleLike(s)
    if not s or s == '' then return false end
    if #utf8Chars(s) > 45 then return false end
    return s:sub(-1):match('[%.%!%?;,]') == nil
end

-- Row label for a record (title-else-snippet): the record definition's LOWEST-stage info text when it's
-- title-like (independent of what the player has accumulated), otherwise the earliest visible entry text
-- truncated. Never the raw id (technical, and always English even in the RU game).
local function recordTitle(rec, entries)
    if rec and rec.infos then
        local bestStage, bestText
        for _, info in ipairs(rec.infos) do
            local st = info.questStage
            if st and (not bestStage or st < bestStage) then bestStage, bestText = st, info.text end
        end
        if bestText then
            local t = sanitizeText(bestText)
            if isTitleLike(t) then return t end
        end
    end
    return truncate((entries[1] and entries[1].text) or '', 30)
end

-- The non-quest journal records the player has entries for, newest-activity first. Reuses the cached
-- journal buckets; a bucket is a "record" when its id isn't a member of any quest shown in the Quests tab
-- (classifying against getQuests avoids duplicating name-grouped quests whose non-finishing member ids
-- would fail a per-record isRealQuest check).
local function getRecords()
    if cachedRecords then return cachedRecords end
    local questIds = {}
    for _, q in ipairs(getQuests()) do
        for _, mid in ipairs(q.ids or { q.id }) do questIds[mid:lower()] = true end
    end
    local out = {}
    for key, bucket in pairs(collectJournalEntries()) do   -- key = lowercased journal id
        if not questIds[key] then
            out[#out + 1] = {
                id = bucket.id,
                name = recordTitle(questRecord(bucket.id), bucket.entries),  -- display label (title-else-snippet)
                entries = bucket.entries,   -- oldest -> newest; { text, day, month, dayOfMonth, index }
                recency = bucket.lastIndex,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.recency ~= b.recency then return a.recency > b.recency end
        return a.id:lower() < b.id:lower()
    end)
    cachedRecords = out
    return out
end

local function setLastViewed(id) state.lastViewed = id end
local function getLastViewed() return state.lastViewed end
local function setLastViewedTopic(id) state.lastViewedTopic = id end
local function getLastViewedTopic() return state.lastViewedTopic end

local function isPinned(id) return id ~= nil and state.pinned[id] == true end
-- Toggle a quest's pinned flag (ctrl+click). Persisted per save via onSave/onLoad.
local function togglePin(id)
    if not id then return end
    if state.pinned[id] then state.pinned[id] = nil else state.pinned[id] = true end
    dbg('togglePin', id, '->', tostring(state.pinned[id] == true))
end

local function isHidden(id) return id ~= nil and state.hidden[id] == true end
-- Toggle a quest's hidden flag (Del / the detail-pane eye button). Persisted per save.
local function toggleHide(id)
    if not id then return end
    if state.hidden[id] then state.hidden[id] = nil else state.hidden[id] = true end
    dbg('toggleHide', id, '->', tostring(state.hidden[id] == true))
end

-- ---------------------------------------------------------------------------
-- persistence
-- ---------------------------------------------------------------------------

local function onSave()
    return { lastViewed = state.lastViewed, lastViewedTopic = state.lastViewedTopic,
             pinned = state.pinned, hidden = state.hidden }
end

local function onLoad(data)
    if data then
        state.lastViewed = data.lastViewed
        state.lastViewedTopic = data.lastViewedTopic
        state.pinned = data.pinned or {}
        state.hidden = data.hidden or {}
    end
    invalidateCache()   -- a loaded save has a different journal; drop any cached scans
    dbg('onLoad: lastViewed =', tostring(state.lastViewed))
    schedulePrewarm()
end

-- One-time snapshot logged on the FIRST menu open. Deliberately NOT gated by the Debug setting (unlike
-- dbg): when a player reports "something's broken", their openmw.log should already contain the key facts
-- without them having had to enable Debug first. A zero/low count, or an installed add-on showing 0, points
-- straight at a detection/classification problem.
-- `env` (optional) carries UI-only facts the data layer can't read itself: { screenW, screenH,
-- logicalW, logicalH } (physical vs logical/UI-scaled resolution). Supplied by ui.lua on first open.
-- `quests` (optional): the caller's already-built getQuests() list. Passing it in avoids a second full
-- scan on huge saves (the menu just built this list to draw the quest page).
local function logDiagnostics(env, quests)
    quests = quests or getQuests()
    local topics = getTopics()
    local finished = 0
    for _, q in ipairs(quests) do
        if q.completed then finished = finished + 1 end
    end
    local catTotal = buildCatalog().total   -- whole-game catalog count (started + not-yet-started)
    local journal = types.Player.journal(self)
    local journalEntries = #((journal and journal.journalTextEntries) or {})

    local function line(s) print('[questman]', s) end
    if env and env.screenW then
        local scale = (env.logicalW and env.logicalW > 0) and (env.screenW / env.logicalW) or 1
        line(('Player screen: %.0fx%.0f (%.0fx%.0f), GUI scale %.2f')
            :format(env.screenW, env.screenH, env.logicalW or 0, env.logicalH or 0, scale))
    end
    line(('Quests: %d started, %d finished, %d total'):format(#quests, finished, catTotal))
    line(('Topics: %d. Journal entries: %d'):format(#topics, journalEntries))
end

return {
    interfaceName = 'QuestmanData',
    interface = {
        version = 1,
        invalidate = invalidateCache,   -- ui.lua calls this at the start of each open -> fresh data per open
        logDiagnostics = logDiagnostics,
        getQuests = getQuests,
        getQuest = getQuest,
        getTopics = getTopics,
        getTopicLines = getTopicLines,
        getTopicLinks = getTopicLinks,
        getQuestLinks = getQuestLinks,
        getRecords = getRecords,
        getStats = getStats,
        getFilterOptions = getFilterOptions,
        getLastViewed = getLastViewed,
        setLastViewed = setLastViewed,
        getLastViewedTopic = getLastViewedTopic,
        setLastViewedTopic = setLastViewedTopic,
        isPinned = isPinned,
        togglePin = togglePin,
        isHidden = isHidden,
        toggleHide = toggleHide,
    },
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onInit = schedulePrewarm,   -- new game / freshly installed: arm the same background prebuild (no onLoad)
        onUpdate = drivePrewarm,    -- advances the sliced giver scan one budget-slice per frame while it runs
    },
}
