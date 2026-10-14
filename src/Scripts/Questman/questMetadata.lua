-- questman: quest classification from the journal id (prefix/pattern masks). Pure module (no engine deps) — the classification
-- DATA plus the `get(id)` accessor that reads it.
--
-- Why the id: OpenMW gives no runtime way to read a journal record's source file or faction (a DialogueRecord exposes only
-- id/name/questName/infos), so a quest's add-on/faction/category can only be inferred from its id. Morrowind ids are prefixed
-- by questline (MG_ = Mages Guild, TT_ = Temple, A#_/B#_ = main quest, ...) — a clean, extensible signal that also lets
-- third-party mods self-classify by choosing a prefix.
--
-- Two independent axes (a quest has ONE category; only guild/house quests have a faction):
--   * category — Main Quest, Guild Faction, Great House, Daedric, Vampire, Miscellaneous (+ add-on categories: Bounty,
--                Narsis Arena, Abecette Fight Pit); unrecognised ids fall back to Unknown.
--   * faction  — the joinable in-game faction, ONLY for guild/house questlines (Daedric and Vampire are categories, not factions).
--
-- Detection is TWO-STAGE (see `allAddonsRules`): the add-on first, then faction/category WITHIN it. Stage 1 matters because some
-- add-ons share a prefix — Tamriel Rebuilt uses TR_ like vanilla Tribunal, but every TR id carries a region infix (_m1_.._m10_)
-- or the NecMQ tag vanilla lacks, so an `addonRule` identifies it. Morrowind and Tribunal share the MS_ prefix and can't be gated
-- apart, so they live together in `vanillaRules`, the un-gated fallback set where the add-on is set per-rule.
--
-- Lookup (`get`): pick the first `allAddonsRules` set whose `addonRule` matches (the un-gated set is the fallback) → the first
-- matching `patterns` entry → merge `overrides[id]` on top (a full override can classify an id no pattern matched). Patterns are
-- tried in order, so put specific before general. `overrides` handles the two prefixes patterns can't fully decide: `^bm_`
-- (Bloodmoon main vs side quests) and `^ms_` (Morrowind vs Tribunal miscellaneous).

-- The joinable in-game factions: logical name (the key, used by the patterns below and as the "keep the
-- guild joined across add-ons" bucket) -> { id = FACT editor id for the game's localized display name,
-- category = its fixed category }. This is the ONLY place a guild/house quest's category is stored — it is
-- derived from the faction, never duplicated onto a pattern. Province mods ship their OWN guild factions
-- (T_Cyr_MagesGuild, ...), but the patterns map those quests to the vanilla logical faction, so all "Mages
-- Guild" quests share one bucket. Real add-on factionIds appear only for factions with no vanilla twin.
local factions = {
    -- Guilds / factions
    ["Mages Guild"]         = { id = "Mages Guild",            category = "Guild Faction Quests" },
    ["Fighters Guild"]      = { id = "Fighters Guild",         category = "Guild Faction Quests" },
    ["Thieves Guild"]       = { id = "Thieves Guild",          category = "Guild Faction Quests" },
    ["Morag Tong"]          = { id = "Morag Tong",             category = "Guild Faction Quests" },
    ["Imperial Legion"]     = { id = "Imperial Legion",        category = "Guild Faction Quests" },
    ["Imperial Cult"]       = { id = "Imperial Cult",          category = "Guild Faction Quests" },
    ["East Empire Company"] = { id = "East Empire Company",    category = "Guild Faction Quests" },
    ["Tribunal Temple"]     = { id = "Temple",                 category = "Guild Faction Quests" }, -- FACT id is "Temple"
    ["Ja-Natta Syndicate"]  = { id = "T_Mw_JaNattaSyndicate",  category = "Guild Faction Quests" }, -- Tamriel Rebuilt
    ["Ordinators"]          = { id = "T_Mw_Ordinators",        category = "Guild Faction Quests" }, -- Tamriel Rebuilt (map 3)
    ["Kingdom of Anvil"]    = { id = "T_Cyr_KingdomAnvil",     category = "Guild Faction Quests" }, -- Project Cyrodiil
    ["Itinerant Priests"]   = { id = "T_Cyr_ItinerantPriests", category = "Guild Faction Quests" }, -- Project Cyrodiil
    -- Great Houses
    ["House Hlaalu"]        = { id = "Hlaalu",                 category = "Great House Quests" },
    ["House Redoran"]       = { id = "Redoran",                category = "Great House Quests" },
    ["House Telvanni"]      = { id = "Telvanni",               category = "Great House Quests" },
    ["House Indoril"]       = { id = "T_Mw_HouseIndoril",      category = "Great House Quests" }, -- Tamriel Rebuilt (map 3)
}

-- Main-quest finale(s) per add-on: completing any listed id marks that add-on's main quest as done
-- (Morrowind has two mutually-exclusive endings). Lowercase ids, compared case-insensitively like
-- every other id lookup. Not derivable from a prefix, so it lives here as explicit data.
local finalQuests = {
    morrowind       = { "c3_destroydagoth", "cx_backpath" },  -- kill Dagoth Ur, OR the back-path ending
    tribunal        = { "tr_sothasil" },                      -- kill Sotha Sil
    bloodmoon       = { "bm_wildhunt" },                      -- Bloodmoon finale (Hircine's Hunt)
    tamriel_rebuilt = { "tr_necmq_3", "tr_necmq_3tribunal" }, -- Necrom main quest finale (base + Tribunal-installed variant)
}

-- Tamriel Rebuilt (add-on). addonRule: a region infix (_m1_.._m10_) or the NecMQ tag — neither exists in
-- vanilla Tribunal, so this can't capture a vanilla id. Add-on is fixed here, so the stage-2 patterns just
-- look for the faction tag as a delimited token "_<tag>[_%d]" anywhere in the id.
-- LIMITATION: ids are lowercased, so a tag glued straight onto a following word (e.g. MGBonus) is
-- indistinguishable from those letters inside a name (Illene ~ _il); those fall to the catch-all.
local tamrielRebuiltRules = {
    addon     = "tamriel_rebuilt",
    addonRule = { "^tr_m%d", "^tr_necmq" },
    patterns  = {
        { pattern = "necmq",     category = "Main Quest" },
        { pattern = "_hh[_%d]",  faction  = "House Hlaalu" },
        { pattern = "_hr[_%d]",  faction  = "House Redoran" },
        { pattern = "_ht[_%d]",  faction  = "House Telvanni" },
        { pattern = "_hi[_%d]",  faction  = "House Indoril" }, -- TR_m3_HI_* (Almalexia questline)
        { pattern = "_ord[_%d]", faction  = "Ordinators" },   -- TR_m3_Ord_* / TR_m4_Ord_Rite
        { pattern = "_eec[_%d]", faction  = "East Empire Company" },
        { pattern = "_fg[_%d]",  faction  = "Fighters Guild" },
        { pattern = "_ic[_%d]",  faction  = "Imperial Cult" },
        { pattern = "_il[_%d]",  faction  = "Imperial Legion" },
        { pattern = "_jns[_%d]", faction  = "Ja-Natta Syndicate" },
        { pattern = "_mg[_%d]",  faction  = "Mages Guild" },
        { pattern = "_mt[_%d]",  faction  = "Morag Tong" },
        { pattern = "_tg[_%d]",  faction  = "Thieves Guild" },
        { pattern = "_tt[_%d]",  faction  = "Tribunal Temple" },
        { pattern = "_da[_%d]",  category = "Daedric Quests" },
        { pattern = "_va[_%d]",  category = "Vampire Quests" },
        { pattern = "_bal[_%d]", category = "Vampire Quests" }, -- vampire clan (Bal...) ids
        { pattern = "_arena[_%d]",  category = "Narsis Arena" }, -- TR_m7_Ns_Arena_NN
        { pattern = "_and_bounty_", category = "Bounty" }, -- TR_m4_And_Bounty_*
        { pattern = "_b_",          category = "Bounty" }, -- TR_m3_B_* (delimited single-B bounty marker)
        { pattern = "_uman_b%d",    category = "Bounty" }, -- TR_m4_Uman_B1..3
        { pattern = ".",         category = "Miscellaneous Quests" }, -- catch-all: TR id, tag not recognised
    },
}

-- Project Cyrodiil (add-on). Same shape as Tamriel Rebuilt: prefix PC_ + region infix _m<region>_.
-- addonRule on PC_m%d (unique prefix, no overlap with vanilla or TR). Reuses the shared guild tokens
-- (_mg_/_tg_/_fg_) plus two Cyrodiil-only factions (Kingdom of Anvil, Itinerant Priests) and the Abecette
-- Fight Pit category (_afp%d, like Narsis Arena).
local projectCyrodiilRules = {
    addon     = "project_cyrodiil",
    addonRule = { "^pc_m%d" },
    patterns  = {
        { pattern = "_mg[_%d]",     faction  = "Mages Guild" },
        { pattern = "_tg[_%d]",     faction  = "Thieves Guild" },
        { pattern = "_fg[_%d]",     faction  = "Fighters Guild" },
        { pattern = "_k1[_%d]",     faction  = "Kingdom of Anvil" },   -- Kingdom of Anvil questline
        { pattern = "_ip[_%d]",     faction  = "Itinerant Priests" },
        { pattern = "_bounty[_%d]", category = "Bounty" },
        { pattern = "_afp%d",       category = "Abecette Fight Pit" }, -- PC_m1_AFP01 ..
        { pattern = ".",            category = "Miscellaneous Quests" }, -- catch-all
    },
}

-- Province: Skyrim (add-on, SHOTN). Prefix Sky_; ids are Sky_qRe_<AREA><FACTION><N>_Journal, so the
-- faction is a 2-letter suffix glued onto the area code (DSTG, KWMG, ...) rather than a delimited token —
-- matched as "<tag>%d" (validated 0 false-positive within Sky_). Clan Khulari and the Direnni Registers
-- questline have no separable token and stay Miscellaneous by choice.
local provinceSkyrimRules = {
    addon     = "province_skyrim",
    addonRule = { "^sky_" },
    patterns  = {
        { pattern = "tg%d", faction  = "Thieves Guild" },
        { pattern = "mg%d", faction  = "Mages Guild" },
        { pattern = "fg%d", faction  = "Fighters Guild" },
        { pattern = "b%d",  category = "Bounty" }, -- DSB/KWB bounty codes
        { pattern = ".",    category = "Miscellaneous Quests" }, -- catch-all
    },
}

-- Vanilla mainland: Morrowind + Tribunal (+ Bloodmoon). No addonRule — this is the fallback set. Add-on is
-- per-pattern because MS_ is shared between Morrowind and Tribunal (resolved by `overrides`).
local vanillaRules = {
    patterns = {
        -- Guild & faction questlines. The 2-letter tag is followed by '_' in every id.
        { pattern = "^fg_", addon = "morrowind", faction = "Fighters Guild" },
        { pattern = "^mg_", addon = "morrowind", faction = "Mages Guild" },
        { pattern = "^tg_", addon = "morrowind", faction = "Thieves Guild" },
        { pattern = "^mt_", addon = "morrowind", faction = "Morag Tong" },
        { pattern = "^il_", addon = "morrowind", faction = "Imperial Legion" },
        { pattern = "^ic",  addon = "morrowind", faction = "Imperial Cult" },      -- ic_ and ic1_ .. ic30_ (a digit may follow with no '_')
        { pattern = "^tt_", addon = "morrowind", faction = "Tribunal Temple" },
        { pattern = "^co_", addon = "bloodmoon", faction = "East Empire Company" },
        { pattern = "^hh_", addon = "morrowind", faction = "House Hlaalu" },
        { pattern = "^hr_", addon = "morrowind", faction = "House Redoran" },
        { pattern = "^ht_", addon = "morrowind", faction = "House Telvanni" },

        -- Daedric & Vampire — categories, no faction
        { pattern = "^da_", addon = "morrowind", category = "Daedric Quests" },
        { pattern = "^va_", addon = "morrowind", category = "Vampire Quests" },

        -- Main quest. Morrowind main-quest ids are <letter><number>_ (A1_, B2c_, C0_): a letter followed by
        -- a digit, written as an anchored letter + %d.
        { pattern = "^a%d", addon = "morrowind", category = "Main Quest" },
        { pattern = "^b%d", addon = "morrowind", category = "Main Quest" },
        { pattern = "^c%d", addon = "morrowind", category = "Main Quest" },
        { pattern = "^cx_", addon = "morrowind", category = "Main Quest" }, -- lone non-numbered main-quest id (CX_BackPath)
        { pattern = "^tr",  addon = "tribunal",  category = "Main Quest" }, -- vanilla Tribunal (tr_, tr05_..tr09_); TR-mod ids already handled above
        { pattern = "^bm_", addon = "bloodmoon", category = "Main Quest" }, -- Bloodmoon main quest (side quests -> overrides)

        -- Miscellaneous / side quests, no faction
        { pattern = "^ms_",      addon = "tribunal",  category = "Miscellaneous Quests" }, -- mixed MW/Tribunal (see overrides)
        { pattern = "^mv_",      addon = "morrowind", category = "Miscellaneous Quests" },
        { pattern = "^eb",       addon = "morrowind", category = "Miscellaneous Quests" }, -- eb_ and ebq_
        { pattern = "^blades_",  addon = "morrowind", category = "Miscellaneous Quests" },
        { pattern = "^town_",    addon = "morrowind", category = "Miscellaneous Quests" },
        { pattern = "^romance_", addon = "morrowind", category = "Miscellaneous Quests" },
    },
}

-- Stage-1 add-on rule sets, tried in order: gated sets first, the ungated `vanillaRules` fallback last.
local allAddonsRules = {
    tamrielRebuiltRules,
    projectCyrodiilRules,
    provinceSkyrimRules,
    vanillaRules,
}

-- Per-id exceptions the patterns get wrong. Keyed by LOWERCASE journal id. Each entry lists ONLY the
-- fields that differ from the matched pattern.
local overrides = {
    -- A#_ main-quest prefix, but these two are actually side quests
    ["a1_sleeperdreamer02"] = { category = "Miscellaneous Quests" },
    ["a2_1_kurapli_zallay"] = { category = "Miscellaneous Quests" },

    -- BM_ defaults to Main Quest; these are Bloodmoon miscellaneous quests
    ["bm_airship"]        = { category = "Miscellaneous Quests" },
    ["bm_airship_a"]      = { category = "Miscellaneous Quests" },
    ["bm_airship_c"]      = { category = "Miscellaneous Quests" },
    ["bm_brodirgrove"]    = { category = "Miscellaneous Quests" },
    ["bm_cursedcaptain"]  = { category = "Miscellaneous Quests" },
    ["bm_cursedcaptain_a"]= { category = "Miscellaneous Quests" },
    ["bm_falmer"]         = { category = "Miscellaneous Quests" },
    ["bm_ingmar"]         = { category = "Miscellaneous Quests" },
    ["bm_meadhall"]       = { category = "Miscellaneous Quests" },
    ["bm_meadhall_a"]     = { category = "Miscellaneous Quests" },
    ["bm_meadhall_b"]     = { category = "Miscellaneous Quests" },
    ["bm_meadhall_c"]     = { category = "Miscellaneous Quests" },
    ["bm_missionary"]     = { category = "Miscellaneous Quests" },
    ["bm_moonsugar"]      = { category = "Miscellaneous Quests" },
    ["bm_retribution"]    = { category = "Miscellaneous Quests" },
    ["bm_sadseer"]        = { category = "Miscellaneous Quests" },
    ["bm_tymvaul"]        = { category = "Miscellaneous Quests" },
    ["bm_womanscorned"]   = { category = "Miscellaneous Quests" },

    -- MS_ defaults to Tribunal (its larger half); these MS_ ids are Morrowind (category stays Misc)
    ["ms_apologies"]           = { addon = "morrowind" },
    ["ms_arenimtomb"]          = { addon = "morrowind" },
    ["ms_fargothring"]         = { addon = "morrowind" },
    ["ms_firemoth"]            = { addon = "morrowind" },
    ["ms_gold_kanet_flower"]   = { addon = "morrowind" },
    ["ms_hannat"]              = { addon = "morrowind" },
    ["ms_hatandskirt"]         = { addon = "morrowind" },
    ["ms_hentuspants"]         = { addon = "morrowind" },
    ["ms_jobashaabolitionist"] = { addon = "morrowind" },
    ["ms_lookout"]             = { addon = "morrowind" },
    ["ms_master_index"]        = { addon = "morrowind" },
    ["ms_nord_burial"]         = { addon = "morrowind" },
    ["ms_nuccius"]             = { addon = "morrowind" },
    ["ms_piernette"]           = { addon = "morrowind" },
    ["ms_trerayna_bounty"]     = { addon = "morrowind" },
    ["ms_umbra"]               = { addon = "morrowind" },
    ["ms_vampirecure"]         = { addon = "morrowind" }, -- Morrowind Misc, not Vampire
    ["ms_vassirdidanat"]       = { addon = "morrowind" },
    ["ms_whiteguar"]           = { addon = "morrowind" },

    -- Tamriel Rebuilt: faction quests whose id carries NO faction token (the quest name confirms the
    -- faction). Handled explicitly, per the "outliers via overrides, not smarter regexes" rule.
    -- The RR_MQ set is House Telvanni's Roth Roryn questline (name: "House Telvanni: ...").
    ["tr_m1_rr_mq_1"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_2"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_2.5"] = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_3"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_4"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_5"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_6"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_6.5"] = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_7"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_8"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_9"]   = { faction = "House Telvanni" },
    ["tr_m1_rr_mq_10"]  = { faction = "House Telvanni" },
    ["tr_m4_and_missingmerchant"] = { faction = "House Hlaalu" },    -- "House Hlaalu: The Missing Merchant"
    ["tr_m3_at_mgbonus"]          = { faction = "Mages Guild" },     -- glued tag MGBonus ("Mages Guild: Azura's Star")
    ["tr_m0_siegeatfiremoth"]     = { faction = "Imperial Legion" }, -- "Imperial Legion: Siege at Firemoth"
    -- region-less TR id (no _m<region>_): would read as vanilla Tribunal without this. Name: "Temple: Initiation".
    ["tr_tt_q1"] = { addon = "tamriel_rebuilt", faction = "Tribunal Temple" },

    -- Project Cyrodiil: faction quests whose id uses a subregion token instead of the faction token.
    ["pc_m0_fw_colstalker"] = { faction = "Fighters Guild" },   -- "Fighters Guild: ..." (FW subregion token)
    ["pc_m1_anv_goldenrod"] = { faction = "Kingdom of Anvil" }, -- "Kingdom of Anvil: ..." (Anv subregion token)
}

-- Classify one journal id. Returns { addon, category, faction, factionId } or nil (neither add-on nor
-- category resolved -> an unknown mod id). `addon` is a STABLE slug (morrowind / tribunal / bloodmoon /
-- tamriel_rebuilt / project_cyrodiil / province_skyrim) -- an internal key, never renamed (it's the
-- persisted quest-filter key); the user-facing add-on TITLE is defined once in questProvider's ADDONS
-- table. `faction` is the logical name (a `factions` key); `factionId` is its FACT editor id for the
-- engine's localized display. See "Lookup model" above.
local function get(id)
    if not id then return nil end
    id = id:lower()

    local ruleSet
    for _, rs in ipairs(allAddonsRules) do
        if not rs.addonRule then ruleSet = rs; break end          -- the fallback set matches anything
        for _, gate in ipairs(rs.addonRule) do
            if id:match(gate) then ruleSet = rs; break end
        end
        if ruleSet then break end
    end

    local base
    if ruleSet then
        for _, p in ipairs(ruleSet.patterns) do
            if id:match(p.pattern) then base = p; break end
        end
    end

    local ov = overrides[id]
    local faction  = (ov and ov.faction) or (base and base.faction)
    local ovFac    = ov and ov.faction and factions[ov.faction]
    local facEntry = faction and factions[faction]
    local category = (ov and ov.category)
                     or (ovFac and ovFac.category)
                     or (base and base.category)
                     or (facEntry and facEntry.category)
    local addon = (ov and ov.addon) or (ruleSet and ruleSet.addon) or (base and base.addon)
    if not addon and not category then return nil end

    return {
        addon    = addon,
        category = category,
        faction  = faction,
        factionId = facEntry and facEntry.id or nil,
    }
end

return {
    factions       = factions,
    finalQuests    = finalQuests,
    allAddonsRules = allAddonsRules,
    overrides      = overrides,
    get            = get,
}
