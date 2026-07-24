-- questman: menu UI (PLAYER context). A draggable, resizable window with three tabs (Quests / Topics / Stats): a searchable,
-- scrollable list on the left and the selected item's detail on the right. Refresh mutates named content nodes + element:update()
-- (the omw/settings pattern); scrolling is hand-rolled clip+offset. Consumes the QuestmanData interface (questProvider.lua).

local ui = require('openmw.ui')
local util = require('openmw.util')
local input = require('openmw.input')
local storage = require('openmw.storage')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local async = require('openmw.async')

local components = require('scripts.questman.uiComponents')
local uiSearch = require('scripts.questman.uiSearch')
local uiScroll = require('scripts.questman.uiScroll')
local uiResize = require('scripts.questman.uiResize')
local questList = require('scripts.questman.questList')

local v2 = util.vector2
local l10n = core.l10n('Questman')
local settings = storage.playerSection('Settings/Questman/Options')
-- persistent (on-disk, cross-save) window geometry
local windowStore = storage.playerSection('Questman/Window')

-- MANUAL CONFIG -- for players who CAN'T open the in-game Settings page (e.g. console/handheld ports with
-- no keyboard, where the stored setting can't be changed). Leave an entry nil to use the normal in-game
-- Settings; set a value to FORCE it, ignoring whatever the Settings page saved. Read once at load, so
-- restart OpenMW after editing.
local FORCE_OVERRIDE_JOURNAL = nil   -- true -> opening the vanilla Journal opens questman instead (reuse the
                                     --         control you already use for the journal; easiest with no keyboard)
local FORCE_OPEN_BUTTON      = nil   -- a controller button id (>= 0) that opens/closes the menu
local FORCE_OPEN_KEY         = nil   -- a keyboard key that opens the menu, e.g. input.KEY.J

-- A manual-config value wins when set (non-nil); otherwise fall back to the in-game Settings value.
local function forced(override, stored)
    if override ~= nil then return override end
    return stored
end

-- `[questman]` trace lines on key steps (open/close, selection, geometry), gated by the "Debug" setting.
local function dbg(...)
    if settings:get('Debug') ~= false then print('[questman]', ...) end
end

-- ---- layout constants ------------------------------------------------------
local PAD = 8
local TITLE_H = 20
local TAB_H = 28     -- page-tab band (Quests / Stats), under the title
local TAB_GAP = 4    -- spacing between adjacent page tabs (tabs sit flush with the left edge)
local SEARCH_H = 24   -- search row height (icon is 22, so this is the practical minimum)
local BAR_W = 16     -- scrollbar width
local ARROW_H = 19   -- arrow-zone height = BAR_W + scrollbar GAP(3), so the arrow box is square (see
                     -- uiComponents M.scrollbar); the thumb travels between the two zones [ARROW_H, h-ARROW_H]
local ROW_H = 28
-- Tightened ~one-text-line row pitch (no inter-row gap): the topic list (long 877+ index) and the
-- "Related topics" link rows on both detail panes. Default font kept; 18px ≈ the line height, which is
-- the floor before glyphs start to clip.
local TPC_ROW_H = 18
local VLIST_BUFFER = 4   -- virtualized lists (quests + topics): rows rendered above/below the viewport
local STATUS_H = 18      -- slim status strip under the list (holds the shown/total counter)
local ICON_SZ = 24       -- quest icon AND search icon size (must match, so they align vertically)
local ICON_MARGIN = 2    -- left margin from the pane border to the icon
local FOOTER_H = 36      -- bottom button bar height (fits a standard button + margins)
local FOOTER_GAP = 6     -- Close button inset from the footer's right edge (≈ its top/bottom gap)
-- Fraction of the inner width taken by the LEFT (list) pane, per page. Defaults mirror the settings
-- (Quest/Topic list width %); loaded from settings on open, mutated live by the divider drag, saved back.
local questListFrac, topicListFrac = 0.4, 0.3
local MIN_W, MIN_H = 520, 320
local DETAIL_GAP = 4    -- gap before the detail pane; smaller than PAD so detail text sits a few px further left
local DETAIL_DY = 2     -- detail content nudged down this many px
local ENTRY_GAP = 6     -- vertical gap between numbered journal entries in the quest detail
local LINE_ROW = 20     -- content-height allowance for a SINGLE-line detail row (category/giver/subtitle);
                        -- ROW_H(26) is the list-row height and over-reserves here -> spurious scrollbar
local SCROLL_SLACK = 16 -- detail/topic panes: hide the scrollbar unless content overflows by more than this
                        -- (their height is estimated; absorbs a few px of rounding so a fitting quest = no bar)
local WHEEL_STEP = ROW_H * 2

-- Row markers shown before the name. A hidden quest shows the crossed-eye; else a pinned quest shows
-- the star; otherwise no marker (title stays flush against the quest icon).
local PIN_ICON = 'Icons/questman/ui_star.dds'
local HIDDEN_ICON = 'Icons/questman/ui_hidden.dds'

-- Filtering: the funnel REPLACES the search magnifier (same 22px slot). Clicking it toggles a thin
-- FilterDropDown combo row under the search box; clicking THAT opens the options as a floating popover
-- (a separate Element on an interactive layer above the window) that overlays the list. See §filter.
local FILTER_ICON = 'Icons/questman/ui_filter.dds'
local FILTER_ARROW = 'textures/omw_menu_scroll_down.dds'   -- ⇓ on the combo box (the font has no chevron glyph)
local COMBO_H = SEARCH_H      -- the FilterDropDown combo-box row height = the search box height (match)
local FILTER_POPUP_H = 220    -- max height of the floating options popover (it scrolls past this)
local FILTER_ROW_H = 17       -- option row height in the popover (tight)
local FILTER_HDR_H = 19       -- section-header row height in the popover
local STATUS_EYE = 12         -- small crossed-eye icon on the status strip (smaller than the 14px row marker)
local POPUP_LAYER = 'QuestmanFilterPopup'   -- interactive layer (above 'Windows') hosting the options popover
local DIV = 2                 -- approx height of a horizontalLine divider (for popover y-placement math)

-- Stats page metrics (compact rows; numbers align in a fixed column near the labels). Tunable.
local STAT_ROW = 28          -- stat row height. Needs >=2px margin around the ICON_SZ=22 row icon: at only
                             -- 24 (1px) a non-integer GUI scale rounds the margin away and clips the icon
                             -- (seen on the English install, whose scale differs from the Russian one)
local STAT_ICON_GAP = 4      -- gap between a row's icon and its label
local STAT_ICON_ZOOM = 64    -- Stats-page only: hovering a row icon shows it at its NATIVE 64px size (crisp
                            -- 1:1 regardless of GUI scale). This is the icons' real resolution — the max sharp size.
local STAT_HEADER_H = 24     -- section header row height
local STAT_VALUE_W = 85      -- right-aligned "N / N" column, tuned snug around a 4-digit "9999 / 9999"
                            -- (heavily modded totals). MW's font is PROPORTIONAL and digits are wide, and the
                            -- box clips, so don't go below what "9999 / 9999" needs or a leading digit gets cut.
local STAT_LABEL_W = 203     -- label column, tuned tight to the longest localized name ("Восточная Имп.
                            -- Кампания:") so the numbers sit right after it. STATIC — fixed column width (below),
                            -- so labels + numbers stay put regardless of window size. A name that just clips
                            -- still shows in full on hover (tooltip); nudge this up if a real name overflows.
local STAT_CHECK_W = 22      -- reserve at a row's right edge for the ✓ (small gap + 14px tick + a hair of pad)
local STAT_COL_GAP = 6       -- horizontal gap between the two static stat columns
local STAT_TICK = 'Icons/questman/ui_check_mark.dds'   -- main-quest-finished checkmark
local STAT_ICON_ACTIVE = 'Icons/questman/ui_in_progress.dds'   -- Overview "Active" row icon
local STAT_ICON_DONE   = 'Icons/questman/ui_completed.dds'     -- Overview "Completed" row icon

-- ---- state -----------------------------------------------------------------
-- Lifecycle-owned state — driven only by the open / close / UI-modes section far below (search
-- "lifecycle: open / close"): the live Element, the window geometry, and the two mode flags.
local menu = nil           -- the ui Element while open
local geom = { x = 100, y = 100, w = 900, h = 600 }
local diagnosticsLogged = false   -- first-open diagnostics dump fires once per session
local overrideMenuOpen = false    -- true when opened via the Journal override: the engine owns the
                                  -- 'Journal' UI mode, so teardown goes through the registerWindow hideFn
                                  -- (not our own removeMode('Interface'))
local selectedId = nil
local currentOrder = {}     -- the quests as currently displayed (filtered+sorted), for keyboard nav
local lastQuests = nil      -- the raw (unfiltered) getQuests() list from the last quest-page build; reused
                            -- by the deferred first-open diagnostics so they don't scan the save a 2nd time
local listTotal = 0         -- total real quests (before the completed/search filters) for the footer counter
local query = ''
local listOffset, detailOffset = 0, 0
local listContentH, detailContentH = 0, 0
local statsOffset, statsContentH = 0, 0     -- stats page: single scrollable column (overview/addons/categories/factions)
local topicLOffset, topicLContentH = 0, 0   -- Topics page: LEFT topic list
local topicROffset, topicRContentH = 0, 0   -- Topics page: RIGHT topic detail (conversation lines)
local topicActive = 'left'                  -- which topics panel the wheel scrolls
local selectedTopic = nil                   -- selected topic id
local topicQuery = ''                        -- search text for the Topics-page list
local topicListCache                         -- current filtered view of the topic list (search results)

-- Records page state AND view functions live in ONE table (keeps ui.lua's main chunk under Lua 5.1's
-- 200-local cap; structurally a near-clone of the Topics page). Fields assigned below.
local records = {
    lOffset = 0, lContentH = 0,   -- LEFT record list scroll
    rOffset = 0, rContentH = 0,   -- RIGHT record detail scroll
    active = 'left',              -- which panel the wheel scrolls
    selected = nil,               -- selected record id
    query = '',                   -- search text
    listCache = nil,              -- filtered list view
    listFrac = 0.3,               -- LEFT pane width fraction (loaded from RecordListWidthPercent on open)
    -- OpenMW's built-in Tamriel calendar context (month1..month12), localized per game language -- the same
    -- source the rest/journal UIs use. Records date-stamp entries from it; we hardcode no month names.
    calendar = core.l10n('Calendar'),
}

-- Full sorted topic list. The heavy journal scan is cached in the DATA layer (getTopics, invalidated per
-- open), so this is just a thin pass-through — every caller shares the one cached list, re-read fresh on the
-- next open. footerButtons and the Topics page filter from it rather than re-scanning per keystroke.
local function allTopics()
    return I.QuestmanData.getTopics()
end
-- Full record list (non-quest journal records), newest-activity first. Thin pass-through over the cached
-- DATA-layer scan, like allTopics.
function records.all()
    return I.QuestmanData.getRecords()
end
local activePane = 'list'
local activePage = 'quests'   -- 'quests' | 'topics' | 'stats' — the page-tab selection
local showAll = false         -- footer toggle: off = active & non-hidden only; on = also completed + hidden
local hiddenCount = 0         -- how many real quests are hidden (for the "Hidden: X" strip label)
local filterRowOn = false     -- the FilterDropDown combo row is shown (toggled by the funnel); persists across tabs / reopen
local selectedFilter = nil    -- active filter { axis, key, label } or nil; cleared when the funnel toggles the row off, else persists across tabs / reopen
local dividerDrag = false     -- true while dragging the list/detail divider: applySizes resizes in place (no panes rebuild) so the divider handle keeps mouse capture
local filterOffset, filterContentH = 0, 0   -- options-popover scroll state
local popupEl = nil           -- the floating options popover (a separate top-level Element), nil when closed
local popupViewH = 0          -- the popover's viewport height (for scroll clamping)

-- let button hover-recolouring update the menu element. update() can throw "DelayedAction is not
-- allowed to create another DelayedAction" when a focusLoss fires during teardown (e.g. clicking
-- Close) — harmless there, so swallow it.
components.setRefresh(function()
    if menu then pcall(menu.update, menu) end
end)

-- forward declarations
local refreshList, refreshDetail, applyListOffset, applyDetailOffset, applySizes, refreshFooter, savePos, saveSize, applyStatsOffset
local applyTopicLOffset, applyTopicROffset, rebuildTopics, selectTopic, refreshTopicList, openTopic
-- scrollPane + logicalScreen are declared here so functions defined earlier can use them.
local scrollPane, applyFilterOffset, rebuildQuestPane, selectFilter, logicalScreen
local goToPage   -- (page) -> switch tab; used by the clickable Stats rows (defined earlier than goToPage)
local jumpToFilter   -- (axis, key, label) -> filter the Quests tab by this group; used by Stats rows and detail lines
local buildComboRow, buildFilterPopup, openFilterPopup, closeFilterPopup, toggleFilterPopup, toggleFilterRow

-- Interactive layer (above 'Windows') for the options popover, so it floats over the menu and is
-- clickable. Created once; insertAfter is idempotent-safe behind the indexOf guard (survives reloadlua).
pcall(function()
    if ui.layers.indexOf(POPUP_LAYER) == nil then
        ui.layers.insertAfter('Windows', POPUP_LAYER, { interactive = true })
    end
end)

-- ---- sizing ----------------------------------------------------------------
local function sizes()
    local innerW = geom.w - 2 * PAD
    local innerH = geom.h - 2 * PAD
    local contentH = innerH - TITLE_H - TAB_H - FOOTER_H - 6   -- minus 3 dividers (~2 each)
    local listW = math.max(160, math.floor(innerW * questListFrac))
    -- divider now sticks to the scrollbar (no gap before it); a small gap remains before the detail.
    local detailW = innerW - listW - DETAIL_GAP - 2  -- one gap + the vertical separator line
    -- the FilterDropDown combo row (when shown) pushes the list down by one row height
    local comboH = filterRowOn and COMBO_H or 0
    return {
        innerW = innerW, innerH = innerH, contentH = contentH,
        listW = listW, detailW = detailW,
        comboH = comboH,
        listViewH = contentH - SEARCH_H - STATUS_H - comboH,   -- list sticks under search (+combo); reserve status strip
        detailViewH = contentH,
        listVpW = listW - BAR_W,
        detailVpW = detailW - BAR_W,
    }
end

-- Walk named nodes from the root: nodeByPath('main','panes','left', ...) -> layout table.
-- A ui.content Map THROWS on an unknown name key (not nil), so look up via pcall and treat a miss as
-- nil — callers all guard `if node then ...`, so a transient/missing node degrades to a no-op, not a crash.
local function nodeByPath(...)
    if not menu then return nil end
    local c = menu.layout.content
    local node
    for _, name in ipairs({ ... }) do
        if not c then return nil end
        local ok, found = pcall(function() return c[name] end)
        if not ok or not found then return nil end
        node = found
        c = node.content
    end
    return node
end

