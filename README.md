# Questman: Quests Menu for Morrowind (OpenMW)

Adds a new in-game menu for keeping track of your quests and journal entries. Press **X** (by default) to open it.
Allows to search and filter, pin and hide quests, jump between related dialogue topics and much more.

**Requirements:** OpenMW **0.50+**  
**Included Translations:** English, Russian, Polish  

**Links:** [Nexus Mod Page](https://www.nexusmods.com/morrowind/mods/59493) | [Release Notes](https://github.com/fixer-m/morrowind-questman/blob/main/CHANGELOG.md) | [Screenshots](https://www.nexusmods.com/morrowind/mods/59493?tab=images)

<p align="center"><img src="https://i.imgur.com/Uxcyfyk.png" alt="Questman" /></p>

## Main Features

- **Quest list:** active quests at the top, sorted by recent updates, completed quests are grayed out and hidden by default
- **Quest details:** shows addon, category, related faction, quest giver and all related journal entries (newest first)
- **Search:** instant search for any quest or topic
- **Filter quests:** filter your quests by add-on, category or faction — pick one from a drop-down list
- **Pin quest:** pin quests so they stay at the top of the list (with **Ctrl-click** or star button)
- **Hide quest:** hide quest from the list (with **Delete** or the eye button)
- **Clickable topics:** related topics work as links, just like the links in the vanilla journal
- **Topics tab:** a searchable index of every dialogue topic you've heard of, with topic-links
- **Progress tab:** shows your progress so far by quest types, main quest and faction completion
- **Gamepad support:** d-pad moves the list selection, LB/RB cycle tabs, Y pins / X hides the selected quest
- **Override Journal:** optional - will open the Questman menu instead of the vanilla Journal, can be enabled in plugin settings
- **Support for [Tamriel Rebuilt](https://www.tamriel-rebuilt.org):** quest icons, factions and grouping (including Cyrodiil and Skyrim)
- **Support for [SSQN icons](https://www.nexusmods.com/morrowind/mods/53712):** ensure you have SSQN installed and enable the according option in settings

## Support for Russian localization (1C)

- Correct **Cyrillic-aware** search
- Correct handling of the hyperlink markup (`@topic#`) that appears in dialogue and journal text

## Misc features

- **New quest icons:** brand new icons for every faction, category and addon
- **Technical info:** optional — show the quest **id** and current **stage**
- **Resizable window:** drag any corner or border to change the size. Position and size are remembered, and can be reset in settings.
- **Keyboard navigation:** Up/Down arrows move the selection, the list auto-scrolls to follow
- **Virtualized list:** search and scrolling stay instant even with thousands of quests/topics

## F.A.Q.

**Q:** Can I install this mid-game?  
**A:** Yes. It will show all your progress.

**Q:** Does it support mods like Tamriel Rebuilt and Project Cyrodiil?  
**A:** Yes. Proper support added in version 1.1.

## Installation

It can be installed like any other OpenMW Lua script plugin.

1. Copy the plugin files (Icons, Scripts, questman.omwscripts) into your game **data** folder. Or — if you prefer to have multiple data folders — add the plugin's folder as an additional **data** folder in the OpenMW launcher.
2. Enable **questman.omwscripts** in the OpenMW launcher. Or add it manually to your openmw.cfg:
   ```
   content=questman.omwscripts
   ```
3. Run the game, press **X** to open the menu. Configure the plugin in **Options → Scripts → Questman**.

## Configuration

- **Open menu key:** rebind the key that opens the window (default **X**).
- **Window width / height:** the default size of the menu.
- **Window position:** a **Reset** button to re-center the window next time it opens.
- **Show technical info:** also show each quest's id and stage in the detail pane.
- **Debug logging:** print `[questman]` diagnostics to openmw.log

## Credits

Mod inspiration & alternatives:

- OpenMW: [Quest Menu](https://www.nexusmods.com/morrowind/mods/56273)
- OpenMW: [Quest Guider Lite](https://www.nexusmods.com/morrowind/mods/57285)
- OpenMW: [Completionist](https://www.nexusmods.com/morrowind/mods/58020)
- MWSE: [Quest Log Menu](https://www.nexusmods.com/morrowind/mods/54203)
- MWSE: [Quest Guider](https://www.nexusmods.com/morrowind/mods/55593)
