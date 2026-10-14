-- Standalone tests for questman's pure (engine-free) modules.
-- Run from the plugin root:  lua tests/pure_spec.lua
-- The deployable modules live under src/ (src/Scripts/Questman/...), so resolve requires there.
package.path = './src/?.lua;./?.lua;' .. package.path

local icons = require('scripts.questman.icons')
local questMetadata = require('scripts.questman.questMetadata')
local uiSearch = require('scripts.questman.uiSearch')
local uiScroll = require('scripts.questman.uiScroll')
local uiResize = require('scripts.questman.uiResize')
local givers = require('scripts.questman.givers')
local questList = require('scripts.questman.questList')

local failures = 0
local function check(name, cond)
    if cond then
        print('  ok  - ' .. name)
    else
        failures = failures + 1
        print('  FAIL- ' .. name)
    end
end

-- icons.forQuest: questdb category/faction/add-on -> icon path (real ids from questdb) --------------
check('main quest MW -> addon',icons.forQuest('A1_1_FindSpymaster') == 'Icons/questman/addon_morrowind.dds')
check('main quest BM -> addon',icons.forQuest('BM_Rumors') == 'Icons/questman/addon_bloodmoon.dds')
check('great house Hlaalu',    icons.forQuest('HH_Crassius') == 'Icons/questman/gh_hlalu.dds')
check('great house Telvanni',  icons.forQuest('HT_AurielBow') == 'Icons/questman/gh_telvanni.dds')
check('guild Fighters',        icons.forQuest('FG_Nchurdamz') == 'Icons/questman/fa_fighters.dds')
check('guild Mages',           icons.forQuest('MG_Advancement') == 'Icons/questman/fa_mages.dds')
check('guild EEC (CO addon)',  icons.forQuest('CO_1') == 'Icons/questman/fa_eec.dds')
check('imperial legion',       icons.forQuest('IL_Courtesy') == 'Icons/questman/fa_imp_legion.dds')
check('case-insensitive id',   icons.forQuest('mg_advancement') == 'Icons/questman/fa_mages.dds')
check('vampire -> cat',        icons.forQuest('VA_VampChild') == 'Icons/questman/cat_vampires.dds')
check('daedric -> cat',        icons.forQuest('DA_Azura') == 'Icons/questman/cat_daedric.dds')
check('morag tong -> fa icon', icons.forQuest('MT_S_Red') == 'Icons/questman/fa_morag_tong.dds')
check('unknown id -> DEFAULT', icons.forQuest('zzz_unknown') == icons.DEFAULT)
check('non-string -> DEFAULT', icons.forQuest(nil) == icons.DEFAULT)

-- questMetadata.get: id -> { addon, category, faction, factionId } ----------------------------------
local function meta(id) return questMetadata.get(id) or {} end
-- vanilla guild: faction key == its FACT id
check('MG -> Mages Guild / Guild / Morrowind', (function() local m = meta('MG_Advancement')
    return m.addon == 'morrowind' and m.category == 'Guild Faction Quests'
       and m.faction == 'Mages Guild' and m.factionId == 'Mages Guild' end)())
check('get is case-insensitive', meta('mg_advancement').faction == 'Mages Guild')
-- Great House: faction display key differs from FACT id
check('HH -> House Hlaalu, factionId Hlaalu', (function() local m = meta('HH_Crassius')
    return m.category == 'Great House Quests' and m.faction == 'House Hlaalu' and m.factionId == 'Hlaalu' end)())
-- main quest / bloodmoon
check('A1_ -> Main Quest',   meta('A1_1_FindSpymaster').category == 'Main Quest')
check('BM_ -> Main / Bloodmoon', meta('BM_Rumors').category == 'Main Quest' and meta('BM_Rumors').addon == 'bloodmoon')
-- categories carry no faction
check('DA_ -> Daedric, no faction', meta('DA_Azura').category == 'Daedric Quests' and meta('DA_Azura').faction == nil)
check('VA_ -> Vampire, no faction', meta('VA_VampChild').category == 'Vampire Quests' and meta('VA_VampChild').faction == nil)
-- overrides
check('bm_airship override -> Misc', meta('bm_airship').category == 'Miscellaneous Quests')
check('ms_vampirecure -> Morrowind Misc (questdb bug fix)', (function() local m = meta('ms_vampirecure')
    return m.addon == 'morrowind' and m.category == 'Miscellaneous Quests' and m.faction == nil end)())
