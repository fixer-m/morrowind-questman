# Changelog

All notable changes to Questman. One line per change — `[New]` feature, `[Change]` behaviour/looks, `[Fix]` bug fix.

## 1.6

- **[New]** Journal tab - replaces the Records tab: the whole journal as one feed, newest first, grouped by in-game day, with the quest name above its entries. Two modes: "All entries" and "Notes" (entries outside quests - the old Records content). Quest names are links (blue, like topic links) - click one to open the quest on the Quests tab. Loads in pages, so even huge journals open and scroll smoothly.
- **[New]** Quests: sorting - a new button next to the filter opens the sort options: by date, by name, by faction, by category, or by faction and category. The grouped modes split the list under group headers (pinned quests always on top). The choice is remembered per save.
- **[New]** Full-text search: the Quests and Topics search boxes now also find text inside journal entries and conversation lines. Search now starts from the 3rd letter (names used to be filtered from the first one). Title matches come first, then text matches, best first; matches are highlighted in the detail pane.
- **[New]** Topics: bookmarks - Ctrl+click a topic (or the star in its title, or Y on a controller) to pin it to the top of the list.
- **[New]** Settings: "Sort topics ignoring case" - an A-Z topic list instead of the vanilla order (capitalised names first, lowercase topics last).
- **[New]** Compatibility: UI Toolkit shows Questman's controller button hints while the window is open. Other mods can check whether the window is open via the `I.QuestmanWindow` interface.
- **[Change]** The window now reopens on the tab you last used even after restarting the game (before, only until you quit).
- **[Fix]** Game hotkeys (inventory, quick keys, journal, etc.) no longer fire behind the open Questman window. The Journal key now closes Questman.
- **[Fix]** Quests / Topics: the mouse wheel over the journal text in the detail pane scrolled the list instead of the details (it only worked over the empty space below the text).
- **[Fix]** Quests: the detail pane stayed blank when no quest was selected - it now says so.

## 1.5

- **[New]** Added support for "Poison Song" (Tamriel Rebuilt 26.08 Update). Two new factions: House Indoril and the Ordinators are now recognised and sorted into their own groups, each with a dedicated icon and its own row on the Stats page.
- **[Change]** Quests detail: each journal entry now shows its in-game date above the text (like the Records tab), instead of a plain number.
- **[Change]** Small UI tweak: the detail-pane labels (Category / Faction / entry dates) use a slightly warmer, more reddish tone.

## 1.4

- **[New]** Records tab - a new tab that collects journal entries the vanilla journal shows but that aren't quests (no quest name): East Empire Company colony logs, faction rules, Threads of the Webspinner, Imperial Cult notes, and even a few nameless questlines like "Blood Ties". Grouped per record, entries shown newest-first with their in-game date, with a search box.
- **[Change]** Dragging the list/detail divider now resizes the panes live as you drag on every tab (Quests, Topics, Records) — the search box, list and details follow the divider instead of only snapping into place on release.
- **[Fix]** Russian: the "Related topics" list now detects topics that appear in a declined case (e.g. "озеру Фьялдинг", "Корстом Ветроглазым") — previously only topics written in their exact base form were found, so many links were missed. Cyrillic topic matching is also now case-insensitive.
- **[Fix]** Quests could be completely missing on some French/German Morrowind versions due to malformed ESM file. The way quests are recognized was slightly changed to fix this issue. 

## 1.3

- **[New]** Settings: Quest icons — added an "SSQN+" option that also shows SSQN icons for add-on quests (Tamriel Rebuilt, Project Cyrodiil) for players who have SSQN's extra icon packs installed (e.g. SSQN Patches / Great Patch Hub).
- **[New]** Polish translation.
- **[Fix]** The enlarged quest-icon preview on the Progress tab could get stuck floating over the window after clicking a row to apply its filter — it's now dismissed properly.
- **[Fix]** Related topics list no longer hides lowercase topics. Generic topics (like "services", "rumors", "duties", etc) excluded explicitly.
- **[Change]** Performance: scrolling a long detail pane now is smooth - the quest and topic detail panes now render only the visible portion (like the quest/topic lists already did), so panes with lots of text or many related-topic links (e.g. generic topics like "Latest Rumors") no longer drop the framerate.
- **[Change]** Performance: opening the menu no longer freezes on huge load orders (Tamriel Rebuilt + Project Cyrodiil + SHOTN). The quest-giver scan now runs quietly in the background shortly after a save loads, spread across frames so it never stalls one - so by the time you open the journal it's usually already done and the window opens instantly.