-- ---- layout node addresses --------------------------------------------------
-- Every node the refresh / resize / scroll code reaches into, its path from the root named ONCE here — one
-- map of the live tree's addressable anchors, instead of the same deep string literal repeated at each
-- accessor. Rename or renest a node in its builder and you update its path here (the single place they
-- live); the trailing name in each path must match the `name=` the builder sets. node() splats an entry;
-- the apply<X>Offset configs and applySizes reference these directly.
local PATH = {
    main       = { 'main' },
    titlebar   = { 'main', 'titlebar' },
    tabRow     = { 'main', 'tabRow' },
    panes      = { 'main', 'panes' },
    bottomBar  = { 'main', 'bottomBar' },
    footer     = { 'main', 'bottomBar', 'footerButtons' },
    -- Quests page: left column (search + list + status) and right column (detail)
    left        = { 'main', 'panes', 'left' },
    leftBody    = { 'main', 'panes', 'left', 'leftBody' },
    searchRow   = { 'main', 'panes', 'left', 'searchRow' },
    listStatus  = { 'main', 'panes', 'left', 'listStatus' },
    listVp      = { 'main', 'panes', 'left', 'leftBody', 'listVp' },
    listInner   = { 'main', 'panes', 'left', 'leftBody', 'listVp', 'listInner' },
    listBar     = { 'main', 'panes', 'left', 'leftBody', 'listBar' },
    listThumb   = { 'main', 'panes', 'left', 'leftBody', 'listBar', 'thumb' },
    listCounter = { 'main', 'panes', 'left', 'listStatus', 'listCounter' },
    statusLeft  = { 'main', 'panes', 'left', 'listStatus', 'statusLeft' },
    detail      = { 'main', 'panes', 'detail' },
    detailVp    = { 'main', 'panes', 'detail', 'detailVp' },
    detailInner = { 'main', 'panes', 'detail', 'detailVp', 'detailInner' },
    detailBar   = { 'main', 'panes', 'detail', 'detailBar' },
    detailThumb = { 'main', 'panes', 'detail', 'detailBar', 'thumb' },
    -- Stats page: one scroll column holding both stat columns side by side
    statsInner = { 'main', 'panes', 'statsPage', 'statsCol', 'statsColVp', 'statsColInner' },
    statsThumb = { 'main', 'panes', 'statsPage', 'statsCol', 'statsColBar', 'thumb' },
    -- Topics page: left list + right detail
    topicLeftCol     = { 'main', 'panes', 'topicsPage', 'topicLeftCol' },
    topicDetail      = { 'main', 'panes', 'topicsPage', 'topicDetail' },
    topicListInner   = { 'main', 'panes', 'topicsPage', 'topicLeftCol', 'topicList', 'topicListVp', 'topicListInner' },
    topicListBar     = { 'main', 'panes', 'topicsPage', 'topicLeftCol', 'topicList', 'topicListBar' },
    topicListThumb   = { 'main', 'panes', 'topicsPage', 'topicLeftCol', 'topicList', 'topicListBar', 'thumb' },
    topicCounter     = { 'main', 'panes', 'topicsPage', 'topicLeftCol', 'topicStatus', 'topicCounter' },
    topicDetailInner = { 'main', 'panes', 'topicsPage', 'topicDetail', 'topicDetailVp', 'topicDetailInner' },
    topicDetailThumb = { 'main', 'panes', 'topicsPage', 'topicDetail', 'topicDetailBar', 'thumb' },
    -- Records page: left list + right detail (mirror of the Topics page)
    recordLeftCol     = { 'main', 'panes', 'recordsPage', 'recordLeftCol' },
    recordDetail      = { 'main', 'panes', 'recordsPage', 'recordDetail' },
    recordListInner   = { 'main', 'panes', 'recordsPage', 'recordLeftCol', 'recordList', 'recordListVp', 'recordListInner' },
    recordListBar     = { 'main', 'panes', 'recordsPage', 'recordLeftCol', 'recordList', 'recordListBar' },
    recordListThumb   = { 'main', 'panes', 'recordsPage', 'recordLeftCol', 'recordList', 'recordListBar', 'thumb' },
    recordCounter     = { 'main', 'panes', 'recordsPage', 'recordLeftCol', 'recordStatus', 'recordCounter' },
    recordDetailInner = { 'main', 'panes', 'recordsPage', 'recordDetail', 'recordDetailVp', 'recordDetailInner' },
    recordDetailThumb = { 'main', 'panes', 'recordsPage', 'recordDetail', 'recordDetailBar', 'thumb' },
    -- resize strips: direct children of the root (siblings of the 'frame' box)
    rzL = { 'rzL' }, rzR = { 'rzR' }, rzT = { 'rzT' }, rzB = { 'rzB' },
    rzTL = { 'rzTL' }, rzTR = { 'rzTR' }, rzBL = { 'rzBL' }, rzBR = { 'rzBR' },
}
-- Window chrome lives inside the 'frame' box (child of the plain-Widget root) so the resize strips can sit
-- on the true outer edge; prefix every content path with 'frame'. The rz* strips stay at the root level.
for pathKey, p in pairs(PATH) do
    if pathKey:sub(1, 2) ~= 'rz' then table.insert(p, 1, 'frame') end
end
-- The filter popover is a separate element (popupEl); its nodes are reached with popNode, not node.
local POP = {
    filterInner = { 'filterPop', 'filterDD', 'filterDDVp', 'filterDDInner' },
    filterThumb = { 'filterPop', 'filterDD', 'filterDDBar', 'thumb' },
}

-- Resolve a PATH entry to its live node (sugar over nodeByPath). Callers still guard `if n then` — a nil
-- means the node isn't in the current tree (e.g. a different page is active), a valid no-op.
local function node(path)
    return nodeByPath(unpack(path))
end

-- ---- left pane: search + scrollable quest list -----------------------------
local function onSelect(quest)
    -- Ctrl+click toggles the pin (keep the current selection); a plain click selects.
    if input.isCtrlPressed() then
        I.QuestmanData.togglePin(quest.id)   -- logs the resulting state in questProvider.togglePin
        refreshList()   -- reorder + redraw the pin markers
        return
    end
    selectedId = quest.id
    I.QuestmanData.setLastViewed(quest.id)
    detailOffset = 0
    refreshList()   -- update highlight
    local t0 = core.getRealTime()
    refreshDetail()
    dbg(('Selected quest: %s, stage %s (%.0f ms)')
        :format(quest.id, tostring(quest.stage or 0), (core.getRealTime() - t0) * 1000))
end

-- One quest list row: icon + name + pin/hidden markers, highlighted when selected. Clicking selects.
local function questRowNode(q)
    local markers = {}                                  -- pinned first, then hidden (both can show)
    if q.pinned then markers[#markers + 1] = PIN_ICON end
    if q.hidden then markers[#markers + 1] = HIDDEN_ICON end
    return components.questRow(q, q.id == selectedId, onSelect, markers, ROW_H, ICON_SZ)
end

-- VIRTUALIZED list body: render only the rows in the viewport (+VLIST_BUFFER), preceded by one spacer the
-- height of the rows above. Quest rows are heavy (icon + markers), so this keeps the widget count flat as
-- the journal grows. `quests` is the displayed (filtered+sorted) order; `listContentH` (set by the caller)
-- stays the FULL height so the scrollbar is correct. Mirrors buildTopicSlice.
local function buildQuestSlice(quests, offset, viewH)
    local n = #quests
    local firstVisible = math.floor((offset or 0) / ROW_H) + 1
    local first = math.max(1, firstVisible - VLIST_BUFFER)
    local last = math.min(n, firstVisible + math.ceil(viewH / ROW_H) + VLIST_BUFFER)
    local nodes = {}
    if first > 1 then nodes[#nodes + 1] = { props = { size = v2(0, (first - 1) * ROW_H) } } end
    for i = first, last do nodes[#nodes + 1] = questRowNode(quests[i]) end
    return nodes
end

-- Cached { node, h } item lists for the two VARIABLE-height panes (quest detail, topic detail), set by
-- their builders and re-sliced on scroll by buildVarSlice. Layout tables are read-only descriptors the
-- engine never writes back to (element.cpp setLayout only stores a ref + reads props), so caching and
-- reusing them across slices is safe.
local vitems = { detail = {}, topicR = {}, recordR = {} }

-- VIRTUALIZED variable-height body (analog of buildQuestSlice for the uniform lists). `items` is an array
-- of { node = layout, h = pixel height }. Render only the items intersecting [offset, offset+viewH] (+120px
-- buffer), preceded by ONE spacer as tall as everything above the first rendered item — so the inner Flex
-- still positions the visible items at the right y and the scrollbar (driven by the FULL contentH) stays
-- correct. Without this, a generic topic's 60+ conversation paragraphs are all live widgets that the engine
-- re-lays-out every frame (measured: ~90 ms/frame), even the ~90% scrolled off-screen.
local function buildVarSlice(items, offset, viewH)
    local top = (offset or 0) - 120
    local bottom = (offset or 0) + viewH + 120
    local nodes, y, firstY = {}, 0, nil
    for _, it in ipairs(items) do
        if y + it.h > top and y < bottom then
            if not firstY then firstY = y end
            nodes[#nodes + 1] = it.node
        end
        y = y + it.h
    end
    if firstY and firstY > 0 then table.insert(nodes, 1, { props = { size = v2(0, firstY) } }) end
    return nodes
end

local function buildRows(s)
    local quests = I.QuestmanData.getQuests()
    lastQuests = quests   -- retain the raw list (before filtering) for the deferred first-open diagnostics
    quests = questList.apply(quests, selectedFilter)   -- category filter defines the current scope
    listTotal = #quests         -- denominator = the filtered scope, before completed/hidden/search
    hiddenCount = 0
    for _, q in ipairs(quests) do if q.hidden then hiddenCount = hiddenCount + 1 end end
    if not showAll then   -- default: drop hidden (always) and completed (unless pinned)
        local vis = {}
        for _, q in ipairs(quests) do
            if not q.hidden and ((not q.completed) or q.pinned) then vis[#vis + 1] = q end
        end
        quests = vis
    end
    -- v1: search by quest NAME only (entry-text/fuzzy search is a later weighted feature).
    quests = uiSearch.filter(questList.sortDefault(quests), query, { searchEntries = false })
    currentOrder = quests   -- displayed order: drives keyboard nav, the counter, AND the scroll slices
    listContentH = #currentOrder * ROW_H                 -- FULL height (drives the scrollbar), not the slice
    listOffset = uiScroll.clamp(listOffset, listContentH, s.listViewH)
    return buildQuestSlice(currentOrder, listOffset, s.listViewH)
end

local function listThumb(s)
    local trackH = s.listViewH - 2 * ARROW_H   -- thumb travels between the arrows
    local function step(d)
        listOffset = uiScroll.clamp(listOffset + d, listContentH, s.listViewH)
        applyListOffset()
    end
    return components.scrollbar {
        width = BAR_W, height = s.listViewH, arrowH = ARROW_H,
        thumb = uiScroll.thumb(listContentH, s.listViewH, trackH, listOffset),
        onDrag = function(dy) step(dy * (listContentH / math.max(1, trackH))) end,
        onStepUp = function() step(-WHEEL_STEP) end,
        onStepDown = function() step(WHEEL_STEP) end,
    }
end

-- Status-strip LEFT group: a small crossed-eye + hidden count, only when >0 (empty otherwise). The
-- active filter is shown by the combo row + funnel shade, NOT here, so the strip stays uncluttered.
local function statusLeftNodes()
    local nodes = {}
    if hiddenCount > 0 then
        nodes[#nodes + 1] = { type = ui.TYPE.Image,   -- vertically centered by the statusLeft Flex's arrange
            props = { size = v2(STATUS_EYE, STATUS_EYE), resource = ui.texture { path = HIDDEN_ICON } } }
        nodes[#nodes + 1] = { props = { size = v2(3, 0) } }
        nodes[#nodes + 1] = { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
            props = { text = tostring(hiddenCount), textColor = components.GRAY, textSize = 14 } }
    end
    return nodes
end

local function buildLeft(s)
    local rows = buildRows(s)   -- MUST run before listThumb: it sets listContentH (the thumb size input)
    local listBar = listThumb(s)
    listBar.name = 'listBar'

    -- Bordered search box. Keep a ref to the input layout so the textChanged handler can write
    -- its text back; otherwise menu:update() re-syncs the field to the stale layout and blanks it
    -- (the "typed text invisible / cursor stuck at 0" bug).
    -- Placeholder is implemented as the input's OWN text (greyed) when empty+unfocused — no overlay
    -- widget (an overlay intercepted clicks and broke the field). It's cleared on focus, restored on
    -- blur-while-empty, and never leaks into `query`.
    local PH = l10n('search_placeholder')
    local searchInput
    searchInput = {
        name = 'searchInput',
        template = I.MWUI.templates.textEditLine,
        -- fill the box width (the box `size` is ignored — Container autosizes — so we grow the box
        -- instead and stretch the input to it with relativeSize)
        props = {
            text = (query == '') and PH or query,
            textColor = (query == '') and components.GRAY or components.WHITE,
            relativeSize = v2(1, 0), size = v2(-12, 0), position = v2(6, 0),
            relativePosition = v2(0, 0.5), anchor = v2(0, 0.5),
        },
        events = {
            textChanged = async:callback(function(text)
                query = text
                listOffset = 0
                searchInput.props.text = text
                searchInput.props.textColor = components.WHITE
                refreshList()
            end),
            focusGain = async:callback(function()
                if query == '' then   -- clear the placeholder so the user types into an empty field
                    searchInput.props.text = ''
                    searchInput.props.textColor = components.WHITE
                    if menu then pcall(menu.update, menu) end
                end
            end),
            focusLoss = async:callback(function()
                if query == '' then   -- restore the greyed placeholder
                    searchInput.props.text = PH
                    searchInput.props.textColor = components.GRAY
                    if menu then pcall(menu.update, menu) end
                end
            end),
        },
    }
    -- Plain Widget (NOT the box template): the box is a Container that autosizes, and with grow + a
    -- relativeSize input it collapsed to nothing. A fixed-size grow Widget + manual border lines fills
    -- the row reliably; the input relativeSizes to it without a circular dependency.
    local searchBox = {
        name = 'search',
        type = ui.TYPE.Widget,
        props = { size = v2(0, SEARCH_H) },
        external = { grow = 1 },   -- fill the rest of the search row -> right border reaches the scrollbar
        content = components.framed { searchInput },
    }

    -- Funnel button: a bordered frame (same 1px lines + height as the search box) with a smaller centered
    -- icon, so it reads as a clickable button. Click toggles the combo row; the icon shade signals filter
    -- state (bright = filter active, mid = row open, dim = idle).
    local funnelBtn = {
        type = ui.TYPE.Widget,
        props = { size = v2(ICON_SZ, SEARCH_H) },
        events = { mouseClick = async:callback(function() toggleFilterRow() end) },
        content = components.framed {   -- 8-piece directional frame (matches scrollbar boxes)
            { type = ui.TYPE.Image,
              props = { size = v2(14, 14), resource = ui.texture { path = FILTER_ICON },
                        alpha = selectedFilter and 1 or (filterRowOn and 0.8 or 0.55),
                        relativePosition = v2(0.5, 0.5), anchor = v2(0.5, 0.5) } },
        },
    }
    components.attachTooltip(funnelBtn, l10n('filter_tooltip'))

    local searchRow = {   -- [margin] [funnel] [margin] [search box]  (funnel aligns with quest icons)
        name = 'searchRow',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.listW, SEARCH_H), autoSize = false,
                  arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(ICON_MARGIN, 0) } },
            funnelBtn,
            { props = { size = v2(ICON_MARGIN, 0) } },
            searchBox,
        },
    }

    local leftBody = {
        name = 'leftBody',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.listW, s.listViewH), autoSize = false },
        content = ui.content {
            {
                name = 'listVp',
                type = ui.TYPE.Widget,
                props = { size = v2(s.listVpW, s.listViewH) },
                events = {
                    mouseMove = async:callback(function() activePane = 'list' end),
                },
                content = ui.content {
                    {
                        name = 'listInner',
                        type = ui.TYPE.Flex,
                        props = { position = v2(0, -listOffset), autoSize = true },
                        events = {
                            mouseMove = async:callback(function() activePane = 'list' end),
                            mousePress = async:callback(function() activePane = 'list' end),
                        },
                        content = ui.content(rows),
                    },
                },
            },
            listBar,
        },
    }

    local listStatus = {   -- slim status strip: top divider + left group (hidden eye+count) + right shown/total.
        name = 'listStatus',
        type = ui.TYPE.Widget,
        props = { size = v2(s.listW, STATUS_H) },
        content = ui.content {
            { template = I.MWUI.templates.horizontalLine },   -- top border (y = 0)
            {   -- left group: [eye N] — rebuilt by refreshList; empty when nothing hidden
                name = 'statusLeft',
                type = ui.TYPE.Flex,
                props = { horizontal = true, arrange = ui.ALIGNMENT.Center,
                          position = v2(2, 0), relativePosition = v2(0, 0.5), anchor = v2(0, 0.5) },
                content = ui.content(statusLeftNodes()),
            },
            {   -- right: shown / total, near the divider (2px gap), nudged up off the bottom line
                name = 'listCounter',
                type = ui.TYPE.Text,
                template = I.MWUI.templates.textNormal,
                props = { text = #currentOrder .. ' / ' .. listTotal,
                          textColor = components.GRAY, textSize = 14,
                          position = v2(-2, 0), relativePosition = v2(1, 0.5), anchor = v2(1, 0.5) },
            },
        },
    }

    -- Assemble: search row, the combo row (only while shown, pushing the list down), list body, status.
    local content = { searchRow }
    if filterRowOn then content[#content + 1] = buildComboRow(s) end
    content[#content + 1] = leftBody
    content[#content + 1] = listStatus

    return {
        name = 'left',
        type = ui.TYPE.Flex,
        props = { horizontal = false, size = v2(s.listW, s.contentH), autoSize = false },
        content = ui.content(content),
    }
end

-- ---- right pane: category + entries ----------------------------------------
local function buildDetailContent(s)
    if not selectedId then
        detailContentH = ROW_H
        return { components.textLine(l10n('no_quest_selected')) }
    end
    local quest = I.QuestmanData.getQuest(selectedId)
    if not quest then
        detailContentH = ROW_H
        vitems.detail = { { node = components.textLine(l10n('no_quest_selected')), h = ROW_H } }
        return
    end

    local items = {}
    local h = 0
    local function push(layout, height)
        items[#items + 1] = { node = layout, h = height }
        h = h + height
    end

    -- Title row: quest name (grows) + pin & hide toggle buttons (full when active, dim otherwise).
    -- Same actions as ctrl+click (pin) / Del (hide) on the selection.
    local function iconToggle(iconPath, isOn, toggle, tipFn)
        local btn = {
            type = ui.TYPE.Image,
            props = { size = v2(18, 18), resource = ui.texture { path = iconPath }, alpha = isOn and 1 or 0.45 },
            events = { mouseClick = async:callback(function() toggle(); refreshList(); refreshDetail() end) },
        }
        components.attachTooltip(btn, tipFn)
        return btn
    end
    local pinBtn = iconToggle(PIN_ICON, quest.pinned, function() I.QuestmanData.togglePin(quest.id) end,
        function() return quest.pinned and l10n('unpin_quest') or l10n('pin_quest') end)
    local eyeBtn = iconToggle(HIDDEN_ICON, quest.hidden, function() I.QuestmanData.toggleHide(quest.id) end,
        function() return quest.hidden and l10n('unhide_quest') or l10n('hide_quest') end)
    push({
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.detailVpW - 2, TITLE_H), autoSize = false,
                  arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { template = I.MWUI.templates.textHeader, props = { text = quest.name or quest.id, textSize = 20 },
              external = { grow = 1 } },
            pinBtn,
            { props = { size = v2(6, 0) } },   -- margin between the two icon buttons
            eyeBtn,
        },
    }, TITLE_H)
    push({ props = { size = v2(0, 4) } }, 4)   -- small gap separating the title from the static labels
    -- Category / faction lines double as filter launchers (like the Stats rows): clicking jumps to the
    -- Quests tab filtered to that group. Same look/colours — only a click handler is added.
    local catKey = quest.category or 'unknown'
    local catText = l10n('cat_' .. catKey)
    if quest.addonLabel then catText = catText .. ' (' .. quest.addonLabel .. ')' end   -- e.g. "Daedric Quests (Bloodmoon)"
    push(components.labelValue(l10n('category_label'), catText, components.LABEL_COLOR,
        function() jumpToFilter('category', catKey, l10n('cat_' .. catKey)) end), LINE_ROW)
    if quest.faction then
        -- keyOf('faction') is the factionId; without it a filter would match nothing, so leave it static.
        local onFaction = quest.factionId
            and function() jumpToFilter('faction', quest.factionId, quest.faction) end or nil
        push(components.labelValue(l10n('faction_label'), quest.faction, components.LABEL_COLOR, onFaction), LINE_ROW)
    end
    if quest.giver then
        push(components.labelValue(l10n('quest_from_label'), quest.giver, components.LABEL_COLOR), LINE_ROW)
    end
    if settings:get('ShowTechnicalInfo') then
        -- Show the started record actually driving the display + ITS OWN stage. The main id may be a
        -- not-yet-started finishing record (e.g. C3_DestroyDagoth while only C0_Act_C_Expo has started),
        -- so pairing it with this stage would be misleading. Meta quests span several journal ids, but
        -- listing them all here is noisy; the full list is logged on select instead (see onSelect).
        local active = (quest.techRows or {})[1]   -- active branch first; falls back to the main id
        local techId = active and active.id or quest.id
        local techStage = active and active.stage or quest.stage or 0
        push(components.textLine(l10n('tech_info', { id = techId, stage = techStage }), components.GRAY), LINE_ROW)
    end
    push({ props = { size = v2(0, PAD) } }, PAD)

    local entries = quest.entries or {}
    if #entries > 0 then
        push(components.subtitle(l10n('journal_entries_label')), LINE_ROW)
        push({ props = { size = v2(0, PAD) } }, PAD)
        -- Newest entry first, numbered high-to-low (the player reads the latest progress at the top).
        for i = #entries, 1, -1 do
            local text = entries[i].text or ''
            push(components.entry(i, text, s.detailVpW - PAD),
                uiScroll.estimateTextHeight(('%d. %s'):format(i, text), s.detailVpW - PAD) + 2)
            push({ props = { size = v2(0, ENTRY_GAP) } }, ENTRY_GAP)   -- small gap between entries
        end
    end

    -- "Related topics": accumulated topics this quest's journal entries hyperlink to (@keyword#).
    -- Clicking a link jumps to the Topics page with that topic selected (openTopic). Same look as the
    -- Topics page's own related list.
    local links = I.QuestmanData.getQuestLinks(quest.id)
    if #links > 0 then
        push({ props = { size = v2(0, PAD) } }, PAD)
        push(components.subtitle(l10n('related_topics')), TITLE_H)
        for _, lk in ipairs(links) do
            local id = lk.id
            push({
                type = ui.TYPE.Flex, props = { horizontal = true, size = v2(s.detailVpW - PAD, TPC_ROW_H),
                                               autoSize = false, arrange = ui.ALIGNMENT.Center },
                content = ui.content {
                    components.link(lk.name, function() openTopic(id) end),
                },
            }, TPC_ROW_H)
        end
    end

    detailContentH = h
    vitems.detail = items
end

local function detailThumb(s)
    local trackH = s.detailViewH - 2 * ARROW_H
    local function step(d)
        detailOffset = uiScroll.clamp(detailOffset + d, detailContentH, s.detailViewH)
        applyDetailOffset()
    end
    return components.scrollbar {
        width = BAR_W, height = s.detailViewH, arrowH = ARROW_H,
        thumb = uiScroll.thumb(detailContentH, s.detailViewH, trackH, detailOffset, SCROLL_SLACK),
        onDrag = function(dy) step(dy * (detailContentH / math.max(1, trackH))) end,
        onStepUp = function() step(-WHEEL_STEP) end,
        onStepDown = function() step(WHEEL_STEP) end,
    }
end

local function buildDetail(s)
    buildDetailContent(s)   -- MUST run before detailThumb: fills vitems.detail + sets detailContentH
    local detailBar = detailThumb(s)
    detailBar.name = 'detailBar'
    return {
        name = 'detail',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.detailW, s.detailViewH), autoSize = false },
        external = { grow = 1 },
        content = ui.content {
            {
                name = 'detailVp',
                type = ui.TYPE.Widget,
                props = { size = v2(s.detailVpW, s.detailViewH) },
                events = {
                    mouseMove = async:callback(function() activePane = 'detail' end),
                },
                content = ui.content {
                    {
                        name = 'detailInner',
                        type = ui.TYPE.Flex,
                        -- Explicit height (= detailContentH, the summed content height buildDetailContent
                        -- just computed) instead of autoSize: an autoSize Flex re-sums — and so re-measures
                        -- — all its children on every update(), and scrolling calls update() constantly, so
                        -- a page of auto-height journal paragraphs made scrolling lag. We already know the
                        -- height, so hand it over. (detailVpW-wide so children keep their layout width.)
                        props = { size = v2(s.detailVpW, detailContentH),
                                  position = v2(0, DETAIL_DY - detailOffset), autoSize = false },
                        events = {
                            mouseMove = async:callback(function() activePane = 'detail' end),
                            mousePress = async:callback(function() activePane = 'detail' end),
                        },
                        content = ui.content(buildVarSlice(vitems.detail, detailOffset, s.detailViewH)),
                    },
                },
            },
            detailBar,
        },
    }
end

-- ---- window assembly -------------------------------------------------------
local function buildTitleBar(s)
    -- textured "head block" that grows to fill one side of the caption (like MW_Window)
    local function block()
        return {
            type = ui.TYPE.Image,
            external = { grow = 1 },
            props = {
                resource = ui.texture { path = 'textures/menu_head_block_middle.dds' },
                tileH = true,
                tileV = true,
                size = v2(0, TITLE_H),
            },
        }
    end
    return {
        name = 'titlebar',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.innerW, TITLE_H), autoSize = false,
                  arrange = ui.ALIGNMENT.Center },
        userData = { drag = false, last = nil },
        content = ui.content {
            -- textured blocks on the sides, title on the dark centre (readable) — no buttons in the header
            block(),
            { props = { size = v2(12, 0) } },
            {
                template = I.MWUI.templates.textHeader,
                props = { text = l10n('menu_title'), textSize = 16 },
            },
            { props = { size = v2(12, 0) } },
            block(),
        },
        events = {
            mousePress = async:callback(function(e, layout)
                layout.userData.drag = true
                layout.userData.last = e.position
            end),
            mouseMove = async:callback(function(e, layout)
                if layout.userData.drag and layout.userData.last then
                    local d = e.position - layout.userData.last
                    geom.x = geom.x + d.x
                    geom.y = geom.y + d.y
                    layout.userData.last = e.position
                    if menu then
                        menu.layout.props.position = v2(geom.x, geom.y)
                        menu:update()
                    end
                end
            end),
            mouseRelease = async:callback(function(_, layout)
                layout.userData.drag = false
                savePos()
            end),
        },
    }
