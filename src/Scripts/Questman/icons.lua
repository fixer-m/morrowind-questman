-- questman: map a quest to a bundled icon path (NO runtime icon-pack dependency).
-- Pure module (its only dependency is the pure questMetadata classifier) -> unit-testable.
--
-- Icons are chosen from the quest's classification (scripts/questman/questMetadata.lua):
--   * Main Quest   -> its add-on's icon (Morrowind / Tribunal / Bloodmoon / Tamriel Rebuilt / ...)
--   * Great House / Guild-Faction -> per the classified `faction`
--   * Vampire / Daedric / Misc / Bounty / Narsis Arena / Abecette Fight Pit -> one icon per category
-- Anything unclassified (unknown mod ids), or any facet still without dedicated art, falls back to misc.

local questMetadata = require('scripts.questman.questMetadata')

local DIR = 'Icons/questman/'
local DEFAULT = DIR .. 'cat_misc.dds'

-- Add-on icon by the classified `addon` SLUG (questMetadata emits slugs). Used both for a Main Quest's icon
-- (it inherits its add-on's art, see forQuest) and for the Stats "By add-ons" rows (forAddon). The 'unknown'
-- catch-all ("Other") falls back to the misc icon. Add a new add-on's art by appending one slug row here.
local ADDON_ICON = {
    morrowind        = 'addon_morrowind.dds',
    tribunal         = 'addon_tribunal.dds',
    bloodmoon        = 'addon_bloodmoon.dds',
    tamriel_rebuilt  = 'addon_tamriel.dds',
    project_cyrodiil = 'addon_cyrodiil.dds',
    province_skyrim  = 'addon_skyrim.dds',
}

-- Category slug (the six-way taxonomy) -> a single icon, for the Stats "By categories" rows.
-- great_house / guild_faction use dedicated "shared" art (the category spans all houses / all factions).
local CATEGORY_ICON = {
    main_quest         = 'addon_morrowind.dds',  -- the iconic Morrowind main-quest art
    great_house        = 'gh_shared.dds',        -- spans all three Great Houses
    guild_faction      = 'fa_shared.dds',        -- spans every guild/faction
    vampire            = 'cat_vampires.dds',
    daedric            = 'cat_daedric.dds',
    misc               = 'cat_misc.dds',
    bounty             = 'cat_bounty.dds',
    narsis_arena       = 'cat_narsis_arena.dds',
    abecette_fight_pit = 'cat_abecette.dds',
}

-- Categories that get one icon regardless of faction/add-on.
local BY_CATEGORY = {
    ['Vampire Quests']       = 'cat_vampires.dds',
    ['Daedric Quests']       = 'cat_daedric.dds',
    ['Miscellaneous Quests'] = 'cat_misc.dds',
    ['Bounty']               = 'cat_bounty.dds',
    ['Narsis Arena']         = 'cat_narsis_arena.dds',
    ['Abecette Fight Pit']   = 'cat_abecette.dds',
}

-- Great House + Guild-Faction quests: icon keyed by the classified `faction` string.
local BY_FACTION = {
    ['House Hlaalu']        = 'gh_hlalu.dds',
    ['House Redoran']       = 'gh_redoran.dds',
    ['House Telvanni']      = 'gh_telvanni.dds',
    ['House Indoril']       = 'gh_indoril.dds',   -- Tamriel Rebuilt (map 3)
    ['Fighters Guild']      = 'fa_fighters.dds',
    ['Mages Guild']         = 'fa_mages.dds',
    ['Thieves Guild']       = 'fa_thieves.dds',
    ['East Empire Company'] = 'fa_eec.dds',
    ['Tribunal Temple']     = 'fa_temple.dds',
    ['Imperial Legion']     = 'fa_imp_legion.dds',
    ['Imperial Cult']       = 'fa_imp_cult.dds',
    ['Morag Tong']          = 'fa_morag_tong.dds',
    ['Ja-Natta Syndicate']  = 'fa_janatta.dds',   -- Tamriel Rebuilt
    ['Ordinators']          = 'fa_ordinators.dds', -- Tamriel Rebuilt (map 3)
    ['Kingdom of Anvil']    = 'fa_anvil.dds',      -- Project Cyrodiil
    ['Itinerant Priests']   = 'fa_priests.dds',    -- Project Cyrodiil
}

local M = {}
M.DEFAULT = DEFAULT

--- VFS texture path for a quest id, from its classified category/faction/add-on (questMetadata).
-- @param questId #string
-- @return #string
function M.forQuest(questId)
    if type(questId) ~= 'string' then return DEFAULT end
    local m = questMetadata.get(questId)
    if not m then return DEFAULT end
    if m.category == 'Main Quest' then
        -- a Main Quest inherits its add-on's icon; a truly unknown add-on falls back to misc
        return DIR .. (ADDON_ICON[m.addon] or 'cat_misc.dds')
    end
    local file = (m.faction and BY_FACTION[m.faction]) or BY_CATEGORY[m.category]
    return file and (DIR .. file) or DEFAULT
end

-- Stats "By add-ons" rows reuse ADDON_ICON (defined above, keyed by the same add-on slug).
function M.forAddon(addonKey)
    return DIR .. (ADDON_ICON[addonKey] or 'cat_misc.dds')
end

function M.forCategory(catKey)
    return DIR .. (CATEGORY_ICON[catKey] or 'cat_misc.dds')
end

return M