## 1.2

- **[New]** Support for SSQN Icons, added option to change icon set in plugin settings.
- **[New]** Quest details: the Category and Faction lines are now clickable and filter the quest list to that group (same as the Progress tab rows).
- **[Change]** Translation fixes
- **[New]** Draggable divider between the list and detail panes. Drag it (resize cursor on hover) to change the split.
- **[New]** Settings: Quest list width and Topic list width (as %), also set by dragging the divider; grouped with the other window settings.
- **[New]** Full window resize: drag any edge or corner (not just the bottom-right grip), with the matching resize cursor on hover. The old dotted corner grip was removed.
- **[Change]** The window now opens only when no other menu is active, prevents some possible issues with other UI modes.
- **[Fix]** Pressing ESC now closes Questman instead of popping up the game menu (inventory).
- **[Fix]** Pinned HUD windows (e.g. the map) are now restored whenever Questman closes, no more opening/closing the inventory to get them back.
- **[Fix]** Some multi-part quests could disappear from the list while in progress, they now stay in the list from the moment they begin, and their "Quest from" line shows the correct quest-giver.
- **[Fix]** The active filter (add-on / category / faction) and the "show completed and hidden" toggle are now remembered and restored during save/load.

## 1.1

- **[New]** Full support for Tamriel Rebuilt, including Project Cyrodiil and Skyrim. New quests, factions and icons, support in filtering and progress tab.
- **[New]** Controller full support. D-pad moves the list selection, LB/RB cycle tabs, Y pins / X hides the selected quest.
- **[New]** Settings: "Override the journal" option (needs restart), opening the vanilla journal opens Questman instead
- **[New]** Settings: separate binding for gamepad button that opens main menu
- **[New]** Stats: full page redesign, two columns layout, icons, icons previews, etc
- **[New]** Stats: click any add-on / category / faction row to jump to the Quests tab filtered to it
- **[New]** Stats: Grayed checkmark + tooltip on the Great Houses you can't complete (mutually exclusive)
- **[New]** Topics: Arrow-key navigation of the topic list
- **[New]** Manual-config overrides (force_) at the top of ui.lua - to override bahavior (useful for consoles ports)
- **[Change]** UI: a few small fixes for readability
- **[Change]** Quest categorisation is now derived from the journal id (prefix/pattern masks) instead of a scraped quest database. More robust, covers mods automatically, and no longer depends on a fixed per-quest list
- **[Change]** Topics: conversation lines now show newest-first (matching the quest journal order)
- **[Change]** Topics: each line shows the speaker name above its text, and consecutive lines from the same speaker share one name label
- **[Change]** UI: Refreshed several text colors (list entries, selection, labels)
- **[Change]** Performance: opening the menu on large saves is faster - quest/topic/journal data is scanned once per open (was several times), and the first-open debug dump no longer blocks the window
- **[Change]** Performance: the Stats page opens faster on large saves - the per-add-on main-quest completion check no longer re-scans the whole quest list
- **[Change]** Performance: a quest's / topic's "Related topics" list is computed once per open and cached, so reselecting one you've already viewed is instant
- **[Fix]** Quests: meta quests (several journal ids under one name) now merge every constituent id's journal entries; previously only the single "completion" id's entries showed
- **[Fix]** Quests: Filter row and selection no longer reset when switching tabs or reopening the menu
- **[Fix]** Quests: Closing the filter row (funnel) now clears the active filter, instead of filtering with the controls hidden
- **[Fix]** Quest/topic detail no longer shows a needless scrollbar when the content fits