end

-- ---- window resize: 8 transparent strips over the border (edges + corners) ---------------------------
-- Each strip owns one drag direction: it shows the matching resize cursor on hover (props.pointer, drawn
-- natively by MyGUI) and drives a manual drag that runs the pure uiResize.apply math, then reuses geom +
-- applySizes + save. Corners are added AFTER edges in build() so they win the overlapping hit area.
-- (Kept as one block for the future uiWindow.lua extraction.)
local RZ = uiResize.DIR
-- resize-strip constants bundled in one table (also keeps the module under Lua 5.1's 200-local limit).
-- edge/corner = hit thickness; border = MWUI thickBorder (boxTransparentThick frame width per side).
local RZC = {
    edge = 6, corner = 12, border = 4,
    pointer = {
        [RZ.L] = 'hresize', [RZ.R] = 'hresize', [RZ.T] = 'vresize', [RZ.B] = 'vresize',
        [RZ.TL] = 'dresize', [RZ.BR] = 'dresize', [RZ.TR] = 'dresize2', [RZ.BL] = 'dresize2',
    },
    name = {
        [RZ.L] = 'rzL', [RZ.R] = 'rzR', [RZ.T] = 'rzT', [RZ.B] = 'rzB',
        [RZ.TL] = 'rzTL', [RZ.TR] = 'rzTR', [RZ.BL] = 'rzBL', [RZ.BR] = 'rzBR',
    },
    all = { RZ.L, RZ.R, RZ.T, RZ.B, RZ.TL, RZ.TR, RZ.BL, RZ.BR },
}

-- Explicit strip rect in the window's OUTER (full-window) coordinate space -> position, size. The strips
-- are children of the plain-Widget root (size = outer), so they sit on the real window edge. relativeSize/
-- relativePosition are avoided (they don't resolve against the auto-sizing box); we place/size by hand from
-- the outer size and refresh in applySizes(). Edges span the full side; corners are boxes drawn on top.
local function stripRect(dir, ow, oh)
    local E, C = RZC.edge, RZC.corner
    if dir == RZ.L  then return v2(0, 0),             v2(E, oh) end
    if dir == RZ.R  then return v2(ow - E, 0),        v2(E, oh) end
    if dir == RZ.T  then return v2(0, 0),             v2(ow, E) end
    if dir == RZ.B  then return v2(0, oh - E),        v2(ow, E) end
    if dir == RZ.TL then return v2(0, 0),             v2(C, C) end
    if dir == RZ.TR then return v2(ow - C, 0),        v2(C, C) end
    if dir == RZ.BL then return v2(0, oh - C),        v2(C, C) end
    return v2(ow - C, oh - C), v2(C, C)   -- RZ.BR
end

local function makeResizeStrip(dir, outer)
    local pos, size = stripRect(dir, outer.x, outer.y)
    return {
        name = RZC.name[dir],
        type = ui.TYPE.Widget,
        props = {
            position = pos,
            size = size,
            pointer = RZC.pointer[dir],   -- native resize cursor on hover
            propagateEvents = false,
        },
        userData = { drag = false, from = nil, start = nil },
        events = {
            mousePress = async:callback(function(e, layout)
                layout.userData.drag = true
                layout.userData.from = e.position
                layout.userData.start = { x = geom.x, y = geom.y, w = geom.w, h = geom.h }
            end),
            mouseMove = async:callback(function(e, layout)
                if not (layout.userData.drag and layout.userData.from and menu) then return end
                local screen = logicalScreen()
                local g = uiResize.apply(dir, e.position - layout.userData.from, layout.userData.start,
                    { minW = MIN_W, minH = MIN_H, screenW = screen.x, screenH = screen.y })
                geom.x, geom.y, geom.w, geom.h = g.x, g.y, g.w, g.h
                menu.layout.props.position = v2(geom.x, geom.y)   -- origin may move (left/top edges)
                applySizes()                                      -- resizes inner nodes + menu:update()
            end),
            mouseRelease = async:callback(function(_, layout)
                layout.userData.drag = false
                saveSize()   -- width/height -> settings
                savePos()    -- x/y may have changed -> disk
            end),
        },
    }
end

-- Draggable vertical divider between the list and detail panes. Wraps the same verticalLine + gap the
-- panes used before, plus a hresize cursor and a horizontal drag that shifts the list/detail split
-- fraction (clamped); applySizes then re-lays-out the panes. `getFrac`/`setFrac` read+write the page's
-- fraction (questListFrac for Quests, topicListFrac for Topics), so the same handle serves both pages.
-- `saveFrac` persists the settled fraction to its % setting on release (like saveSize for the window size).
local DIVIDER_MIN_FRAC, DIVIDER_MAX_FRAC = 0.2, 0.6
local function makeDivider(getFrac, setFrac, saveFrac)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, pointer = 'hresize', propagateEvents = false },
        external = { stretch = 1 },   -- fill the pane height; auto-follows window resize
        userData = { drag = false, fromX = 0, startFrac = 0 },
        -- pointer on BOTH children too: they sit on top of the Flex, so without it the line shows the
        -- default arrow (only the pass-through gap showed hresize -> a thin zone offset right of the line).
        -- With it, the whole handle -- starting at the visible line -- reads as the resize grab zone.
        content = ui.content {
            { template = I.MWUI.templates.verticalLine, external = { stretch = 1 }, props = { pointer = 'hresize' } },
            { props = { size = v2(DETAIL_GAP, 0), pointer = 'hresize' } },   -- gap before detail
        },
        events = {
            mousePress = async:callback(function(e, l)
                l.userData.drag = true
                l.userData.fromX = e.position.x
                l.userData.startFrac = getFrac()
                dividerDrag = true   -- applySizes resizes in place (no rebuild) so this handle survives the drag
            end),
            mouseMove = async:callback(function(e, l)
                if not (l.userData.drag and menu) then return end
                local innerW = sizes().innerW
                if innerW <= 0 then return end
                local frac = l.userData.startFrac + (e.position.x - l.userData.fromX) / innerW
                setFrac(math.max(DIVIDER_MIN_FRAC, math.min(DIVIDER_MAX_FRAC, frac)))
                applySizes()
            end),
            mouseRelease = async:callback(function(_, l)
                l.userData.drag = false
                dividerDrag = false
                if saveFrac then saveFrac() end   -- persist the % to settings
                applySizes()   -- final full reflow (rebuilds virtualized panes at the settled width)
            end),
        },
    }
