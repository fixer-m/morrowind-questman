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
local journalFeed = require('scripts.questman.journalFeed')

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

-- uiSearch.lower: Cyrillic case-folding (string.lower can't fold these) -----------------------------------
local A, a = string.char(0xD0, 0x90), string.char(0xD0, 0xB0)   -- А / а
local YA, ya = string.char(0xD0, 0xAF), string.char(0xD1, 0x8F) -- Я / я
check('lower folds Cyrillic А->а', uiSearch.lower(A) == a)
check('lower folds Cyrillic Я->я', uiSearch.lower(YA) == ya)
check('lower keeps ascii', uiSearch.lower('AbC') == 'abc')

-- uiSearch.index / search: name hits first, then text hits ranked by occurrences / sqrt(words) ---------
local function names(list)
    local out = {}
    for i, item in ipairs(list) do out[i] = item.name end
    return table.concat(out, '|')
end
local function questText(q)
    local parts = {}
    for i, e in ipairs(q.entries or {}) do parts[i] = e.text end
    return table.concat(parts, '\n')
end
local suranQuests = {
    { name = 'Suran Trade', entries = { { text = 'goods' } } },
    { name = 'Lost Ring', entries = { { text = 'go to Suran' } } },
    { name = 'Velothi Debt', entries = { { text = 'Suran, then suran again' }, { text = 'SURAN' } } },
    { name = 'Mehrunes Dagon', entries = { { text = 'shrine in the north' } } },
}
local suranIdx = uiSearch.index(suranQuests, questText)

local emptyRes = uiSearch.search(suranIdx, '')
check('search: empty query -> all by name, in input order',
      names(emptyRes.byName) == 'Suran Trade|Lost Ring|Velothi Debt|Mehrunes Dagon' and #emptyRes.byText == 0)

local suranRes = uiSearch.search(suranIdx, 'suran')
check('search: name hits keep input order', names(suranRes.byName) == 'Suran Trade')
check('search: text hits ranked by score', names(suranRes.byText) == 'Velothi Debt|Lost Ring')
check('search: a name hit is not repeated in text hits', (function()
    for _, q in ipairs(suranRes.byText) do if q.name == 'Suran Trade' then return false end end
    return true end)())

local tieQuests = {
    { name = 'First', entries = { { text = 'ald ruhn' } } },
    { name = 'Second', entries = { { text = 'ald ruhn' } } },
}
check('search: equal counts keep input order',
      names(uiSearch.search(uiSearch.index(tieQuests, questText), 'ruhn').byText) == 'First|Second')

-- score = hits / sqrt(words). The worked example from the design: a short quest all about Vivec beats the
-- long main quest, which still beats a tiny one-off mention; a passing mention in a mid-size text is last.
local function textOf(words, hits)
    return string.rep('vivec ', hits) .. string.rep('word ', words - hits)
end
local vivecQuests = {   -- input order is the reverse of the expected ranking, so sorting must do the work
    { name = 'C passing', entries = { { text = textOf(400, 1) } } },    -- 1 / 20    = 0.05
    { name = 'D tiny', entries = { { text = textOf(50, 1) } } },        -- 1 / 7.07  = 0.14
    { name = 'B main', entries = { { text = textOf(3000, 12) } } },     -- 12 / 54.8 = 0.22
    { name = 'A short', entries = { { text = textOf(60, 3) } } },       -- 3 / 7.75  = 0.39
}
check('search: score divides hits by sqrt of the word count',
      names(uiSearch.search(uiSearch.index(vivecQuests, questText), 'vivec').byText)
          == 'A short|B main|D tiny|C passing')
check('search: same hits in a longer text rank lower', names(uiSearch.search(uiSearch.index({
    { name = 'Long', entries = { { text = textOf(200, 2) } } },
    { name = 'Short', entries = { { text = textOf(20, 2) } } },
}, questText), 'vivec').byText) == 'Short|Long')

-- One floor for names AND text: a shorter query is no search yet (the whole list), so every further letter
-- only narrows the results -- they never jump up when the text search kicks in.
check('search: query under 3 chars is no search yet (whole list)', (function()
    local r = uiSearch.search(suranIdx, 'su')   -- would match a name and texts
    return names(r.byName) == 'Suran Trade|Lost Ring|Velothi Debt|Mehrunes Dagon' and #r.byText == 0 end)())
check('isActive: from 3 chars', not uiSearch.isActive('') and not uiSearch.isActive('su')
      and uiSearch.isActive('sur') and not uiSearch.isActive(nil))
check('search: 3-char query reaches text', names(uiSearch.search(suranIdx, 'sur').byText) == 'Velothi Debt|Lost Ring')

-- The threshold counts characters, not bytes: 'Су' is 2 chars (4 bytes) and must NOT reach text.
local SU = string.char(0xD0, 0xA1) .. string.char(0xD1, 0x83)                 -- "Су"
local SUR = SU .. string.char(0xD1, 0x80)                                      -- "Сур"
local ruText = { { name = 'Kolco', entries = { { text = 'в ' .. SUR .. 'ан' } } } }
local ruIdx = uiSearch.index(ruText, questText)
check('search: 2 cyrillic chars are no search yet', #uiSearch.search(ruIdx, SU).byText == 0
      and #uiSearch.search(ruIdx, SU).byName == 1 and not uiSearch.isActive(SU))
check('search: 3 cyrillic chars reach text', #uiSearch.search(ruIdx, SUR).byText == 1)
check('search: cyrillic text match is case-insensitive',
      #uiSearch.search(ruIdx, uiSearch.lower(SUR)).byText == 1)
check('search: ascii name match is case-insensitive', names(uiSearch.search(suranIdx, 'SURAN').byName) == 'Suran Trade')
local ALM = A .. string.char(0xD0, 0xBB, 0xD1, 0x8C)                            -- "Аль"
local ruNames = uiSearch.index({ { name = ALM .. 'малексия' } }, questText)     -- "Альмалексия"
check('search: cyrillic name match is case-insensitive', #uiSearch.search(ruNames, uiSearch.lower(ALM)).byName == 1
      and #uiSearch.search(ruNames, ALM).byName == 1)

check('search: text is built lazily, once per item', (function()
    local calls = 0
    local idx = uiSearch.index(suranQuests, function(q) calls = calls + 1; return questText(q) end)
    uiSearch.search(idx, 'oo')                 -- too short for text -> must not build
    if calls ~= 0 then return false end
    uiSearch.search(idx, 'suran')
    uiSearch.search(idx, 'sura')
    return calls == 3 end)())                  -- 'Suran Trade' is a name hit: its text is never needed

check('search: text cache survives re-indexing the same items', (function()
    local calls = 0
    local function textOf(q) calls = calls + 1; return questText(q) end
    uiSearch.search(uiSearch.index(suranQuests, textOf), 'suran')
    uiSearch.search(uiSearch.index(suranQuests, textOf), 'suran')   -- e.g. a list refresh on click
    return calls == 3 end)())

-- uiSearch.lessIgnoreCase: the Topics tab's optional case-insensitive order -------------------------------
local function sortedIgnoreCase(list)
    local copy = { unpack(list) }
    table.sort(copy, uiSearch.lessIgnoreCase)
    return table.concat(copy, '|')
end
check('ignore case: lowercase topics mix in alphabetically',
      sortedIgnoreCase({ 'my trade', 'Zainab', 'Balmora' }) == 'Balmora|my trade|Zainab')
local DVEMER = string.char(0xD0, 0x94) .. 'vemer'    -- "Д..." (capital De)
local APTEKA = string.char(0xD0, 0xB0) .. 'pteka'    -- "а..." (small a)
check('ignore case: cyrillic folds too', sortedIgnoreCase({ DVEMER, APTEKA }) == APTEKA .. '|' .. DVEMER)
check('ignore case: names equal but for case keep a fixed order',
      uiSearch.lessIgnoreCase('Vivec', 'vivec') and not uiSearch.lessIgnoreCase('vivec', 'Vivec'))

-- uiSearch.highlight: wrap matches in MyGUI #RRGGBB colour tags -------------------------------------------
check('highlight: wraps every match, keeping the original case',
      uiSearch.highlight('Suran is near suran.', 'SURAN', 'FFFFFF', 'CAA560')
          == '#FFFFFFSuran#CAA560 is near #FFFFFFsuran#CAA560.')
check('highlight: no match -> text unchanged',
      uiSearch.highlight('Balmora', 'suran', 'FFFFFF', 'CAA560') == 'Balmora')
check('highlight: query under 3 chars -> text unchanged',
      uiSearch.highlight('Suran', 'su', 'FFFFFF', 'CAA560') == 'Suran')
check('highlight: empty / nil query -> text unchanged',
      uiSearch.highlight('Suran', '', 'FFFFFF', 'CAA560') == 'Suran'
          and uiSearch.highlight('Suran', nil, 'FFFFFF', 'CAA560') == 'Suran')
check('highlight: cyrillic match keeps the original case', (function()
    local text = 'в ' .. SUR .. 'ан'                                   -- "в Суран"
    local out = uiSearch.highlight(text, uiSearch.lower(SUR), 'FFFFFF', 'CAA560')
    return out == 'в #FFFFFF' .. SUR .. '#CAA560ан' end)())
check('highlight: a literal # is escaped once tags are added',
      uiSearch.highlight('Suran #1', 'suran', 'FFFFFF', 'CAA560') == '#FFFFFFSuran#CAA560 ##1')

-- journalFeed.rows: the Journal tab's newest-first feed (day headers, quest labels, mode filter) ------------
-- A compact "kind:text" dump of the rows: day headers by day number, labels by quest id (or '-' for a
-- non-quest record), entry texts as-is.
local function feedDump(rows)
    local out = {}
    for i, r in ipairs(rows) do
        if r.kind == 'day' then out[i] = 'day:' .. tostring(r.entry.day)
        elseif r.kind == 'label' then out[i] = 'label:' .. (r.entry.questId or '-')
        else out[i] = 'text:' .. r.entry.text end
    end
    return table.concat(out, ' ')
end
local feedEntries = {   -- oldest -> newest, as the journal stores them
    { text = 'a1', day = 1, questId = 'A' },
    { text = 'a2', day = 1, questId = 'A' },
    { text = 'r1', day = 1, record = true },
    { text = 'b1', day = 2, questId = 'B' },
    { text = 'a3', day = 2, questId = 'A' },
    { text = 'a4', day = 2, questId = 'A' },
}
local allFeed = journalFeed.rows(feedEntries, 'all')
check('feed: newest first, a header per day, a label per quest run',
      feedDump(allFeed.rows) ==
      'day:2 label:A text:a4 text:a3 label:B text:b1 day:1 label:- text:r1 label:A text:a2 text:a1')
check('feed: count = the mode total, nothing more to load', allFeed.count == 6 and allFeed.more == false)
check('feed: a new day repeats the label of a continuing quest', feedDump(journalFeed.rows({
    { text = 'a1', day = 1, questId = 'A' },
    { text = 'a2', day = 2, questId = 'A' },
}, 'all').rows) == 'day:2 label:A text:a2 day:1 label:A text:a1')
local recFeed = journalFeed.rows(feedEntries, 'records')
check('feed: records mode keeps only non-quest entries, without labels',
      feedDump(recFeed.rows) == 'day:1 text:r1' and recFeed.count == 1)
check('feed: an undated entry gets no header and joins the run above', feedDump(journalFeed.rows({
    { text = 'x', questId = 'A' },
    { text = 'a1', day = 1, questId = 'A' },
}, 'all').rows) == 'day:1 label:A text:a1 text:x')
check('feed: empty journal -> no rows', #journalFeed.rows({}, 'all').rows == 0)

-- Lazy loading: `limit` caps the shown (newest) entries; count stays the mode's total, `more` says if
-- older entries are left to load.
local limited = journalFeed.rows(feedEntries, 'all', 3)
check('feed: limit keeps only the newest entries',
      feedDump(limited.rows) == 'day:2 label:A text:a4 text:a3 label:B text:b1')
check('feed: limit keeps the total count and reports more', limited.count == 6 and limited.more == true)
check('feed: no more once the limit covers everything', journalFeed.rows(feedEntries, 'all', 6).more == false
      and journalFeed.rows(feedEntries, 'all').more == false)
check('feed: limit counts records-mode entries only',
      feedDump(journalFeed.rows(feedEntries, 'records', 1).rows) == 'day:1 text:r1')

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

-- questList.pinnedFirst: the Topics list's bookmarks float up, both groups keep their order --------------
local function ids(list)
    local out = {}
    for i, t in ipairs(list) do out[i] = t.id end
    return table.concat(out, '|')
end
local topicsToPin = { { id = 'a' }, { id = 'b', pinned = true }, { id = 'c' }, { id = 'd', pinned = true } }
check('pinnedFirst: pinned first, each group in input order', ids(questList.pinnedFirst(topicsToPin)) == 'b|d|a|c')
check('pinnedFirst: input not mutated', ids(topicsToPin) == 'a|b|c|d')
check('pinnedFirst: nothing pinned -> same order', ids(questList.pinnedFirst({ { id = 'x' }, { id = 'y' } })) == 'x|y')

-- questList.sortByName: pinned first, active before completed, then A-Z ignoring case (Cyrillic too) --------
local toName = {
    { id = 'b', name = 'beta' },
    { id = 'P', name = 'zeta', pinned = true },
    { id = 'D', name = 'Alpha', completed = true },
    { id = 'A', name = 'Alpha' },
    { id = 'ya', name = 'Яблоко' },
    { id = 'ar', name = 'арбуз' },
}
check('sortByName: pinned, active A-Z, completed last', ids(questList.sortByName(toName)) == 'P|A|b|ar|ya|D')
check('sortByName: input not mutated', toName[1].id == 'b')

-- questList.groupByFaction: pinned group, factions A-Z by label, no-faction last; groups keep input order -----
local toGroup = {
    { id = 'p1', pinned = true, factionId = 'mg', faction = 'Mages Guild' },
    { id = 'm1', factionId = 'mg', faction = 'Mages Guild' },
    { id = 'n1' },
    { id = 'f1', factionId = 'fg', faction = 'fighters guild' },
    { id = 'm2', factionId = 'mg', faction = 'Mages Guild' },
}
local function groupDump(groups)
    local out = {}
    for i, g in ipairs(groups) do out[i] = tostring(g.key) .. ':' .. ids(g.quests) end
    return table.concat(out, ' ')
end
check('groupByFaction: order + members',
      groupDump(questList.groupByFaction(toGroup)) == questList.GROUP_PINNED .. ':p1 fg:f1 mg:m1|m2 '
          .. questList.GROUP_NONE .. ':n1')
check('groupByFaction: faction label carried', questList.groupByFaction(toGroup)[2].label == 'fighters guild')
check('groupByFaction: empty groups omitted', groupDump(questList.groupByFaction({ { id = 'n1' } }))
      == questList.GROUP_NONE .. ':n1')
check('groupByFaction: empty input -> no groups', #questList.groupByFaction({}) == 0)

-- questList.groupByFactionOrCategory: faction if any, else category; Main Quest, factions, categories (Stats
-- order: alphabetical, Misc then Unknown last) -------------------------------------------------------------
local toMix = {
    { id = 'u1' },                                                    -- no category -> unknown
    { id = 'x1', category = 'misc' },
    { id = 'd1', category = 'daedric' },
    { id = 'm1', category = 'guild_faction', factionId = 'mg', faction = 'Mages Guild' },
    { id = 'q1', category = 'main_quest' },
    { id = 'v1', category = 'vampire' },
    { id = 'd2', category = 'daedric' },
    { id = 'p1', category = 'daedric', pinned = true },
}
local function catLabel(key) return ({ daedric = 'Daedric', vampire = 'Vampire', misc = 'Misc', unknown = 'Unknown',
                                       main_quest = 'Main' })[key] end
local mixed = questList.groupByFactionOrCategory(toMix, catLabel)
local function mixDump(groups)
    local out = {}
    for i, g in ipairs(groups) do out[i] = (g.label or g.key) .. ':' .. ids(g.quests) end
    return table.concat(out, ' ')
end
check('groupByFactionOrCategory: order + members', mixDump(mixed)
      == questList.GROUP_PINNED .. ':p1 Main:q1 Mages Guild:m1 Daedric:d1|d2 Vampire:v1 Misc:x1 Unknown:u1')
toMix[#toMix + 1] = { id = 'g1', category = 'guild_faction', factionId = 'fg', faction = 'Fighters Guild' }
catLabel = function(key) return ({ daedric = 'Daedric', vampire = 'Vampire', misc = 'Misc', unknown = 'Unknown',
                                   main_quest = 'Main', guild_faction = 'Guilds' })[key] end
check('groupByCategory: categories only, Stats order', mixDump(questList.groupByCategory(toMix, catLabel))
      == questList.GROUP_PINNED .. ':p1 Main:q1 Daedric:d1|d2 Guilds:m1|g1 Vampire:v1 Misc:x1 Unknown:u1')

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
