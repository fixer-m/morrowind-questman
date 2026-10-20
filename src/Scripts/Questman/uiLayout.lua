-- questman: layout constants for ui.lua (sizes, gaps, row heights, icon paths). Pure data, no engine deps.
-- WHY a module: ui.lua's main chunk hit Lua 5.1's 200-local cap; as one table these take a single slot
-- (`L`) there instead of ~45. Values are fixed for the session -- mutable layout state stays in ui.lua.

local M = {}

M.PAD = 8
M.TITLE_H = 20
M.TAB_H = 28     -- page-tab band (Quests / Topics / Journal / Progress), under the title
M.TAB_GAP = 4    -- spacing between adjacent page tabs (tabs sit flush with the left edge)
M.SEARCH_H = 24   -- search row height (= the funnel / sort button height)
M.BAR_W = 16     -- scrollbar width
M.ARROW_H = 19   -- arrow-zone height = BAR_W + scrollbar GAP(3), so the arrow box is square (see
                 -- uiComponents M.scrollbar); the thumb travels between the two zones [ARROW_H, h-ARROW_H]
M.ROW_H = 28
-- Tightened ~one-text-line row pitch (no inter-row gap): the topic list (long 877+ index) and the
-- "Related topics" link rows on both detail panes. Default font kept; 18px ≈ the line height, which is
-- the floor before glyphs start to clip.
M.TPC_ROW_H = 18
M.VLIST_BUFFER = 4   -- virtualized lists (quests + topics): rows rendered above/below the viewport
M.STATUS_H = 18      -- slim status strip under the list (holds the shown/total counter)
M.ICON_SZ = 24       -- quest icon size AND the funnel / sort button width (so the funnel lines up with the icons)
M.ICON_MARGIN = 2    -- left margin from the pane border to the icon
M.FOOTER_H = 36      -- bottom button bar height (fits a standard button + margins)
M.FOOTER_GAP = 6     -- Close button inset from the footer's right edge (≈ its top/bottom gap)
M.MIN_W = 520
M.MIN_H = 320
M.DETAIL_GAP = 4    -- gap before the detail pane; smaller than PAD so detail text sits a few px further left
M.DETAIL_DY = 2     -- detail content nudged down this many px
M.ENTRY_GAP = 6     -- vertical gap between journal entries (quest detail, Journal feed)
M.LINE_ROW = 20     -- content-height allowance for a SINGLE-line detail row (category/giver/subtitle);
                    -- ROW_H is the list-row height and over-reserves here -> spurious scrollbar
M.SCROLL_SLACK = 16 -- detail/topic panes: hide the scrollbar unless content overflows by more than this
                    -- (their height is estimated; absorbs a few px of rounding so a fitting quest = no bar)
M.WHEEL_STEP = M.ROW_H * 2

-- Row markers shown before the name. A hidden quest shows the crossed-eye; else a pinned quest shows
-- the star; otherwise no marker (title stays flush against the quest icon).
M.PIN_ICON = 'Icons/questman/ui_star.dds'
M.HIDDEN_ICON = 'Icons/questman/ui_hidden.dds'

-- Filtering: the funnel left of the search box toggles a thin FilterDropDown combo row under it; clicking
-- THAT opens the options as a floating popover (a separate Element on an interactive layer above the
-- window) that overlays the list.
M.FILTER_ICON = 'Icons/questman/ui_filter.dds'
-- Sort button next to the funnel; opens the sort popover (the list orders) under it.
M.SORT_ICON = 'Icons/questman/ui_sorting.dds'
M.FILTER_ARROW = 'textures/omw_menu_scroll_down.dds'   -- ⇓ on the combo box (the font has no chevron glyph)
M.COMBO_H = M.SEARCH_H      -- the FilterDropDown combo-box row height = the search box height (match)
M.FILTER_POPUP_H = 220    -- max height of the floating options popover (it scrolls past this)
M.FILTER_ROW_H = 17       -- option row height in the filter and sort popovers (tight)
M.FILTER_HDR_H = 19       -- section-header row height in the popover
M.SORT_POPUP_W = 230      -- the sort popover's width: fits its longest option ("По фракциям и категориям")
M.STATUS_EYE = 12         -- small crossed-eye icon on the status strip (smaller than the 14px row marker)
M.POPUP_LAYER = 'QuestmanFilterPopup'   -- interactive layer (above 'Windows') hosting the filter / sort popover
M.DIV = 2                 -- approx height of a horizontalLine divider (for popover y-placement math)

-- Journal page (one chronological feed in a centered column).
M.JOURNAL_COL_W = 560     -- max text-column width: lines across a whole wide screen are hard to read
M.JOURNAL_BAR_H = 32      -- the mode bar above the feed (tab-height buttons + a little air)
M.JOURNAL_DAY_H = 26      -- a `── date ──` day header row
M.JOURNAL_PAGE = 100      -- entries shown at first and added per load (scrolling to the bottom loads more)

-- Stats page metrics (compact rows; numbers align in a fixed column near the labels). Tunable.
M.STAT_ROW = 28          -- stat row height. Needs >=2px margin around the ICON_SZ row icon: with only 1px
                         -- a non-integer GUI scale rounds the margin away and clips the icon
                         -- (seen on the English install, whose scale differs from the Russian one)
M.STAT_ICON_GAP = 4      -- gap between a row's icon and its label
M.STAT_ICON_ZOOM = 64    -- Stats-page only: hovering a row icon shows it at its NATIVE 64px size (crisp
                        -- 1:1 regardless of GUI scale). This is the icons' real resolution — the max sharp size.
M.STAT_HEADER_H = 24     -- section header row height
M.STAT_VALUE_W = 85      -- right-aligned "N / N" column, tuned snug around a 4-digit "9999 / 9999"
                        -- (heavily modded totals). MW's font is PROPORTIONAL and digits are wide, and the
                        -- box clips, so don't go below what "9999 / 9999" needs or a leading digit gets cut.
M.STAT_LABEL_W = 203     -- label column, tuned tight to the longest localized name ("Восточная Имп.
                        -- Кампания:") so the numbers sit right after it. STATIC — fixed column width (below),
                        -- so labels + numbers stay put regardless of window size. A name that just clips
                        -- still shows in full on hover (tooltip); nudge this up if a real name overflows.
M.STAT_CHECK_W = 22      -- reserve at a row's right edge for the ✓ (small gap + 14px tick + a hair of pad)
M.STAT_COL_GAP = 6       -- horizontal gap between the two static stat columns
M.STAT_TICK = 'Icons/questman/ui_check_mark.dds'   -- main-quest-finished checkmark
M.STAT_ICON_ACTIVE = 'Icons/questman/ui_in_progress.dds'   -- Overview "Active" row icon
M.STAT_ICON_DONE   = 'Icons/questman/ui_completed.dds'     -- Overview "Completed" row icon

return M