end

-- footer button row content: the show-completed checkbox (the shown/total counter now lives in the
-- list's bottom status strip, freeing the footer). [✔ Display completed] — the checkbox (bordered box
-- + bundled tick image when on) toggles the completed filter.
local COMPLETED_TICK = 'Icons/questman/ui_check_mark.dds'
local function footerButtons()
    -- Topics page: the count moved to the list's own status strip (like Quests), so the footer is empty.
    if activePage ~= 'quests' then return {} end   -- the completed toggle is a quest-list control only
    return {
        components.checkbox {
            checked = showAll,
            style = 'image',
            image = COMPLETED_TICK,
            label = l10n('display_completed_hidden'),
            onClick = function()
                showAll = not showAll
                listOffset = 0
                refreshFooter()   -- redraw the checkbox state
                refreshList()     -- re-filter the list + counter
            end,
        },
    }
end

-- close button in the footer, right side (left of the resize grip) — system windows keep buttons
-- out of the title bar
local function footerClose()
    -- Exit whichever mode owns us (teardown follows via onUiModeChanged / the override hideFn).
    local b = components.button(l10n('close'), function()
        I.UI.removeMode(overrideMenuOpen and 'Journal' or 'Interface')
    end)
    b.props = b.props or {}
    b.props.relativePosition = v2(1, 0.5)
    b.props.anchor = v2(1, 0.5)
    b.props.position = v2(-FOOTER_GAP, 0)   -- inset from the footer's right edge = the button's vertical gap
    return b
end

-- ---- page tabs (Quests / Stats) --------------------------------------------
local switchPage   -- forward decl (tabButtons references it)

-- A stats row: [PAD][label column][value column, right-aligned][optional checkmark]. The value column
-- is fixed-width so the "N / N" numbers align vertically across rows; labelW sits just past the longest
-- label so the gap stays small. label/value text clips to its box (no overflow into the next column).
local function statRow(W, labelW, label, value, opts)
    opts = opts or {}
    -- Icon cell — image when opts.icon is set, else an empty spacer of the same width, so labels and the
    -- "N / N" values stay aligned across rows whether or not a row has an icon (the Overview rows have none).
    local iconCell
    if opts.icon then
        iconCell = { type = ui.TYPE.Image,
                     props = { size = v2(ICON_SZ, ICON_SZ), resource = ui.texture { path = opts.icon } } }
        components.attachIconZoom(iconCell, opts.icon, STAT_ICON_ZOOM)   -- hover -> enlarged preview (Stats only)
    else
        iconCell = { props = { size = v2(ICON_SZ, 0) } }
    end
    local labelBox = {
        type = ui.TYPE.Widget, props = { size = v2(labelW, STAT_ROW) },
        content = ui.content {
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = label .. ':', textColor = components.LABEL_COLOR,
                        relativePosition = v2(0, 0.5), anchor = v2(0, 0.5) } },
        },
    }
    local valueBox = {
        type = ui.TYPE.Widget, props = { size = v2(STAT_VALUE_W, STAT_ROW) },
        content = ui.content {
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = value, relativePosition = v2(1, 0.5), anchor = v2(1, 0.5) } },
        },
    }
    local cells = { { props = { size = v2(PAD, 0) } }, iconCell,
                    { props = { size = v2(STAT_ICON_GAP, 0) } }, labelBox, valueBox }
    if opts.check then
        local tick = { type = ui.TYPE.Image,
                       props = { size = v2(14, 14), resource = ui.texture { path = STAT_TICK } } }
        if opts.checkGray then tick.props.color = components.GRAY end   -- muted = earned elsewhere / not here
        if opts.checkTip then components.attachTooltip(tick, opts.checkTip) end
        cells[#cells + 1] = { props = { size = v2(5, 0) } }
        cells[#cells + 1] = tick
    end
    local row = { type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, STAT_ROW), autoSize = false,
                                                 arrange = ui.ALIGNMENT.Center },
                  content = ui.content(cells) }
    if opts.onClick then   -- the whole row opens the Quests tab pre-filtered to this group (see statFilter)
        row.events = { mouseClick = async:callback(opts.onClick) }
    end
    return row
end

local function statHeader(W, title)
    return { type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, STAT_HEADER_H), autoSize = false,
                                            arrange = ui.ALIGNMENT.Center },
             content = ui.content {
                 { props = { size = v2(PAD, 0) } },
                 { template = I.MWUI.templates.textHeader, props = { text = title, textSize = 16 } },
             } }
end

-- Build a column of stat nodes (all width W) via an accumulator; returns (nodes, totalHeight).
local function statsColumn(W, build)
    local out, h = {}, 0
    local api = {}
    function api.header(title) out[#out + 1] = statHeader(W, title); h = h + STAT_HEADER_H end
    function api.row(labelW, label, value, opts) out[#out + 1] = statRow(W, labelW, label, value, opts); h = h + STAT_ROW end
    function api.divider()
        out[#out + 1] = { props = { size = v2(0, 6) } }; h = h + 6
        out[#out + 1] = { template = I.MWUI.templates.horizontalLine, props = { size = v2(W, 0) }, external = { stretch = 1 } }; h = h + 2
    end
    build(api)
    return out, h
end

-- Jump to the Quests tab with this group as the active filter, so both the Progress page rows and the
-- quest-detail category/faction lines double as launchers into the matching quests.
-- `axis` = 'addon'|'category'|'faction'; key/label match a getFilterOptions entry.
jumpToFilter = function(axis, key, label)
    selectedFilter = { axis = axis, key = key, label = label }
    filterRowOn = true   -- reveal the filter row so the active filter shows and can be cleared
    listOffset = 0
    closeFilterPopup()
    -- From another tab (Stats rows), switch to Quests -> switchPage rebuilds the page with the filter.
    -- From the Quests detail pane we're already here, so goToPage would no-op (activePage unchanged) and
    -- nothing would redraw; rebuild the pane in place so the combo row, funnel shade and list all reflect
    -- the new filter (same path selectFilter uses).
    if activePage == 'quests' then
        rebuildQuestPane()
    else
        goToPage('quests')
    end
end

-- Click handler for a stat row (see jumpToFilter). `x` is the stats row (its {key,label} match a
-- getFilterOptions entry).
local function statFilter(axis, x)
    return function() jumpToFilter(axis, x.key, x.label) end
end

-- Two side-by-side stat columns (no divider between them):
--   LEFT  = Overview + By factions        RIGHT = By add-ons + By categories
-- Every non-Overview row carries its group's icon and is clickable (see statFilter). Sets statsContentH
-- to the taller column, which drives the single shared scrollbar.
local function buildStatsColumns(stats, vpW)
    -- Static layout: fixed label + value widths -> a fixed column width, so the right column and the numbers
    -- stay put regardless of window size (vpW is intentionally ignored). Narrow windows just clip on the
    -- right (labels get a hover tooltip); widen the window or trim STAT_LABEL_W if that ever bites.
    local labelW = STAT_LABEL_W
    local colW = PAD + ICON_SZ + STAT_ICON_GAP + labelW + STAT_VALUE_W + STAT_CHECK_W + STAT_COL_GAP
    -- The RIGHT column starts at x = colW (the columns sit flush in a horizontal Flex). An odd colW lands
    -- that x on a half-pixel at fractional GUI scales (e.g. 343 * 1.5 = 514.5), which shifts the whole right
    -- column and clips its icons' left edge. Snap colW up to a multiple of 4 so the boundary is a whole
    -- pixel at the common 1.25/1.5/1.75/2.0 scales. (The left column starts at 0, so it's already fine.)
    colW = math.ceil(colW / 4) * 4

    -- Value formatters: "done / total" for a group, or a single number (the Overview "Active" count).
    local function pair(done, total) return done .. ' / ' .. total end
    local function single(n) return tostring(n) end

    local leftNodes, leftH = statsColumn(colW, function(c)
        c.header(l10n('stats_overview'))
        c.row(labelW, l10n('stat_active'), single(stats.overall.active),
              { icon = STAT_ICON_ACTIVE })                                                            -- in-progress icon; not clickable
        c.row(labelW, l10n('stat_completed'), pair(stats.overall.completed, stats.overall.total),
              { icon = STAT_ICON_DONE })                                                              -- completed icon; not clickable
        -- Skip the whole "By factions" block (divider + header) until the player has a faction quest —
        -- otherwise the start of the game shows a bare "By factions:" label over nothing.
        if #stats.byFaction > 0 then
            c.divider()
            c.header(l10n('stats_by_faction'))
            for _, x in ipairs(stats.byFaction) do
                local opts = { icon = x.icon, onClick = statFilter('faction', x) }
                if x.topRank then
                    opts.check = true; opts.checkTip = l10n('tip_faction_top_rank')            -- reached the highest rank
                elseif x.otherHouseDone then   -- a mutually-exclusive Great House was completed instead
                    opts.check = true; opts.checkGray = true
                    opts.checkTip = l10n('tip_other_house_done', { name = x.otherHouseDone })
                end
                c.row(labelW, x.label, pair(x.done, x.total), opts)
            end
        end
    end)

    local rightNodes, rightH = statsColumn(colW, function(c)
        c.header(l10n('stats_by_addon'))
        for _, x in ipairs(stats.byAddon) do
            c.row(labelW, x.label, pair(x.done, x.total),
                  { icon = x.icon, onClick = statFilter('addon', x),
                    check = x.mainDone, checkTip = l10n('tip_main_quest_done') })   -- main-quest-done checkmark
        end
        c.divider()
        c.header(l10n('stats_by_category'))
        for _, x in ipairs(stats.byCategory) do
            c.row(labelW, x.label, pair(x.done, x.total),
                  { icon = x.icon, onClick = statFilter('category', x) })
        end
    end)

    statsContentH = math.max(leftH, rightH)
    local function column(nodes)
        return { type = ui.TYPE.Flex, props = { horizontal = false, autoSize = false, size = v2(colW, statsContentH) },
                 content = ui.content(nodes) }
    end
    return { column(leftNodes), column(rightNodes) }
end

-- The single scrollable stats panel = [viewport(inner Flex)][scrollbar].
local function statsPane(paneW, viewH, contentNodes)
    local trackH = viewH - 2 * ARROW_H
    local function step(d)
        statsOffset = uiScroll.clamp(statsOffset + d, statsContentH, viewH)
        applyStatsOffset()
    end
    local bar = components.scrollbar {
        width = BAR_W, height = viewH, arrowH = ARROW_H,
        thumb = uiScroll.thumb(statsContentH, viewH, trackH, statsOffset),
        onDrag = function(dy) step(dy * (statsContentH / math.max(1, trackH))) end,
        onStepUp = function() step(-WHEEL_STEP) end,
        onStepDown = function() step(WHEEL_STEP) end,
    }
    bar.name = 'statsColBar'
    return {
        name = 'statsCol',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(paneW, viewH), autoSize = false },
        content = ui.content {
            {
                name = 'statsColVp',
                type = ui.TYPE.Widget,
                props = { size = v2(paneW - BAR_W, viewH) },
                events = { mouseMove = async:callback(function() activePane = 'stats' end) },
                content = ui.content {
                    {
                        name = 'statsColInner',
                        type = ui.TYPE.Flex,   -- horizontal: the two stat columns sit side by side; y-offset scrolls both
                        props = { horizontal = true, autoSize = true, position = v2(0, -statsOffset) },
                        content = ui.content(contentNodes),
                    },
                },
            },
            bar,
        },
    }
end

-- Two-column panel (Overview + Factions | Add-ons + Categories) under a single shared scrollbar.
local function buildStatsPage(s)
    local stats = I.QuestmanData.getStats()
    local viewH = s.contentH
    local vpW = s.innerW - BAR_W                  -- inner (viewport) width the two columns fill
    local cols = buildStatsColumns(stats, vpW)    -- MUST precede statsPane: sets statsContentH (thumb input)
    return {
        name = 'statsPage',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.innerW, s.contentH), autoSize = false },
        content = ui.content {
            statsPane(s.innerW, viewH, cols),
        },
    }
end

-- ---- Topics page ----------------------------------------------------------

-- Generic vertical scroll pane: [viewport(inner Flex)][scrollbar]. `pre` = node-name prefix; `step(d)`
-- adjusts the offset + thumb; `onHover` marks the active pane. (Stats has its own statsPane; this serves
-- the Topics page, the filter dropdown, and any future interactive scroll pane.)
-- Forward-declared (top of file) so buildLeft, defined earlier, can use it for the filter dropdown.
scrollPane = function(pre, paneW, viewH, contentNodes, contentH, offset, step, onHover, slack)
    local trackH = viewH - 2 * ARROW_H
    local bar = components.scrollbar {
        width = BAR_W, height = viewH, arrowH = ARROW_H,
        thumb = uiScroll.thumb(contentH, viewH, trackH, offset, slack),   -- slack: text panes only (est. height)
        onDrag = function(dy) step(dy * (contentH / math.max(1, trackH))) end,
        onStepUp = function() step(-WHEEL_STEP) end,
        onStepDown = function() step(WHEEL_STEP) end,
    }
    bar.name = pre .. 'Bar'
    return {
        name = pre, type = ui.TYPE.Flex, props = { horizontal = true, size = v2(paneW, viewH), autoSize = false },
        content = ui.content {
            { name = pre .. 'Vp', type = ui.TYPE.Widget, props = { size = v2(paneW - BAR_W, viewH) },
              events = { mouseMove = async:callback(onHover) },
              content = ui.content {
                  { name = pre .. 'Inner', type = ui.TYPE.Flex,
                    props = { horizontal = false, autoSize = true, position = v2(0, -offset) },
                    content = ui.content(contentNodes) },
              } },
            bar,
        },
    }
end

-- The FilterDropDown combo row (shown under the search box while `filterRowOn`): a bordered box that
-- displays the active filter (or "All quests") + a ⇓ glyph; clicking it toggles the options popover.
buildComboRow = function(s)
    local label = selectedFilter and selectedFilter.label or l10n('filter_all')
    -- The box GROWS to fill the row (no trailing margin) so its right border reaches the divider, exactly
    -- like the search box. Label + ⇓ are absolutely positioned (left / right insets) so no width is needed.
    return {
        name = 'filterRow', type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.listW, COMBO_H), autoSize = false,
                  arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(ICON_MARGIN, 0) } },
            {
                name = 'filterCombo', type = ui.TYPE.Widget,
                props = { size = v2(0, SEARCH_H) }, external = { grow = 1 },
                events = { mouseClick = async:callback(function() toggleFilterPopup() end) },
                content = components.framed {
                    { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                      props = { text = label, textColor = selectedFilter and components.WHITE or components.GRAY,
                                position = v2(PAD, 0), relativePosition = v2(0, 0.5), anchor = v2(0, 0.5) } },
                    { type = ui.TYPE.Image,
                      props = { size = v2(14, 14), resource = ui.texture { path = FILTER_ARROW },
                                position = v2(-PAD, 0), relativePosition = v2(1, 0.5), anchor = v2(1, 0.5) } },
                },
            },
        },
    }
end