-- Tamriel Rebuilt (add-on)
check('TR RR_MQ override -> Telvanni / TR', (function() local m = meta('tr_m1_rr_mq_1')
    return m.addon == 'tamriel_rebuilt' and m.faction == 'House Telvanni' end)())
check('TR MGBonus glued override -> Mages Guild', meta('tr_m3_at_mgbonus').faction == 'Mages Guild')
check('TR _HI_ -> House Indoril / Great House', (function() local m = meta('tr_m3_hi_roadyr1')
    return m.addon == 'tamriel_rebuilt' and m.category == 'Great House Quests'
       and m.faction == 'House Indoril' and m.factionId == 'T_Mw_HouseIndoril' end)())
check('TR _Ord_ -> Ordinators / Guild Faction', (function() local m = meta('tr_m3_ord_watch1')
    return m.addon == 'tamriel_rebuilt' and m.category == 'Guild Faction Quests'
       and m.faction == 'Ordinators' and m.factionId == 'T_Mw_Ordinators' end)())
check('TR m4 Ord_Rite -> Ordinators', meta('tr_m4_ord_rite').faction == 'Ordinators')
check('TR tt_q1 override -> Temple factionId', (function() local m = meta('tr_tt_q1')
    return m.addon == 'tamriel_rebuilt' and m.faction == 'Tribunal Temple' and m.factionId == 'Temple' end)())
-- Project Cyrodiil: add-on faction keeps its real FACT id
check('PC Anvil override -> Kingdom of Anvil / T_Cyr_KingdomAnvil', (function() local m = meta('pc_m1_anv_goldenrod')
    return m.addon == 'project_cyrodiil' and m.faction == 'Kingdom of Anvil'
       and m.factionId == 'T_Cyr_KingdomAnvil' end)())
-- unknown mod id -> nil
check('unknown id -> nil', questMetadata.get('zzz_unknown_mod') == nil)
check('nil id -> nil', questMetadata.get(nil) == nil)

