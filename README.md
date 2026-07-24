# Questman - Modern Quest Journal (OpenMW)

Adds a new in-game menu for keeping track of your quests and journal. Find any quest instantly, filter the list down to a single faction or add-on, pin the ones you care about, read a quest's journal entries in order, jump between related dialogue topics, and see how much of the game you've actually finished. 

It is built natively for **OpenMW**, with a feature-rich UI and no extra dependencies. 

> **Requirements:** OpenMW **0.50+**  
> **Included Languages:** English and Russian

---

## Features

### Quests tab
- **Instant search box** — type to filter the list by quest name as you go
- **Filter the list** by **add-on**, **category**, or **faction** — pick one from a drop-down list
- **Pin important quests** — pin your quests so they stay at the top of the list (with **Ctrl-click** or star button)
- **Hide quests** — hides them from the list (with **Delete** or the eye button)
- **Quest details** — shows the quest giver, related faction, and the journal entries you've seen (newest first)
- **Clickable related topics** — jumps to the Topics tab and its related info, just like the links in the vanilla journal
- **Display hidden and finished** — a checkbox to also show every quest you've completed or hidden

### Topics tab
- **List of topics** — a searchable index of every dialogue **topic** you've accumulated
- **Topic entries** — shows every line you've heard about it, and from whom
- **Related topics** — links here too, so you can cross-reference your way through the lore

### Stats tab
- **Overview** — active, completed, and total quests across the whole game
- **By add-on** — progress for every add-on that adds quests (Morrowind, Tribunal, Bloodmoon, and large mods like Tamriel Rebuilt / Project Cyrodiil / Province: Skyrim), ordered by release, with a **✓** when you've finished that add-on's main quest
- **By category** — progress per quest type (Main Quest, Great House, Guild/Faction, Vampire, Daedric, Miscellaneous, plus mod-specific categories)
- **By faction** — progress per joinable faction, with a **✓** when you've reached its highest rank

### Native support for Russian localisation (1C/Akella)
- Proper **Cyrillic-aware** search
- Proper handling of the hyperlink markup (`@topic#`) that appears in dialogue and journal text

### Misc features
- **Icons** — custom icons for every add-on, faction, and category
- **Optional technical info** — turn on a setting to also show the quest **id** and current **stage**
- **Counters** — a slim strip under the list shows how many quests are **shown / total** or **hidden**
- **Resizable window** — drag the lower-left corner to change the size. Position and size are remembered, and can be reset in settings.
- **Keyboard navigation** — Up/Down arrows move the selection, the list auto-scrolls to follow
- **Controller support** — D-pad moves the selection, **LB/RB** switch tabs, **Y** pins and **X** hides the selected quest, **B** closes the menu
- **Virtualized list** — search and scrolling stay instant even with thousands of quests/topics

## F.A.Q.

- Q: Can I install this mid-game?  
- A: Yes. It will show all your progress so far.  

- Q: Does it support mods like Tamriel Rebuilt and Project Cyrodiil?  
- A: Yes — quests from **Tamriel Rebuilt**, **Project Cyrodiil** and **Province: Skyrim** are sorted into their add-on, faction and category. Other mods still work; their quests appear under **"Other" / "Unknown"** until dedicated support is added.  

## Installation

It installs like any other OpenMW script plugin. 

1. Copy plugin files (Icons, Scripts, questman.omwscripts) into your game **data** folder.  
2. Enable **questman.omwscripts** in the OpenMW launcher. Or add it manually to your `openmw.cfg`:  
```
content=questman.omwscripts
```
Alternatively, if you prefer to keep multiple data folders, add the plugin's folder as an additional **data** folder in the OpenMW launcher.  
3. Run game, press **X** (default) to open the menu. Configure plugin in **Options → Scripts → Questman**. 

## Configuration

- **Open menu key** — rebind the key that opens the window (default **X**).
- **Open menu (controller)** — bind a gamepad button to open the window (click the field, then press a button).
- **Override the journal** — open the vanilla journal to show Questman instead (requires a restart).
- **Window width / height** — the default size of the menu.
- **Window position** — a **Reset** button to re-centre the window next time it opens.
- **Show technical info** — also show each quest's `id` and `stage` in the detail pane.
- **Debug logging** — print `[questman]` diagnostics to `openmw.log` (off for normal play).

## Credits

- Quest categories and taxonomy reference the community documentation at **UESP**

**Mod inspiration & alternatives** 
- [Quest Log Menu](https://www.nexusmods.com/morrowind/mods/54203) (MWSE)
- [OpenMW Quest Menu](https://www.nexusmods.com/morrowind/mods/56273) (OpenMW)
- [Quest Guider](https://www.nexusmods.com/morrowind/mods/55593) (MWSE) and [Quest Guider Lite](https://www.nexusmods.com/morrowind/mods/57285) (OpenMW)
- [Completionist](https://www.nexusmods.com/morrowind/mods/58020) (OpenMW)