-- Walk named nodes inside the popover Element (separate from the menu, so nodeByPath can't reach it).
local function popNode(...)
    if not popupEl then return nil end
    local c = popupEl.layout.content
    local node
    for _, name in ipairs({ ... }) do
        if not c then return nil end
        node = c[name]
        if not node then return nil end
        c = node.content
    end
    return node
end

-- The floating options popover: a full-screen transparent backdrop (a click outside closes it) holding a
-- solid box, anchored just below the combo row, with the grouped single-select option list inside.
buildFilterPopup = function()
    local s = sizes()
    local popW = s.listW - ICON_MARGIN     -- match the combo box (ICON_MARGIN inset on the left, flush right)
    local rowW = popW - BAR_W

    local function optionRow(label, count, active, onClick)
        -- match the quest list: the active (selected) option is the bright WHITE, the rest the gold HIGHLIGHT
        local color = active and components.WHITE or components.HIGHLIGHT
        return {
            type = ui.TYPE.Flex, props = { horizontal = true, size = v2(rowW, FILTER_ROW_H),
                                           autoSize = false, arrange = ui.ALIGNMENT.Center },
            content = ui.content {
                { props = { size = v2(PAD, 0) } },
                { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal, external = { grow = 1 },
                  props = { text = label, textColor = color } },
                count and { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                            props = { text = tostring(count), textColor = components.GRAY, textSize = 14 } }
                      or { props = { size = v2(0, 0) } },
                { props = { size = v2(PAD, 0) } },
            },
            events = { mouseClick = async:callback(onClick) },
        }
    end
    local function headerRow(text)   -- same font size as the option (category) rows; just a different colour
        return {
            type = ui.TYPE.Flex, props = { horizontal = true, size = v2(rowW, FILTER_HDR_H),
                                           autoSize = false, arrange = ui.ALIGNMENT.Center },
            content = ui.content {
                { props = { size = v2(4, 0) } },
                { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                  props = { text = text, textColor = components.LABEL_COLOR } },
            },
        }
    end

    local nodes, h = {}, 0
    local function add(node, ht) nodes[#nodes + 1] = node; h = h + ht end
    add(optionRow(l10n('filter_all'), nil, selectedFilter == nil, function() selectFilter(nil) end), FILTER_ROW_H)
    local lastAxis
    for _, o in ipairs(I.QuestmanData.getFilterOptions()) do
        if o.axis ~= lastAxis then
            lastAxis = o.axis
            add(headerRow(l10n('filter_axis_' .. o.axis)), FILTER_HDR_H)
        end
        local active = selectedFilter ~= nil and selectedFilter.axis == o.axis and selectedFilter.key == o.key
        add(optionRow(o.label, o.count, active, function() selectFilter(o) end), FILTER_ROW_H)
    end
    filterContentH = h
    local popH = math.min(FILTER_POPUP_H, filterContentH)
    popupViewH = popH
    filterOffset = uiScroll.clamp(filterOffset, filterContentH, popH)

    -- anchor under the combo row using window-relative layout constants (tweak DIV / PAD if misaligned)
    local popX = geom.x + PAD + ICON_MARGIN
    local popY = geom.y + PAD + TITLE_H + DIV + TAB_H + DIV + SEARCH_H + COMBO_H

    local pane = scrollPane('filterDD', popW, popH, nodes, filterContentH, filterOffset,
        function(d) filterOffset = uiScroll.clamp(filterOffset + d, filterContentH, popH); applyFilterOffset() end,
        function() end)

    return {
        layer = POPUP_LAYER,
        type = ui.TYPE.Widget,
        props = { size = logicalScreen() },   -- full-screen backdrop; a press outside the box closes the popover
        events = { mousePress = async:callback(function() closeFilterPopup() end) },
        content = ui.content {
            {   -- solid box (covers the list); propagateEvents=false so inside-clicks don't hit the backdrop
                name = 'filterPop', type = ui.TYPE.Container, template = I.MWUI.templates.boxSolid,
                props = { position = v2(popX, popY), propagateEvents = false },
                content = ui.content { pane },
            },
        },
    }
end

openFilterPopup = function()
    if popupEl then return end
    filterOffset = 0
    local ok, el = pcall(function() return ui.create(buildFilterPopup()) end)
    if ok then popupEl = el else dbg('filter popup create failed:', tostring(el)) end
end

closeFilterPopup = function()
    if popupEl then pcall(function() popupEl:destroy() end); popupEl = nil end
end

toggleFilterPopup = function()
    if popupEl then closeFilterPopup() else openFilterPopup() end
end

-- One implementation of "move a scroll pane to its current offset" — shared by every apply<X>Offset below,
-- so the clamp / virtualized-slice re-render / inner reposition / thumb reposition / refresh lives in ONE
-- place. Returns the clamped offset so the caller stores it back into its state var. cfg:
--   offset / contentH / viewH   the pane's scroll state + viewport height
--   find                        node lookup for this pane's element (nodeByPath for the menu, popNode for the popup)
--   inner / thumb               path arrays (splatted into `find`) for the inner Flex and the bar's 'thumb'
--   el                          the Element to :update() (menu or popupEl)
--   topMargin (optional)        fixed top inset of the inner content (e.g. the detail pane's DETAIL_DY)
--   renderSlice (optional)      function(offset, viewH) -> nodes; virtualized panes redraw the visible window
local function applyScrollPane(cfg)
    local offset = uiScroll.clamp(cfg.offset, cfg.contentH, cfg.viewH)
    local inner = cfg.find(unpack(cfg.inner))
    if inner then
        if cfg.renderSlice then inner.content = ui.content(cfg.renderSlice(offset, cfg.viewH)) end
        inner.props.position = v2(0, (cfg.topMargin or 0) - offset)
    end
    local thumb = cfg.find(unpack(cfg.thumb))
    if thumb then
        local trackH = cfg.viewH - 2 * ARROW_H
        thumb.props.position = v2(2, ARROW_H + uiScroll.thumb(cfg.contentH, cfg.viewH, trackH, offset).top)
    end
    cfg.el:update()
    return offset
end

applyFilterOffset = function()
    if not popupEl then return end
    filterOffset = applyScrollPane {
        offset = filterOffset, contentH = filterContentH, viewH = popupViewH, el = popupEl, find = popNode,
        inner = POP.filterInner, thumb = POP.filterThumb,
    }
end

local function topicDims(s)
    local listW = math.max(160, math.floor(s.innerW * topicListFrac))
    local detailW = s.innerW - listW - DETAIL_GAP - 2
    -- list viewport = content minus the fixed search row (top) and the status strip (bottom), mirroring
    -- the Quests left column (search + list + status).
    return listW, detailW, s.contentH - SEARCH_H - STATUS_H
end

-- The Topics counter text: shown (after the search filter) / total, mirroring the Quests strip.
local function topicCounterText()
    return #(topicListCache or {}) .. ' / ' .. #allTopics()
end

-- Topics list status strip — same height/font as the Quests strip (`listStatus`), but just the topic
-- count on the right (no hidden-eye group). Inherits the top divider + GRAY textSize-14 counter.
local function topicStatusStrip(listW)
    return {
        name = 'topicStatus',
        type = ui.TYPE.Widget,
        props = { size = v2(listW, STATUS_H) },
        content = ui.content {
            { template = I.MWUI.templates.horizontalLine },   -- top border (y = 0)
            {
                name = 'topicCounter',
                type = ui.TYPE.Text,
                template = I.MWUI.templates.textNormal,
                props = { text = topicCounterText(),
                          textColor = components.GRAY, textSize = 14,
                          position = v2(-2, 0), relativePosition = v2(1, 0.5), anchor = v2(1, 0.5) },
            },
        },
    }
end

-- One clickable topic row (name only, no icon). Selected = white, else default Morrowind text colour
-- (matches the quest list's scheme).
local function topicRow(t, W)
    local id = t.id
    local color = (id == selectedTopic) and components.WHITE or components.fontColors().normal
    return {
        type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, TPC_ROW_H), autoSize = false,
                                       arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(PAD, 0) } },
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = t.name, textColor = color } },
        },
        events = { mouseClick = async:callback(function() selectTopic(id) end) },
    }
end

-- VIRTUALIZED list body: build only the rows visible in the viewport (+ a small buffer), preceded by a
-- single tall spacer that reserves the height of the rows above. The inner Flex is offset by -scroll like
-- any scroll pane, so with the spacer the visible rows land at their true positions — but the widget count
-- stays ~constant (≈ viewport rows) no matter how many thousand topics exist. The scrollbar still reflects
-- the FULL height via `topicLContentH` (set by the caller). `topics` is the sorted+filtered list.
local function buildTopicSlice(topics, offset, viewH, W)
    local n = #topics
    local firstVisible = math.floor((offset or 0) / TPC_ROW_H) + 1          -- 1-based topmost visible row
    local first = math.max(1, firstVisible - VLIST_BUFFER)
    local last = math.min(n, firstVisible + math.ceil(viewH / TPC_ROW_H) + VLIST_BUFFER)
    local nodes = {}
    if first > 1 then nodes[#nodes + 1] = { props = { size = v2(0, (first - 1) * TPC_ROW_H) } } end
    for i = first, last do nodes[#nodes + 1] = topicRow(topics[i], W) end
    return nodes
end

-- util.color -> "RRGGBB" for inline MyGUI colour codes (#RRGGBB) that colour a span inside one Text.
local function colorHex(c)
    local v = c:asRgb()
    return ('%02X%02X%02X'):format(
        math.floor(v.x * 255 + 0.5), math.floor(v.y * 255 + 0.5), math.floor(v.z * 255 + 0.5))
end

-- RIGHT: selected topic -> name title + its distinct conversation lines (speaker label + text). `topics`
-- is the UNFILTERED list (the detail survives an active search). Sets topicRContentH.
local function buildTopicDetailNodes(topics, W)
    local sel
    for _, t in ipairs(topics) do if t.id == selectedTopic then sel = t; break end end
    if not sel then
        topicRContentH = ROW_H
        vitems.topicR = { { node = components.textLine(l10n('topic_none_selected')), h = ROW_H } }
        return
    end
    local nodes, h = {}, 0
    local function push(node, height) nodes[#nodes + 1] = { node = node, h = height }; h = h + height end
    push(components.header(sel.name), TITLE_H)
    push({ props = { size = v2(0, PAD) } }, PAD)
    -- Speaker name on its own line (brown, LABEL_COLOR), then the line text below it. Consecutive lines
    -- from the SAME speaker collapse under a single name label -- the name is only re-printed when the
    -- speaker changes. MyGUI parses #RRGGBB codes inside Text and getTopicLines strips '#', so the inline
    -- colour code on the name is safe.
    local brownHex = colorHex(components.LABEL_COLOR)
    -- Newest line first, mirroring the quest detail's reversed iteration. Topic entries carry no timestamp
    -- (PlayerJournalTopicEntry is only text/actor), so true recency sorting isn't possible -- we reverse the
    -- engine's natural accumulation order (oldest -> newest). Grouping is over THIS display order, so
    -- "consecutive" means adjacent as shown.
    local lines = I.QuestmanData.getTopicLines(sel.id)
    local prevActor = nil
    for i = #lines, 1, -1 do
        local ln = lines[i]
        local actor, raw = ln.actor or '', ln.text or ''
        if actor ~= '' and actor ~= prevActor then
            if prevActor ~= nil then push({ props = { size = v2(0, 6) } }, 6) end   -- breathing room before a new speaker
            push(components.paragraph(('#%s%s:'):format(brownHex, actor), W), uiScroll.estimateTextHeight(actor .. ':', W) + 2)
        end
        push(components.paragraph(raw, W), uiScroll.estimateTextHeight(raw, W) + 2)
        push({ props = { size = v2(0, 4) } }, 4)   -- gap between lines
        prevActor = actor
    end
    -- "Related topics": the other accumulated topics this one hyperlinks to (@keyword# in the raw text).
    -- OpenMW can't make a sub-span of wrapped text clickable, so we surface the links as a list of
    -- clickable rows below the conversation instead of highlighting them in place.
    local links = I.QuestmanData.getTopicLinks(sel.id)
    if #links > 0 then
        push({ props = { size = v2(0, PAD) } }, PAD)
        push(components.subtitle(l10n('related_topics')), TITLE_H)
        for _, lk in ipairs(links) do
            local id = lk.id
            push({
                type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, TPC_ROW_H), autoSize = false,
                                               arrange = ui.ALIGNMENT.Center },
                content = ui.content {
                    components.link(lk.name, function() selectTopic(id) end),
                },
            }, TPC_ROW_H)
        end
    end
    topicRContentH = h
    vitems.topicR = nodes
end

-- The Topics-page search row (no funnel): [margin][search box grow]. Mirrors the Quests search box; its
-- textChanged does a PARTIAL list refresh (refreshTopicList) so the field keeps keyboard focus.
local function buildTopicSearchRow(listW)
    local PH = l10n('search_placeholder')
    local input
    input = {
        name = 'topicSearchInput', template = I.MWUI.templates.textEditLine,
        props = {
            text = (topicQuery == '') and PH or topicQuery,
            textColor = (topicQuery == '') and components.GRAY or components.WHITE,
            relativeSize = v2(1, 0), size = v2(-12, 0), position = v2(6, 0),
            relativePosition = v2(0, 0.5), anchor = v2(0, 0.5),
        },
        events = {
            textChanged = async:callback(function(text)
                topicQuery = text
                topicLOffset = 0
                input.props.text = text                       -- write back so update() won't blank it
                input.props.textColor = components.WHITE
                refreshTopicList()
            end),
            focusGain = async:callback(function()
                if topicQuery == '' then
                    input.props.text = ''; input.props.textColor = components.WHITE
                    if menu then pcall(menu.update, menu) end
                end
            end),
            focusLoss = async:callback(function()
                if topicQuery == '' then
                    input.props.text = PH; input.props.textColor = components.GRAY
                    if menu then pcall(menu.update, menu) end
                end
            end),
        },
    }
    return {
        name = 'topicSearchRow', type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(listW, SEARCH_H), autoSize = false, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(ICON_MARGIN, 0) } },
            {
                name = 'topicSearch', type = ui.TYPE.Widget, props = { size = v2(0, SEARCH_H) },
                external = { grow = 1 },
                content = components.framed { input },
            },
        },
    }
end

local function buildTopicsPage(s)
    local all = allTopics()                                -- sorted, UNFILTERED (drives the detail + auto-select)
    local found = false
    for _, t in ipairs(all) do if t.id == selectedTopic then found = true; break end end
    if not found then selectedTopic = all[1] and all[1].id or nil end
    local listW, detailW, listViewH = topicDims(s)
    topicListCache = uiSearch.filter(all, topicQuery, { searchEntries = false })
    topicLContentH = #topicListCache * TPC_ROW_H           -- FULL height (drives the scrollbar), not the slice
    topicLOffset = uiScroll.clamp(topicLOffset, topicLContentH, listViewH)
    local listNodes = buildTopicSlice(topicListCache, topicLOffset, listViewH, listW - BAR_W)
    buildTopicDetailNodes(all, detailW - BAR_W)   -- fills vitems.topicR + sets topicRContentH
    topicROffset = uiScroll.clamp(topicROffset, topicRContentH, s.contentH)
    local detailNodes = buildVarSlice(vitems.topicR, topicROffset, s.contentH)   -- visible slice only
    return {
        name = 'topicsPage', type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.innerW, s.contentH), autoSize = false },
        content = ui.content {
            {   -- LEFT column: search (fixed) above the scrollable topic list above the status strip
                name = 'topicLeftCol', type = ui.TYPE.Flex,
                props = { horizontal = false, size = v2(listW, s.contentH), autoSize = false },
                content = ui.content {
                    buildTopicSearchRow(listW),
                    scrollPane('topicList', listW, listViewH, listNodes, topicLContentH, topicLOffset,
                        function(d) topicLOffset = uiScroll.clamp(topicLOffset + d, topicLContentH, listViewH); applyTopicLOffset() end,
                        function() activePane = 'topics'; topicActive = 'left' end),
                    topicStatusStrip(listW),
                },
            },
            makeDivider(function() return topicListFrac end, function(v) topicListFrac = v end,
                        function() settings:set('TopicListWidthPercent', math.floor(topicListFrac * 100 + 0.5)) end),
            scrollPane('topicDetail', detailW, s.contentH, detailNodes, topicRContentH, topicROffset,
                function(d) topicROffset = uiScroll.clamp(topicROffset + d, topicRContentH, s.contentH); applyTopicROffset() end,
                function() activePane = 'topics'; topicActive = 'right' end, SCROLL_SLACK),   -- estimated height -> slack
        },
    }
end