-- uiSearch.filter ------------------------------------------------------------
local quests = {
    { name = 'Dark Brotherhood Attacks', entries = { { text = 'an assassin attacked' } } },
    { name = 'Mehrunes Dagon', entries = { { text = 'shrine in the north' } } },
    { name = 'Fighters Guild Dues', entries = {} },
}
check('empty query returns all', #uiSearch.filter(quests, '') == 3)
check('name substring (case-insens)', #uiSearch.filter(quests, 'dark') == 1)
check('matches entry text', #uiSearch.filter(quests, 'assassin')[1] ~= nil
      and uiSearch.filter(quests, 'assassin')[1].name == 'Dark Brotherhood Attacks')
check('no match -> empty', #uiSearch.filter(quests, 'zzzzz') == 0)
check('case-insensitive ascii name', #uiSearch.filter(quests, 'DARK') == 1)
-- Cyrillic case-insensitivity (string.lower can't fold these)
local A, a = string.char(0xD0, 0x90), string.char(0xD0, 0xB0)   -- А / а
local YA, ya = string.char(0xD0, 0xAF), string.char(0xD1, 0x8F) -- Я / я
check('lower folds Cyrillic А->а', uiSearch.lower(A) == a)
check('lower folds Cyrillic Я->я', uiSearch.lower(YA) == ya)
check('lower keeps ascii', uiSearch.lower('AbC') == 'abc')
local ruQuests = { { name = A .. 'льмалексия' } }  -- "Альмалексия"
check('cyrillic search lower matches', #uiSearch.filter(ruQuests, a) == 1)
check('cyrillic search upper matches', #uiSearch.filter(ruQuests, A) == 1)
check('searchEntries=false ignores entries',
      #uiSearch.filter(quests, 'assassin', { searchEntries = false }) == 0)

-- questList.sortByRecency ------------------------------------------------
local toSort = {
    { name = 'B old active',   completed = false, recency = 1 },
    { name = 'A new active',   completed = false, recency = 5 },
    { name = 'C done recent',  completed = true,  recency = 9 },
    { name = 'D done old',     completed = true,  recency = 2 },
}
local s = questList.sortByRecency(toSort)
check('active before completed', not s[1].completed and not s[2].completed
      and s[3].completed and s[4].completed)
check('active sorted by recency desc', s[1].name == 'A new active' and s[2].name == 'B old active')
check('completed sorted by recency desc', s[3].name == 'C done recent' and s[4].name == 'D done old')
check('input not mutated', toSort[1].name == 'B old active')

-- pinned quests float above everything, including active ones
local toPin = {
    { name = 'A new active',  completed = false, recency = 9 },
    { name = 'P done pinned',  completed = true,  recency = 1, pinned = true },
    { name = 'B old active',  completed = false, recency = 2 },
}
local sp = questList.sortByRecency(toPin)
check('pinned first even when completed/old', sp[1].name == 'P done pinned')
check('non-pinned keep active-before-completed order', sp[2].name == 'A new active' and sp[3].name == 'B old active')

-- scroll math ---------------------------------------------------------------
check('maxOffset when content fits', uiScroll.maxOffset(100, 200) == 0)
check('maxOffset when content overflows', uiScroll.maxOffset(500, 200) == 300)
check('clamp low', uiScroll.clamp(-50, 500, 200) == 0)
check('clamp high', uiScroll.clamp(9999, 500, 200) == 300)
check('clamp mid', uiScroll.clamp(120, 500, 200) == 120)
local t1 = uiScroll.thumb(100, 200, 200, 0)
check('thumb hidden when content fits', t1.visible == false)
local t2 = uiScroll.thumb(400, 200, 200, 0)
check('thumb visible when overflow', t2.visible == true and t2.top == 0)
local t3 = uiScroll.thumb(400, 200, 200, 200) -- at max offset
check('thumb at bottom near track end', t3.top > 0 and (t3.top + t3.height) <= 200 + 0.01)
check('thumb slack hides bar for small overflow', uiScroll.thumb(210, 200, 200, 0, 16).visible == false)
check('thumb slack still shows bar past slack', uiScroll.thumb(220, 200, 200, 0, 16).visible == true)
check('estimateTextHeight one short line',
      uiScroll.estimateTextHeight('hi', 800, 8, 18) == 18)
check('estimateTextHeight wraps long line',
      uiScroll.estimateTextHeight(string.rep('x', 200), 80, 8, 18) == 20 * 18)
-- Cyrillic is 2 bytes/char: 10 chars must fit one 10-char line (18), not two (byte-count would give 36).
check('estimateTextHeight counts UTF-8 chars, not bytes',
      uiScroll.estimateTextHeight(string.rep('я', 10), 80, 8, 18) == 18)

-- givers -------------------------------------------------------------------
check('parseJournal quoted', (function()
    local r = givers.parseJournal('Journal "A1_1" 10')
    return #r == 1 and r[1].id == 'a1_1' and r[1].stage == 10
end)())
check('parseJournal quoted-with-spaces', (function()
    local r = givers.parseJournal('journal "Larrius Varro Tells a Little Story" 5')
    return #r == 1 and r[1].id == 'larrius varro tells a little story' and r[1].stage == 5
end)())
check('parseJournal unquoted', (function()
    local r = givers.parseJournal('Journal MG_Boots 100')
    return #r == 1 and r[1].id == 'mg_boots' and r[1].stage == 100
end)())
check('parseJournal none / non-string', #givers.parseJournal('SetFight 0') == 0
      and #givers.parseJournal(nil) == 0)

-- mock dialogue stores: quest q1 set at stage 10 by bob, at stage 1 by alice -> alice (lowest)
local stores = { {
    records = {
        { infos = {
            { resultScript = 'Journal "q1" 10', filterActorId = 'bob' },
            { resultScript = 'Journal "q1" 1',  filterActorId = 'alice' },
            { resultScript = 'Journal "q2" 1',  filterActorId = '', filterActorFaction = 'mages guild' },
            { resultScript = 'SetHello 50' },   -- no journal cmd
        } },
    },
} }
local gmap = givers.resolve(stores)
check('resolve picks lowest-stage giver', gmap['q1'] and gmap['q1'].actor == 'alice')
check('resolve captures faction when no actor', gmap['q2'] and gmap['q2'].faction == 'mages guild')
check('giverId resolves actor', givers.giverId(gmap, 'q1') == 'alice')
check('giverId case-insensitive', givers.giverId(gmap, 'Q1') == 'alice')
check('giverId faction-only -> nil', givers.giverId(gmap, 'q2') == nil)
check('giverId unknown -> nil', givers.giverId(gmap, 'nope') == nil)
check('giverId override wins', givers.giverId(gmap, 'q1', { q1 = 'caius' }) == 'caius')

-- sliced resolve: run inside a coroutine with a shouldYield that fires at every poll; the scan must yield
-- across "frames" yet still return the same map (state carried over yields). Journal cmd sits AFTER the
-- padding so it's only reached once work resumes past the yields.
local sliced = { infos = {} }
for i = 1, 300 do sliced.infos[i] = { resultScript = 'SetHello 0' } end   -- padding past YIELD_INTERVAL (128)
sliced.infos[#sliced.infos + 1] = { resultScript = 'Journal "qx" 5', filterActorId = 'zoe' }
local co = coroutine.create(function()
    return givers.resolve({ { records = { sliced } } }, function() return true end)
end)
local yields, allOk, slicedMap = 0, true, nil
while coroutine.status(co) ~= 'dead' do
    local ok, res = coroutine.resume(co)
    if not ok then allOk = false; break end
    if coroutine.status(co) == 'dead' then slicedMap = res else yields = yields + 1 end
end
check('sliced resolve resumes without error', allOk)
check('sliced resolve actually yielded', yields >= 2)
check('sliced resolve result matches sync', slicedMap and slicedMap['qx'] and slicedMap['qx'].actor == 'zoe')

-- giverForIds: the opener across ids sharing a name = the lowest-stage entry that has an actor
local gm2 = {
    dsmg4  = { actor = 'giverA', stage = 10 },   -- finishing record, opener at stage 10
    dsmg4a = { actor = 'giverB', stage = 30 },   -- a branch, later stage
    dsmg4c = { actor = '',       stage = 5  },   -- lower stage but no actor -> ignored
}
check('giverForIds picks lowest-stage actor', givers.giverForIds(gm2, { 'dsmg4a', 'dsmg4', 'dsmg4c' }) == 'giverA')
check('giverForIds case-insensitive ids', givers.giverForIds(gm2, { 'DSMG4' }) == 'giverA')
check('giverForIds none derivable -> nil', givers.giverForIds(gm2, { 'dsmg4c', 'nope' }) == nil)
check('giverForIds empty / bad args -> nil',
      givers.giverForIds(gm2, {}) == nil and givers.giverForIds(nil, { 'x' }) == nil)

-- questList ---------------------------------------------------------------
local fq = {
    { id = 'a', addon = 'morrowind', category = 'guild_faction', factionId = 'mages guild' },
    { id = 'b', addon = 'tribunal',  category = 'guild_faction', factionId = 'fighters guild' },
    { id = 'c', addon = 'tribunal',  category = 'great_house',   factionId = nil },           -- no faction
    { id = 'd',                       category = 'main_quest',    factionId = 'mages guild' }, -- no addon -> 'unknown' (Other)
}
check('matches nil selection -> all', questList.matches(fq[1], nil) == true)
check('matches addon', questList.matches(fq[2], { axis = 'addon', key = 'tribunal' }) == true)
check('matches addon miss', questList.matches(fq[1], { axis = 'addon', key = 'tribunal' }) == false)
check('matches faction', questList.matches(fq[1], { axis = 'faction', key = 'mages guild' }) == true)
check('matches faction nil never matches', questList.matches(fq[3], { axis = 'faction', key = 'mages guild' }) == false)
check('keyOf addon defaults unknown', questList.keyOf(fq[4], 'addon') == 'unknown')
check('keyOf category defaults unknown', questList.keyOf({}, 'category') == 'unknown')
check('apply nil -> unchanged', #questList.apply(fq, nil) == 4)
check('apply addon tribunal -> 2', #questList.apply(fq, { axis = 'addon', key = 'tribunal' }) == 2)
check('apply category guild_faction -> 2', #questList.apply(fq, { axis = 'category', key = 'guild_faction' }) == 2)
check('apply faction mages -> 2', #questList.apply(fq, { axis = 'faction', key = 'mages guild' }) == 2)
check('apply preserves order', questList.apply(fq, { axis = 'category', key = 'guild_faction' })[1].id == 'a')
local counts = questList.counts(fq)
check('counts addon', counts.addon.tribunal == 2 and counts.addon.morrowind == 1 and counts.addon.unknown == 1)
check('counts category', counts.category.guild_faction == 2 and counts.category.great_house == 1 and counts.category.main_quest == 1)
check('counts faction (nil excluded)', counts.faction['mages guild'] == 2 and counts.faction['fighters guild'] == 1)
check('counts faction has no nil key', (function()
    local n = 0; for _ in pairs(counts.faction) do n = n + 1 end; return n == 2
end)())

-- uiResize.apply: window resize geometry (min-size + on-screen clamping, origin-moving edges) ----------
local RZOPT = { minW = 100, minH = 80, screenW = 1000, screenH = 800 }
local function rz(dir, dx, dy, start) return uiResize.apply(dir, { x = dx, y = dy }, start, RZOPT) end
local RS = { x = 200, y = 150, w = 400, h = 300 }   -- a mid-screen window at start-of-drag

-- right edge: width only, origin fixed
check('R grows width', (function() local g = rz('r', 50, 0, RS)
    return g.w == 450 and g.x == 200 and g.y == 150 and g.h == 300 end)())
check('R clamps to minW',          rz('r', -1000, 0, RS).w == 100)
check('R clamps to screen right',  rz('r',  1000, 0, RS).w == 800)   -- screenW(1000) - x(200)
-- bottom edge: height only, origin fixed
check('B grows height',            rz('b', 0,   40, RS).h == 340)
check('B clamps to minH',          rz('b', 0,-1000, RS).h == 80)
check('B clamps to screen bottom', rz('b', 0, 1000, RS).h == 650)    -- screenH(800) - y(150)
-- left edge: width shrinks AND origin moves
check('L drag-right shrinks + moves x', (function() local g = rz('l', 50, 0, RS)
    return g.w == 350 and g.x == 250 and g.y == 150 and g.h == 300 end)())
check('L clamps x >= 0', (function() local g = rz('l', -1000, 0, RS)
    return g.x == 0 and g.w == 600 end)())     -- dX=-200 -> w=400-(-200)=600, x=0
check('L clamps w >= minW', (function() local g = rz('l', 1000, 0, RS)
    return g.w == 100 and g.x == 500 end)())   -- dX=300 -> w=100, x=500
-- top edge: height shrinks AND origin moves
check('T drag-down shrinks + moves y', (function() local g = rz('t', 0, 30, RS)
    return g.h == 270 and g.y == 180 and g.w == 400 and g.x == 200 end)())
-- corners combine both components
check('BR grows both, origin fixed', (function() local g = rz('br', 20, 20, RS)
    return g.w == 420 and g.h == 320 and g.x == 200 and g.y == 150 end)())
check('TL moves origin on both axes', (function() local g = rz('tl', 10, 10, RS)
    return g.x == 210 and g.y == 160 and g.w == 390 and g.h == 290 end)())

print('')
if failures == 0 then
    print('ALL PASS')
    os.exit(0)
else
    print(failures .. ' FAILURE(S)')
    os.exit(1)
end