-- Full rebuild of the Topics page (select / resize). Offsets persist.
rebuildTopics = function()
    if not menu then return end
    components.dismissTooltip()   -- rebuild destroys hovered widgets; block a click's trailing tooltip re-show
    local panes = node(PATH.panes)
    -- buildTopicsPage returns the single 'topicsPage' node; ui.content needs a LIST, else the name is
    -- never registered and the pane goes blank (and nodeByPath('topicsPage') later no-ops on scroll).
    if panes then panes.content = ui.content({ buildTopicsPage(sizes()) }) end
    menu:update()
end

-- Partial refresh of ONLY the topic list (for search typing — keeps the search field's focus, unlike a
-- full rebuild which recreates the field).
refreshTopicList = function()
    if not menu then return end
    local s = sizes()
    local listW, _, listViewH = topicDims(s)
    topicListCache = uiSearch.filter(allTopics(), topicQuery, { searchEntries = false })   -- filter the cache, no re-scan
    topicLContentH = #topicListCache * TPC_ROW_H
    topicLOffset = uiScroll.clamp(topicLOffset, topicLContentH, listViewH)
    local nodes = buildTopicSlice(topicListCache, topicLOffset, listViewH, listW - BAR_W)
    local inner = node(PATH.topicListInner)
    if inner then
        inner.content = ui.content(nodes)
        inner.props.position = v2(0, -topicLOffset)
    end
    local bar = node(PATH.topicListBar)
    if bar then
        local trackH = listViewH - 2 * ARROW_H
        local t = uiScroll.thumb(topicLContentH, listViewH, trackH, topicLOffset)
        bar.props = bar.props or {}; bar.props.visible = t.visible
    end
    local counter = node(PATH.topicCounter)
    if counter then counter.props.text = topicCounterText() end   -- shown/total tracks the filter
    menu:update()
end

selectTopic = function(id)
    selectedTopic = id
    topicROffset = 0   -- reset the detail scroll for the newly-selected topic
    I.QuestmanData.setLastViewedTopic(id)
    local t0 = core.getRealTime()
    rebuildTopics()
    dbg(('Selected topic: %s (%.0f ms)'):format(id, (core.getRealTime() - t0) * 1000))
end

-- Select a topic AND make sure the Topics page is showing it — used by "Related topics" links on the
-- quest detail page (cross-page jump). When already on Topics this is just selectTopic; otherwise it
-- switches the page (mirroring the tab() reset) so buildTopicsPage renders with the new selection.
openTopic = function(id)
    selectedTopic = id
    dbg('open topic (link)', id)
    topicROffset = 0
    I.QuestmanData.setLastViewedTopic(id)
    if activePage == 'topics' then
        rebuildTopics()
    else
        activePage = 'topics'
        listOffset = 0
        closeFilterPopup()   -- close the popover; the Quests filter row + selection persist for our return
        switchPage()
    end
end

-- ============================================================================
-- Records page — journal records that aren't real quests (see questProvider.getRecords). Structurally a
-- near-clone of the Topics page: left list + search + status strip, right detail. The detail differs:
-- dated journal entries (newest-first) instead of speaker-tagged conversation lines.
-- ============================================================================

function records.dims(s)
    local listW = math.max(160, math.floor(s.innerW * records.listFrac))
    local detailW = s.innerW - listW - DETAIL_GAP - 2
    return listW, detailW, s.contentH - SEARCH_H - STATUS_H
end

function records.counterText()
    return #(records.listCache or {}) .. ' / ' .. #records.all()
end

function records.statusStrip(listW)
    return {
        name = 'recordStatus',
        type = ui.TYPE.Widget,
        props = { size = v2(listW, STATUS_H) },
        content = ui.content {
            { template = I.MWUI.templates.horizontalLine },
            {
                name = 'recordCounter',
                type = ui.TYPE.Text,
                template = I.MWUI.templates.textNormal,
                props = { text = records.counterText(),
                          textColor = components.GRAY, textSize = 14,
                          position = v2(-2, 0), relativePosition = v2(1, 0.5), anchor = v2(1, 0.5) },
            },
        },
    }
end

-- One clickable record row (title/snippet only, no icon), highlighted when selected.
function records.row(r, W)
    local id = r.id
    local color = (id == records.selected) and components.WHITE or components.fontColors().normal
    return {
        type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, TPC_ROW_H), autoSize = false,
                                       arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(PAD, 0) } },
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = r.name, textColor = color } },
        },
        events = { mouseClick = async:callback(function() records.select(id) end) },
    }
end

-- Virtualized record list body (analog of buildTopicSlice).
function records.buildSlice(list, offset, viewH, W)
    local n = #list
    local firstVisible = math.floor((offset or 0) / TPC_ROW_H) + 1
    local first = math.max(1, firstVisible - VLIST_BUFFER)
    local last = math.min(n, firstVisible + math.ceil(viewH / TPC_ROW_H) + VLIST_BUFFER)
    local nodes = {}
    if first > 1 then nodes[#nodes + 1] = { props = { size = v2(0, (first - 1) * TPC_ROW_H) } } end
    for i = first, last do nodes[#nodes + 1] = records.row(list[i], W) end
    return nodes
end

-- RIGHT: selected record -> title header + its journal entries (newest-first), each preceded by its
-- in-game date (localized via OpenMW's Calendar context). `list` is the UNFILTERED list (the detail
-- survives an active search). Sets records.rContentH.
function records.detailNodes(list, W)
    local sel
    for _, r in ipairs(list) do if r.id == records.selected then sel = r; break end end
    if not sel then
        records.rContentH = ROW_H
        vitems.recordR = { { node = components.textLine(l10n('records_empty')), h = ROW_H } }
        return
    end
    local nodes, h = {}, 0
    local function push(node, height) nodes[#nodes + 1] = { node = node, h = height }; h = h + height end
    push(components.header(sel.name), TITLE_H)
    push({ props = { size = v2(0, PAD) } }, PAD)
    local brownHex = colorHex(components.LABEL_COLOR)
    local dayWord = core.getGMST('sDay')   -- the game's own "Day" word, like the vanilla journal's #{sDay}
    local entries = sel.entries or {}
    for i = #entries, 1, -1 do          -- newest-first, mirroring the quest/topic detail
        local e = entries[i]
        if e.month and e.dayOfMonth then
            -- Matches the vanilla journal timestamp: "<dayOfMonth> <month> (<Day> <elapsed day>)".
            local dateLabel = ('%d %s (%s %d)'):format(
                e.dayOfMonth, records.calendar('month' .. tostring(e.month)), tostring(dayWord), e.day or 0)
            push(components.paragraph(('#%s%s'):format(brownHex, dateLabel), W),
                 uiScroll.estimateTextHeight(dateLabel, W) + 2)
        end
        push(components.paragraph(e.text or '', W), uiScroll.estimateTextHeight(e.text or '', W) + 2)
        push({ props = { size = v2(0, 6) } }, 6)   -- gap between entries
    end
    -- "Related topics": the accumulated topics this record's entries hyperlink to (@keyword#). Clicking
    -- jumps to the Topics page (cross-page), like the quest detail.
    local links = I.QuestmanData.getQuestLinks(sel.id)
    if #links > 0 then
        push({ props = { size = v2(0, PAD) } }, PAD)
        push(components.subtitle(l10n('related_topics')), TITLE_H)
        for _, lk in ipairs(links) do
            local id = lk.id
            push({
                type = ui.TYPE.Flex, props = { horizontal = true, size = v2(W, TPC_ROW_H), autoSize = false,
                                               arrange = ui.ALIGNMENT.Center },
                content = ui.content {
                    components.link(lk.name, function() openTopic(id) end),
                },
            }, TPC_ROW_H)
        end
    end
    records.rContentH = h
    vitems.recordR = nodes
end

-- The Records-page search row. Mirrors the Topics search box; textChanged does a PARTIAL list refresh so
-- the field keeps keyboard focus.
function records.searchRow(listW)
    local PH = l10n('search_placeholder')
    local input
    input = {
        name = 'recordSearchInput', template = I.MWUI.templates.textEditLine,
        props = {
            text = (records.query == '') and PH or records.query,
            textColor = (records.query == '') and components.GRAY or components.WHITE,
            relativeSize = v2(1, 0), size = v2(-12, 0), position = v2(6, 0),
            relativePosition = v2(0, 0.5), anchor = v2(0, 0.5),
        },
        events = {
            textChanged = async:callback(function(text)
                records.query = text
                records.lOffset = 0
                input.props.text = text
                input.props.textColor = components.WHITE
                records.refreshList()
            end),
            focusGain = async:callback(function()
                if records.query == '' then
                    input.props.text = ''; input.props.textColor = components.WHITE
                    if menu then pcall(menu.update, menu) end
                end
            end),
            focusLoss = async:callback(function()
                if records.query == '' then
                    input.props.text = PH; input.props.textColor = components.GRAY
                    if menu then pcall(menu.update, menu) end
                end
            end),
        },
    }
    return {
        name = 'recordSearchRow', type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(listW, SEARCH_H), autoSize = false, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            { props = { size = v2(ICON_MARGIN, 0) } },
            {
                name = 'recordSearch', type = ui.TYPE.Widget, props = { size = v2(0, SEARCH_H) },
                external = { grow = 1 },
                content = components.framed { input },
            },
        },
    }
end

function records.buildPage(s)
    local all = records.all()                               -- sorted, UNFILTERED (drives the detail + auto-select)
    local found = false
    for _, r in ipairs(all) do if r.id == records.selected then found = true; break end end
    if not found then records.selected = all[1] and all[1].id or nil end
    local listW, detailW, listViewH = records.dims(s)
    records.listCache = uiSearch.filter(all, records.query, { searchEntries = true })
    records.lContentH = #records.listCache * TPC_ROW_H
    records.lOffset = uiScroll.clamp(records.lOffset, records.lContentH, listViewH)
    local listNodes = records.buildSlice(records.listCache, records.lOffset, listViewH, listW - BAR_W)
    records.detailNodes(all, detailW - BAR_W)   -- fills vitems.recordR + sets records.rContentH
    records.rOffset = uiScroll.clamp(records.rOffset, records.rContentH, s.contentH)
    local detailNodes = buildVarSlice(vitems.recordR, records.rOffset, s.contentH)
    return {
        name = 'recordsPage', type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.innerW, s.contentH), autoSize = false },
        content = ui.content {
            {
                name = 'recordLeftCol', type = ui.TYPE.Flex,
                props = { horizontal = false, size = v2(listW, s.contentH), autoSize = false },
                content = ui.content {
                    records.searchRow(listW),
                    scrollPane('recordList', listW, listViewH, listNodes, records.lContentH, records.lOffset,
                        function(d) records.lOffset = uiScroll.clamp(records.lOffset + d, records.lContentH, listViewH); records.applyLeft() end,
                        function() activePane = 'records'; records.active = 'left' end),
                    records.statusStrip(listW),
                },
            },
            makeDivider(function() return records.listFrac end, function(v) records.listFrac = v end,
                        function() settings:set('RecordListWidthPercent', math.floor(records.listFrac * 100 + 0.5)) end),
            scrollPane('recordDetail', detailW, s.contentH, detailNodes, records.rContentH, records.rOffset,
                function(d) records.rOffset = uiScroll.clamp(records.rOffset + d, records.rContentH, s.contentH); records.applyRight() end,
                function() activePane = 'records'; records.active = 'right' end, SCROLL_SLACK),
        },
    }
end

-- Full rebuild of the Records page (select / resize). Offsets persist.
function records.rebuild()
    if not menu then return end
    components.dismissTooltip()
    local panes = node(PATH.panes)
    if panes then panes.content = ui.content({ records.buildPage(sizes()) }) end
    menu:update()
end

-- Partial refresh of ONLY the record list (search typing) — keeps the search field's focus.
function records.refreshList()
    if not menu then return end
    local s = sizes()
    local listW, _, listViewH = records.dims(s)
    records.listCache = uiSearch.filter(records.all(), records.query, { searchEntries = true })
    records.lContentH = #records.listCache * TPC_ROW_H
    records.lOffset = uiScroll.clamp(records.lOffset, records.lContentH, listViewH)
    local nodes = records.buildSlice(records.listCache, records.lOffset, listViewH, listW - BAR_W)
    local inner = node(PATH.recordListInner)
    if inner then
        inner.content = ui.content(nodes)
        inner.props.position = v2(0, -records.lOffset)
    end
    local bar = node(PATH.recordListBar)
    if bar then
        local trackH = listViewH - 2 * ARROW_H
        local t = uiScroll.thumb(records.lContentH, listViewH, trackH, records.lOffset)
        bar.props = bar.props or {}; bar.props.visible = t.visible
    end
    local counter = node(PATH.recordCounter)
    if counter then counter.props.text = records.counterText() end
    menu:update()
end

function records.select(id)
    records.selected = id
    records.rOffset = 0   -- reset the detail scroll for the newly-selected record
    local t0 = core.getRealTime()
    records.rebuild()
    dbg(('Selected record: %s (%.0f ms)'):format(tostring(id), (core.getRealTime() - t0) * 1000))
end

-- Content of the 'panes' node, swapped by the active page (keeps the 'panes' node identity so all the
-- existing nodeByPath('main','panes',...) refresh/resize code keeps working on the Quests page).
local function buildPanesContent(s)
    if activePage == 'stats' then
        return { buildStatsPage(s) }
    elseif activePage == 'topics' then
        return { buildTopicsPage(s) }
    elseif activePage == 'records' then
        return { records.buildPage(s) }
    end
    return {
        buildLeft(s),
        makeDivider(function() return questListFrac end, function(v) questListFrac = v end,
                    function() settings:set('QuestListWidthPercent', math.floor(questListFrac * 100 + 0.5)) end),
        buildDetail(s),
    }
end

-- Rebuild the Quests page in place (re-runs buildLeft -> inserts/removes the dropdown, resizes the list
-- body, refreshes the status strip). Used when the filter dropdown opens/closes or a filter is picked.
rebuildQuestPane = function()
    if not menu then return end
    components.dismissTooltip()   -- rebuild destroys hovered widgets; block a click's trailing tooltip re-show
    local panes = node(PATH.panes)
    if panes then panes.content = ui.content(buildPanesContent(sizes())) end
    menu:update()
    refreshList()     -- re-assert scrollbar visibility + status strip at the new list height
    refreshDetail()
end

-- Funnel: show/hide the combo row (hiding it also closes any open popover). The filter itself persists.
toggleFilterRow = function()
    if activePage ~= 'quests' then return end
    filterRowOn = not filterRowOn
    if not filterRowOn then
        selectedFilter = nil   -- closing the row clears the filter: never keep an active-but-hidden filter
        listOffset = 0         -- scope widens back to all quests, so return the list to the top
        closeFilterPopup()
    end
    rebuildQuestPane()
end

-- Apply (opt = an option from getFilterOptions) or clear (opt = nil) the filter, then close the popover.
selectFilter = function(opt)
    selectedFilter = opt and { axis = opt.axis, key = opt.key, label = opt.label } or nil
    closeFilterPopup()
    listOffset = 0
    rebuildQuestPane()   -- combo label + funnel shade + re-filtered list
end

-- Switch to a page (tab) and reset its transient view state. Shared by the tab buttons and the
-- controller shoulder-button cycling (LB/RB).
goToPage = function(page)
    if activePage == page then return end
    activePage = page
    listOffset = 0
    closeFilterPopup()     -- close the popover; the filter row + selection persist across tabs
    switchPage()
end

-- Tab buttons; the active page's button is styled active (blue), like the footer toggle.
local function tabButtons()
    local function tab(page, key)
        return components.button(l10n(key), function() goToPage(page) end, { active = activePage == page })
    end
    -- No left margin: tabs sit flush with the window's left edge (system-window look).
    -- TAB_GAP is the spacing between adjacent tabs; reuse it for any future tab button.
    return {
        tab('quests', 'tab_quests'),
        { props = { size = v2(TAB_GAP, 0) } },
        tab('topics', 'tab_topics'),
        { props = { size = v2(TAB_GAP, 0) } },
        tab('records', 'tab_records'),
        { props = { size = v2(TAB_GAP, 0) } },
        tab('stats', 'tab_stats'),
    }
end

local function buildTabRow(s)
    return {
        name = 'tabRow',
        type = ui.TYPE.Flex,
        props = { horizontal = true, size = v2(s.innerW, TAB_H), autoSize = false,
                  arrange = ui.ALIGNMENT.Center },
        content = ui.content(tabButtons()),
    }
end

switchPage = function()
    if not menu then return end
    components.dismissTooltip()   -- panes get rebuilt below; drop any stats tooltip + block a click's re-show
    local s = sizes()
    local panes = node(PATH.panes)
    if panes then panes.content = ui.content(buildPanesContent(s)) end
    local tabRow = node(PATH.tabRow)
    if tabRow then tabRow.content = ui.content(tabButtons()) end   -- refresh active styling
    refreshFooter()   -- footer controls are quest-only -> show/hide per page
    menu:update()
end

-- The box template autosizes to `main` plus a RZC.border frame on each side; this is the window's true
-- outer size. We size the plain-Widget root to it so the resize strips sit on the real frame edge.
local function outerSize(s)
    return v2(s.innerW + 2 * RZC.border, s.innerH + 2 * RZC.border)
end

local function build()
    local s = sizes()
    local outer = outerSize(s)
    return {
        layer = 'Windows',
        type = ui.TYPE.Widget,   -- plain root sized to the box's outer size; the bordered box is 'frame'
        props = { position = v2(geom.x, geom.y), size = outer },
        content = ui.content {
            {
                name = 'frame',
                type = ui.TYPE.Container,   -- must match the boxTransparentThick template type
                template = I.MWUI.templates.boxTransparentThick,
                content = ui.content {
                    {
                        name = 'main',
                        type = ui.TYPE.Flex,
                        props = { horizontal = false, size = v2(s.innerW, s.innerH), autoSize = false },
                        content = ui.content {
                            buildTitleBar(s),
                            { template = I.MWUI.templates.horizontalLine, external = { stretch = 1 } },
                            buildTabRow(s),
                            { template = I.MWUI.templates.horizontalLine, external = { stretch = 1 } },
                            {
                                name = 'panes',
                                type = ui.TYPE.Flex,
                                props = { horizontal = true, size = v2(s.innerW, s.contentH), autoSize = false },
                                content = ui.content(buildPanesContent(s)),
                            },
                            -- divider above the footer (matches the title divider)
                            { template = I.MWUI.templates.horizontalLine, external = { stretch = 1 } },
                            {
                                -- footer: left-aligned button row + Close button
                                name = 'bottomBar',
                                type = ui.TYPE.Widget,
                                props = { size = v2(s.innerW, FOOTER_H) },
                                content = ui.content {
                                    {
                                        name = 'footerButtons',
                                        type = ui.TYPE.Flex,
                                        props = { horizontal = true, arrange = ui.ALIGNMENT.Center,
                                                  position = v2(PAD, 0), relativePosition = v2(0, 0.5), anchor = v2(0, 0.5) },
                                        content = ui.content(footerButtons()),
                                    },
                                    footerClose(),
                                },
                            },
                        },
                    },
                },
            },
            makeResizeStrip(RZ.L, outer), makeResizeStrip(RZ.R, outer),
            makeResizeStrip(RZ.T, outer), makeResizeStrip(RZ.B, outer),
            makeResizeStrip(RZ.TL, outer), makeResizeStrip(RZ.TR, outer),
            makeResizeStrip(RZ.BL, outer), makeResizeStrip(RZ.BR, outer),
        },
    }
end

-- ---- refresh (named-node + update, no full rebuild) ------------------------
refreshList = function()
    if not menu then return end
    local s = sizes()
    local inner = node(PATH.listInner)
    if inner then
        inner.content = ui.content(buildRows(s))
        listOffset = uiScroll.clamp(listOffset, listContentH, s.listViewH)
        inner.props.position = v2(0, -listOffset)
    end
    local bar = node(PATH.listBar)
    if bar then
        local t = listThumb(s)
        bar.content = t.content
        bar.props.visible = t.props.visible   -- visibility must re-evaluate, not stay frozen at build
    end
    local cnt = node(PATH.listCounter)
    if cnt then cnt.props.text = #currentOrder .. ' / ' .. listTotal end
    local sl = node(PATH.statusLeft)
    if sl then sl.content = ui.content(statusLeftNodes()) end   -- hidden eye+count
    menu:update()
end

refreshDetail = function()
    if not menu then return end
    local s = sizes()
    local inner = node(PATH.detailInner)
    if inner then
        buildDetailContent(s)   -- refills vitems.detail + recomputes detailContentH for the new quest
        detailOffset = uiScroll.clamp(detailOffset, detailContentH, s.detailViewH)
        inner.content = ui.content(buildVarSlice(vitems.detail, detailOffset, s.detailViewH))   -- visible slice only
        inner.props.size = v2(s.detailVpW, detailContentH)   -- keep the explicit height in step (see buildDetail)
        inner.props.position = v2(0, DETAIL_DY - detailOffset)
    end
    local bar = node(PATH.detailBar)
    if bar then
        local t = detailThumb(s)
        bar.content = t.content
        bar.props.visible = t.props.visible
    end
    menu:update()
end

refreshFooter = function()
    if not menu then return end
    local fb = node(PATH.footer)
    if fb then fb.content = ui.content(footerButtons()) end
    pcall(menu.update, menu)
end

applyListOffset = function()
    if not menu then return end
    local s = sizes()
    listOffset = applyScrollPane {
        offset = listOffset, contentH = listContentH, viewH = s.listViewH, el = menu, find = nodeByPath,
        inner = PATH.listInner, thumb = PATH.listThumb,
        renderSlice = function(off, vh) return buildQuestSlice(currentOrder, off, vh) end,   -- virtualized
    }
end

applyDetailOffset = function()
    if not menu then return end
    local s = sizes()
    detailOffset = applyScrollPane {
        offset = detailOffset, contentH = detailContentH, viewH = s.detailViewH, el = menu, find = nodeByPath,
        topMargin = DETAIL_DY,
        inner = PATH.detailInner, thumb = PATH.detailThumb,
        renderSlice = function(off, vh) return buildVarSlice(vitems.detail, off, vh) end,   -- virtualized
    }
end

applyStatsOffset = function()
    if not menu then return end
    statsOffset = applyScrollPane {
        offset = statsOffset, contentH = statsContentH, viewH = sizes().contentH, el = menu, find = nodeByPath,
        inner = PATH.statsInner, thumb = PATH.statsThumb,
    }
end

-- Topics page scroll. The two panes differ: the LEFT list lives inside 'topicLeftCol' (under the search
-- box) with a reduced viewport; the RIGHT detail is a direct child at full height. Paths include the
-- '…Vp' viewport level (the bug that made content not move was skipping it).
local function applyTopicPane(which)
    if not menu then return end
    local s = sizes()
    if which == 'left' then
        local listW, _, viewH = topicDims(s)
        topicLOffset = applyScrollPane {
            offset = topicLOffset, contentH = topicLContentH, viewH = viewH, el = menu, find = nodeByPath,
            inner = PATH.topicListInner, thumb = PATH.topicListThumb,
            renderSlice = function(off, vh) return buildTopicSlice(topicListCache or {}, off, vh, listW - BAR_W) end,
        }
    else
        topicROffset = applyScrollPane {
            offset = topicROffset, contentH = topicRContentH, viewH = s.contentH, el = menu, find = nodeByPath,
            inner = PATH.topicDetailInner, thumb = PATH.topicDetailThumb,
            renderSlice = function(off, vh) return buildVarSlice(vitems.topicR, off, vh) end,   -- virtualized
        }
    end
end
applyTopicLOffset = function() applyTopicPane('left') end
applyTopicROffset = function() applyTopicPane('right') end

-- Records page scroll (mirror of applyTopicPane).
function records.applyPane(which)
    if not menu then return end
    local s = sizes()
    if which == 'left' then
        local listW, _, viewH = records.dims(s)
        records.lOffset = applyScrollPane {
            offset = records.lOffset, contentH = records.lContentH, viewH = viewH, el = menu, find = nodeByPath,
            inner = PATH.recordListInner, thumb = PATH.recordListThumb,
            renderSlice = function(off, vh) return records.buildSlice(records.listCache or {}, off, vh, listW - BAR_W) end,
        }
    else
        records.rOffset = applyScrollPane {
            offset = records.rOffset, contentH = records.rContentH, viewH = s.contentH, el = menu, find = nodeByPath,
            inner = PATH.recordDetailInner, thumb = PATH.recordDetailThumb,
            renderSlice = function(off, vh) return buildVarSlice(vitems.recordR, off, vh) end,
        }
    end
end
function records.applyLeft() records.applyPane('left') end
function records.applyRight() records.applyPane('right') end

-- Resize: update sizes in place (keep node identity so the drag keeps mouse capture).
applySizes = function()
    if not menu then return end
    local s = sizes()
    local function setSize(size, path)
        local n = node(path)
        if n then n.props = n.props or {}; n.props.size = size end
    end
    setSize(v2(s.innerW, s.innerH), PATH.main)
    setSize(v2(s.innerW, TITLE_H), PATH.titlebar)
    setSize(v2(s.innerW, TAB_H), PATH.tabRow)
    setSize(v2(s.innerW, s.contentH), PATH.panes)
    setSize(v2(s.innerW, FOOTER_H), PATH.bottomBar)
    setSize(v2(s.listW, s.contentH), PATH.left)
    setSize(v2(s.listW, s.listViewH), PATH.leftBody)
    setSize(v2(s.listW, STATUS_H), PATH.listStatus)   -- status strip follows the pane width
    setSize(v2(s.listVpW, s.listViewH), PATH.listVp)
    setSize(v2(s.detailW, s.detailViewH), PATH.detail)
    setSize(v2(s.detailVpW, s.detailViewH), PATH.detailVp)
    setSize(v2(BAR_W, s.listViewH), PATH.listBar)
    setSize(v2(BAR_W, s.detailViewH), PATH.detailBar)
    -- search row widens with the pane; the search box (grow) + input (relativeSize) follow automatically
    setSize(v2(s.listW, SEARCH_H), PATH.searchRow)
    -- Topics columns resize in place too, so a Topics divider drag can move them without a full panes
    -- rebuild (which would destroy the divider handle mid-drag). No-op on other pages (nodes absent).
    local topicListW, topicDetailW = topicDims(s)
    setSize(v2(topicListW, s.contentH), PATH.topicLeftCol)
    setSize(v2(topicDetailW, s.contentH), PATH.topicDetail)
    -- root Widget + resize strips follow the outer size (root is plain-Widget; the 'frame' box autosizes to
    -- main). The strips hug the real window edges/corners via explicit geom (relativeSize won't resolve here).
    local outer = outerSize(s)
    menu.layout.props.size = outer
    for _, dir in ipairs(RZC.all) do
        local strip = node(PATH[RZC.name[dir]])
        if strip then
            local pos, size = stripRect(dir, outer.x, outer.y)
            strip.props = strip.props or {}
            strip.props.position = pos
            strip.props.size = size
        end
    end
    closeFilterPopup()   -- the popover's position is window-relative; drop it rather than chase the resize
    -- Stats/Topics rebuild their scroll panes on resize; the Quests page resizes in place EXCEPT
    -- when the combo row is shown (its width isn't covered by the setSize calls above).
    -- Skip the rebuild while dragging the divider: a rebuild recreates the divider handle and kills its
    -- mouse capture mid-drag. The in-place setSize calls above move everything; a full reflow runs on release.
    if not dividerDrag and (activePage == 'stats' or activePage == 'topics' or activePage == 'records' or (activePage == 'quests' and filterRowOn)) then
        components.dismissTooltip()                  -- rows are rebuilt below; block a click's tooltip re-show
        local panes = node(PATH.panes)   -- rebuild the page at the new size
        if panes then panes.content = ui.content(buildPanesContent(s)) end
    end
    menu:update()
    -- reflow contents to the new widths
    refreshList()
    refreshDetail()
end

-- ---- lifecycle: open / close / UI modes ------------------------------------
-- Everything that opens, closes, or drives the window's UI mode lives in this one section
-- (geometry helpers, createMenu/destroyMenu, open/close/toggle, onUiModeChanged, the Journal
-- override). The contract:
--  * ONE teardown path: onUiModeChanged destroys the menu + restores pinned HUD windows. Every
--    close trigger (X / Close / right-click / controller-B / Escape / open-key) merely drops our
--    'Interface' mode and lets that handler do the rest — no trigger destroys the menu itself.
--  * open() is guarded: it refuses to open while ANY other UI mode is active. setMode drops all
--    modes, so opening over a book/dialogue/container would stomp that mode and leave a visible-
--    but-unpaused window.
--  * The Journal override is the exception: the engine owns the 'Journal' mode and its
--    registerWindow show/hideFn build/destroy the element, so onUiModeChanged skips override closes.
--  * Persistence: savePos -> disk (windowStore 'pos'); saveSize -> settings (WindowWidth/Height).
--
-- Logical (UI-scaled) screen size. Widget coords are in logical pixels (engine applies the GUI
-- scaling factor), and a layer's `.size` is the logical view size — the SAME space as our widgets.
-- ui.screenSize() returns PHYSICAL resolution, so do NOT use it for layout (would break at scale!=1).
-- Forward-declared (top of file) so buildFilterPopup, defined earlier, can use it for the backdrop size.
logicalScreen = function()
    local ok, size = pcall(function()
        for _, layer in ipairs(ui.layers) do
            if layer.name == 'Windows' and layer.size then return layer.size end
        end
        return nil
    end)
    if ok and size then return size end
    return ui.screenSize() -- fallback (assumes scale == 1)
end

local function centerWindow()
    local screen = logicalScreen()
    if screen then
        geom.w = math.min(geom.w, screen.x - 40)
        geom.h = math.min(geom.h, screen.y - 40)
        geom.x = math.floor((screen.x - geom.w) / 2)
        geom.y = math.floor((screen.y - geom.h) / 2)
        dbg('logical screen', screen.x, screen.y, '-> window', geom.w, geom.h, 'at', geom.x, geom.y)
    end
end

-- keep geometry within the screen and at least the minimum size (e.g. after a resolution change)
local function clampGeom()
    local screen = logicalScreen()
    if not screen then return end
    geom.w = math.max(MIN_W, math.min(geom.w, screen.x))
    geom.h = math.max(MIN_H, math.min(geom.h, screen.y))
    geom.x = math.max(0, math.min(geom.x, screen.x - geom.w))
    geom.y = math.max(0, math.min(geom.y, screen.y - geom.h))
end

-- SIZE lives in the settings (Width/Height shown + editable there); POSITION is remembered on disk.
savePos = function()
    windowStore:set('pos', { x = math.floor(geom.x), y = math.floor(geom.y) })
end
saveSize = function()
    settings:set('WindowWidth', math.floor(geom.w))   -- keeps the settings page in sync
    settings:set('WindowHeight', math.floor(geom.h))
end

-- Build the menu element. Does NOT touch UI modes -- the caller owns the mode. Shared by the standalone
-- open() (which enters our own 'Interface' mode) and the Journal-override showFn (where the engine already
-- holds the 'Journal' mode). Idempotent.
local function createMenu()
    if menu then return end
    local openStart = core.getRealTime()   -- PERF (temp): time the whole open (build + first-time scans + refresh)
    -- Fresh data per open: drop the data layer's per-open cache so this open re-reads the journal (new
    -- entries / quests / topics appear). Within this open, every consumer reuses the newly-built results.
    I.QuestmanData.invalidate()
    geom.w = settings:get('WindowWidth') or geom.w
    geom.h = settings:get('WindowHeight') or geom.h
    -- list/detail split fractions come from the % settings (clamped to the divider's drag range)
    local function fracFromPct(pct, dflt)
        return math.max(DIVIDER_MIN_FRAC, math.min(DIVIDER_MAX_FRAC, (pct or dflt) / 100))
    end
    questListFrac = fracFromPct(settings:get('QuestListWidthPercent'), 40)
    topicListFrac = fracFromPct(settings:get('TopicListWidthPercent'), 30)
    records.listFrac = fracFromPct(settings:get('RecordListWidthPercent'), 30)
    local pos = windowStore:get('pos')
    if pos and pos.x then   -- remembered position
        geom.x, geom.y = pos.x, pos.y
        clampGeom()
    else                    -- no remembered position (or reset): centre
        centerWindow()
    end
    selectedId = selectedId or I.QuestmanData.getLastViewed()
    selectedTopic = selectedTopic or I.QuestmanData.getLastViewedTopic()
    topicListCache = nil   -- drop the filtered view; the full topic list is re-read via the data cache (invalidated above)
    listOffset, detailOffset = 0, 0
    filterOffset = 0   -- reset only the popover scroll; the filter row + selection persist across close/open
    closeFilterPopup()
    menu = ui.create(build())
    -- assert both scrollbars' visibility deterministically (build sets it, but this guards the
    -- flaky "only one bar shows" case by re-evaluating both right after open)
    refreshList()
    local detailStart = core.getRealTime()
    refreshDetail()
    dbg(('Quest selected: %s (%.0f ms)'):format(tostring(selectedId), (core.getRealTime() - detailStart) * 1000))
    dbg(('Window opened (%.0f ms). %s tab'):format((core.getRealTime() - openStart) * 1000, (activePage:gsub('^%l', string.upper))))
    if not diagnosticsLogged then   -- once per session: a snapshot to help debug player installs
        diagnosticsLogged = true
        local phys, logi = ui.screenSize(), logicalScreen()   -- physical vs logical (UI-scaled) resolution
        local env = { screenW = phys.x, screenH = phys.y, logicalW = logi.x, logicalH = logi.y }
        local quests = lastQuests   -- reuse the list this build just produced (huge saves: skip a 2nd scan)
        -- Deferred OFF the open frame: getTopics()/buildCatalog() are heavy on 3000+ quest saves and the log
        -- dump isn't needed to show the window. Fires on the next simulation step, so opening stays snappy.
        async:newUnsavableSimulationTimer(0, function()
            I.QuestmanData.logDiagnostics(env, quests)
        end)
    end
end

-- Destroy the menu element. Does NOT touch UI modes. Idempotent.
local function destroyMenu()
    if not menu then return end
    components.dismissTooltip()   -- the tooltip is a separate element; it won't die with the menu (+ block re-show)
    closeFilterPopup()         -- so is the options popover
    menu:destroy()
    menu = nil
end

local function open()
    if menu then return end
    -- Only open from a clean game state. setMode drops ALL active modes, so opening over another UI mode
    -- (book, dialogue, container, ...) would stomp that mode's stack and leave a half-torn-down, unpaused
    -- state (questman visible but the game running). Require no other UI mode to be active first.
    if I.UI.getMode() ~= nil then return end
    I.UI.setMode('Interface', { windows = {} })
    createMenu()
end

local function close()
    if not menu then return end
    -- Only drop our mode here; the actual destroy + pinned-window restore happen in onUiModeChanged, the
    -- single teardown path shared by every close trigger (X / Close / right-click / controller-B / Escape).
    I.UI.removeMode(overrideMenuOpen and 'Journal' or 'Interface')
    dbg('menu closing')
end

local function toggle()
    if menu then close() else open() end
end

-- Single teardown path for every non-override close (X / Close / right-click / controller-B / Escape /
-- open-key): the trigger only drops our 'Interface' mode; the destroy + pinned-window restore happen here.
-- Under the Journal override the engine owns the mode and registerWindow's hideFn does teardown, so skip
-- (else we'd destroy the menu the instant 'Journal' is entered, and double-destroy on exit).
-- Wired to the engine via eventHandlers.UiModeChanged at the bottom of the file.
local function onUiModeChanged(data)
    if not menu or overrideMenuOpen then return end
    if data and data.newMode == 'Interface' then return end   -- still our own mode: nothing to do
    destroyMenu()
    dbg('menu closed by UiModeChanged ->', tostring(data and data.newMode))
    -- open() hid the HUD/pinned windows via setMode('Interface', {windows={}}). The engine only restores
    -- hidden windows on mode ENTER (updateHidden), never when the stack empties on exit -- so when we drop
    -- back to gameplay (newMode == nil) the pinned map would stay hidden ("open inventory to get it back").
    -- Re-assert Interface once (updateHidden re-enables everything we hid) then drop it. If another mode
    -- took over instead, its own enter already handled windows, so we don't re-assert.
    if not (data and data.newMode) then
        I.UI.setMode('Interface')
        -- Drop with setMode() (= _setUiModeStack({})), NOT removeMode('Interface'). By the time this
        -- event fires, the built-in ui.lua's local modeStack is already empty, and removeMode reads that
        -- local table -- so removeMode('Interface') finds nothing to remove and no-ops, leaving the
        -- re-asserted Interface (the inventory/map/char screen) stuck open on every close.
        I.UI.setMode()
    end
end

-- Journal override (opt-in, needs a restart -- registerWindow disables the native Journal window at load).
-- When enabled, opening the vanilla Journal shows questman instead: the engine enters the 'Journal' UI
-- mode and calls showFn/hideFn, so we only build/destroy our element -- the engine owns the mode. The
-- keyboard/controller open bindings still work independently (they use our own 'Interface' mode).
if forced(FORCE_OVERRIDE_JOURNAL, settings:get('OverrideJournal')) then
    I.UI.registerWindow('Journal',
        function() overrideMenuOpen = true; createMenu() end,   -- showFn: engine is in Journal mode already
        function() destroyMenu(); overrideMenuOpen = false end) -- hideFn: engine leaving Journal mode
end

-- Move the list selection by `delta` rows (keyboard up/down), auto-scrolling to keep it on screen.
local function selectByOffset(delta)
    if not menu or #currentOrder == 0 then return end
    local idx
    for i, q in ipairs(currentOrder) do
        if q.id == selectedId then idx = i; break end
    end
    if not idx then
        idx = (delta > 0) and 1 or #currentOrder            -- nothing selected yet -> jump to an end
    else
        idx = math.max(1, math.min(#currentOrder, idx + delta))
    end
    local q = currentOrder[idx]
    if not q then return end
    selectedId = q.id
    I.QuestmanData.setLastViewed(q.id)
    detailOffset = 0
    -- keep the selected row within the viewport
    local s = sizes()
    local top, bottom = (idx - 1) * ROW_H, idx * ROW_H
    if top < listOffset then listOffset = top
    elseif bottom > listOffset + s.listViewH then listOffset = bottom - s.listViewH end
    refreshList()   -- clamps + applies listOffset and updates the highlight
    refreshDetail()
end

-- Topics-page twin of selectByOffset: move the selected topic up/down the (filtered) left list, keep it
-- in view, and rebuild. Topics live in their own state (selectedTopic / topicListCache / TPC_ROW_H), so
-- arrow keys need this separate path.
local function selectTopicByOffset(delta)
    if not menu then return end
    local list = topicListCache
    if not list or #list == 0 then return end
    local idx
    for i, t in ipairs(list) do
        if t.id == selectedTopic then idx = i; break end
    end
    if not idx then
        idx = (delta > 0) and 1 or #list                    -- nothing selected yet -> jump to an end
    else
        idx = math.max(1, math.min(#list, idx + delta))
    end
    local t = list[idx]
    if not t then return end
    selectedTopic = t.id
    topicROffset = 0   -- reset the detail scroll for the newly-selected topic
    I.QuestmanData.setLastViewedTopic(t.id)
    -- keep the selected row within the left-list viewport
    local _, _, listViewH = topicDims(sizes())
    local top, bottom = (idx - 1) * TPC_ROW_H, idx * TPC_ROW_H
    if top < topicLOffset then topicLOffset = top
    elseif bottom > topicLOffset + listViewH then topicLOffset = bottom - listViewH end
    rebuildTopics()
end

-- Records-page twin of selectTopicByOffset: move the selection up/down the (filtered) left list, keep it
-- in view, and rebuild.
function records.selectByOffset(delta)
    if not menu then return end
    local list = records.listCache
    if not list or #list == 0 then return end
    local idx
    for i, r in ipairs(list) do
        if r.id == records.selected then idx = i; break end
    end
    if not idx then
        idx = (delta > 0) and 1 or #list
    else
        idx = math.max(1, math.min(#list, idx + delta))
    end
    local r = list[idx]
    if not r then return end
    records.selected = r.id
    records.rOffset = 0
    local _, _, listViewH = records.dims(sizes())
    local top, bottom = (idx - 1) * TPC_ROW_H, idx * TPC_ROW_H
    if top < records.lOffset then records.lOffset = top
    elseif bottom > records.lOffset + listViewH then records.lOffset = bottom - listViewH end
    records.rebuild()
end

-- ---- input -----------------------------------------------------------------
local function onKeyPress(key)
    local openKey = forced(FORCE_OPEN_KEY, settings:get('OpenMenuKey')) or input.KEY.X
    if key.code == openKey then
        -- TODO: ignore when the search box has keyboard focus (avoid closing while typing the key).
        toggle()
    -- Escape is deliberately NOT handled here. The engine's own game-menu action fires on Escape and calls
    -- exitCurrentGuiMode, which drops our 'Interface' mode; onUiModeChanged then tears us down (and, when the
    -- popover is open, destroyMenu closes it too). If we emptied the mode stack in Lua instead, it would run
    -- *before* that engine action, which would then see no active GUI mode and pop up the main menu.
    elseif menu and key.code == input.KEY.DownArrow then
        if activePage == 'topics' then selectTopicByOffset(1)
        elseif activePage == 'records' then records.selectByOffset(1)
        elseif activePage == 'quests' then selectByOffset(1) end
    elseif menu and key.code == input.KEY.UpArrow then
        if activePage == 'topics' then selectTopicByOffset(-1)
        elseif activePage == 'records' then records.selectByOffset(-1)
        elseif activePage == 'quests' then selectByOffset(-1) end
    elseif menu and key.code == input.KEY.Delete then
        if activePage == 'quests' and selectedId then   -- toggle hide on the selected quest
            I.QuestmanData.toggleHide(selectedId)
            refreshList()     -- re-filter + markers + the "Hidden: X" label
            refreshDetail()   -- update the eye button state
        end
    elseif menu and key.code == input.KEY.O and I.QuestmanDev then
        -- DEV (dev_features only; absent in a shipped build -> inert): complete EVERY quest, to stress-test
        -- the menu with a full journal. Gated to menu-open so a stray "O" in play can't nuke a save.
        -- Invalidate the per-open cache so the newly-completed quests appear immediately.
        I.QuestmanDev.completeAll()
        I.QuestmanData.invalidate()
        refreshList()
        refreshDetail()
    elseif menu and key.code == input.KEY.P and I.QuestmanDev and activePage == 'quests' and selectedId then
        -- DEV (dev_features only; inert in a shipped build): toggle the selected quest Finished/Unfinished to
        -- test the active/completed display. Flip the WHOLE name-group (all member ids share one log).
        local q = I.QuestmanData.getQuest(selectedId)
        if q then
            I.QuestmanDev.setFinished(q.ids or { q.id }, not q.completed)
            I.QuestmanData.invalidate()
            refreshList()
            refreshDetail()
        end
    end
end

-- Minimal controller support: map a few buttons onto the SAME actions as the keyboard/mouse, so there's
-- no separate interaction model to maintain. Deliberately NOT handled here: A (stays the engine's
-- gamepad-cursor left-click) and B (the engine's own exitCurrentGuiMode closes our Interface mode, which
-- our UiModeChanged handler tears down). Sticks, the search box and filters remain cursor-only by design.
local CONTROLLER_PAGES = { 'quests', 'topics', 'records', 'stats' }
local function cycleControllerPage(delta)
    for i, p in ipairs(CONTROLLER_PAGES) do
        if p == activePage then
            goToPage(CONTROLLER_PAGES[(i - 1 + delta) % #CONTROLLER_PAGES + 1])
            return
        end
    end
end

local function onControllerButtonPress(id)
    if id == forced(FORCE_OPEN_BUTTON, settings:get('OpenMenuButton')) then toggle(); return end   -- the bound pad button opens/closes
    if not menu then return end
    local BTN = input.CONTROLLER_BUTTON
    if id == BTN.DPadDown then          -- move selection down (mirrors the Down arrow)
        if activePage == 'topics' then selectTopicByOffset(1)
        elseif activePage == 'records' then records.selectByOffset(1)
        elseif activePage == 'quests' then selectByOffset(1) end
    elseif id == BTN.DPadUp then        -- move selection up (mirrors the Up arrow)
        if activePage == 'topics' then selectTopicByOffset(-1)
        elseif activePage == 'records' then records.selectByOffset(-1)
        elseif activePage == 'quests' then selectByOffset(-1) end
    elseif id == BTN.RightShoulder then cycleControllerPage(1)   -- next tab
    elseif id == BTN.LeftShoulder then cycleControllerPage(-1)   -- previous tab
    elseif id == BTN.Y or id == BTN.X then
        -- Y pins / X hides the selected quest -- Quests page only (Topics/Stats have neither).
        if activePage == 'quests' and selectedId then
            if id == BTN.Y then I.QuestmanData.togglePin(selectedId)
            else I.QuestmanData.toggleHide(selectedId) end
            refreshList()     -- re-filter, re-sort, refresh markers + hidden count
            refreshDetail()   -- update the pin/eye button state
        end
    end
end

local function onMouseWheel(vertical, horizontal)
    if not menu then return end
    if activePage == 'stats' then
        local viewH = sizes().contentH
        statsOffset = uiScroll.clamp(statsOffset - (vertical or 0) * WHEEL_STEP, statsContentH, viewH)
        applyStatsOffset()
        return
    end
    if activePage == 'topics' then
        local s = sizes()
        if topicActive == 'right' then
            topicROffset = uiScroll.clamp(topicROffset - (vertical or 0) * WHEEL_STEP, topicRContentH, s.contentH)
            applyTopicROffset()
        else
            local _, _, viewH = topicDims(s)   -- left list viewport is shorter (search box above it)
            topicLOffset = uiScroll.clamp(topicLOffset - (vertical or 0) * WHEEL_STEP, topicLContentH, viewH)
            applyTopicLOffset()
        end
        return
    end
    if activePage == 'records' then
        local s = sizes()
        if records.active == 'right' then
            records.rOffset = uiScroll.clamp(records.rOffset - (vertical or 0) * WHEEL_STEP, records.rContentH, s.contentH)
            records.applyRight()
        else
            local _, _, viewH = records.dims(s)
            records.lOffset = uiScroll.clamp(records.lOffset - (vertical or 0) * WHEEL_STEP, records.lContentH, viewH)
            records.applyLeft()
        end
        return
    end
    if popupEl then   -- the options popover is open: the wheel scrolls it
        filterOffset = uiScroll.clamp(filterOffset - (vertical or 0) * WHEEL_STEP, filterContentH, popupViewH)
        applyFilterOffset()
        return
    end
    if activePane == 'detail' then
        detailOffset = uiScroll.clamp(detailOffset - (vertical or 0) * WHEEL_STEP, detailContentH, sizes().detailViewH)
        applyDetailOffset()
    else
        listOffset = uiScroll.clamp(listOffset - (vertical or 0) * WHEEL_STEP, listContentH, sizes().listViewH)
        applyListOffset()
    end
end

return {
    engineHandlers = {
        onKeyPress = onKeyPress,
        onControllerButtonPress = onControllerButtonPress,
        onMouseWheel = onMouseWheel,
        -- Persist the quest-list view state per save (data-layer state lives in questProvider; these are
        -- purely UI): the "show completed + hidden" toggle, the active add-on/category/faction filter, and
        -- whether the filter combo row is revealed. Restored on load so the list looks as the player left it.
        -- (The list/detail split fractions live in cross-save settings now -- QuestListWidthPercent /
        -- TopicListWidthPercent -- not here; see createMenu + the divider's saveFrac.)
        onSave = function()
            return { showAll = showAll, selectedFilter = selectedFilter, filterRowOn = filterRowOn }
        end,
        onLoad = function(data)
            if not data then return end
            showAll = data.showAll == true
            selectedFilter = data.selectedFilter   -- { axis, key, label } or nil
            filterRowOn = data.filterRowOn == true
        end,
    },
    eventHandlers = {
        UiModeChanged = onUiModeChanged,
    },
}
