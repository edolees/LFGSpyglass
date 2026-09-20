# Changelog

## 1.3.1 (2026-09-20)

### Changed
- Dungeons: the group tooltip shows each member's **name and realm**, in their class color, in place
  of their class and spec. The role icons stay.

### Fixed
- Raids: the left column of boss checkboxes is no longer cut off at the edge of the boss list.
- The search box's suggestions are no longer hidden behind LFG Spyglass's list: while they are open,
  the list drops below them and goes back afterwards.

## 1.3.0 (2026-09-20)

### Added
- Dungeons: hovering a group shows each **member's name** in white at the end of their own line in
  the tooltip (gear menu: **Show member names**, on by default). Raid tooltips are left as Blizzard
  draws them, and names only appear when the game sends them.

### Changed
- The **Dark appearance** choice is now account-wide: set it once and every character uses it.

### Fixed
- The **Declined** label no longer sticks on groups that only delisted: once such a group lists
  again, its row looks normal again (Blizzard keeps painting it as declined until you reload).

## 1.2.0 (2026-09-20)

### Added
- **Dark appearance** (gear menu, off by default): LFG Spyglass's own panel, buttons, chips,
  checkboxes, number boxes, the spyglass button and the Sign Up button can be drawn dark and flat
  instead of Blizzard's look. Turning it on or off asks you to reload. Blizzard's Group Finder
  window and the group rows are never restyled, no other add-on is needed, and no extra art ships
  with it.

### Fixed
- Groups that **delisted while you had applied** are no longer treated as declines: they stay
  visible with **Not Declined** on, and you can apply again once they list again (Blizzard blocks
  that until a reload). Groups that really declined you are still hidden and blocked.

### Changed
- A little more space between a checkbox and its label.

## 1.1.0 (2026-09-18)

### Raids
- The raid buttons are gone: the boss list now shows every boss of this season's raids, and
  **Difficulty** sits at the top.
- Boss checkboxes: **left-click** (tick) keeps only groups that haven't killed that boss yet,
  **right-click** (new, red cross) only groups that already killed it, for example to find a group
  for the last boss. Click again to clear; **None** clears all marks.
- **Fresh run** clears the boss marks, and marking a boss turns Fresh run off.

### Dungeons
- **Right-click** a dungeon to hide its groups (red cross); left-click still selects.
- Dungeon buttons always show the short names (KR, RLP, ...), with the full name in the tooltip;
  the option for it is gone.
- The header always shows how many dungeons are selected (0/8 to 8/8).

### Everywhere
- **Sort** is now a sort icon next to the gear, which frees a row in the panel.

## 1.0.1 (2026-09-18)

- Fixed a Lua error when hovering **Show ranges** in the gear menu.

## 1.0.0 (2026-09-18)

First release.

### Dungeons (Mythic+)
- Filter panel docked next to the Group Finder, built from Blizzard's own templates.
- Dungeon buttons with Mythic+ icons (All / None, optional short names such as KR or RLP).
- Leader rating range (min / max) with quick 2000+ / 3000+ / 3200+ / 3500+ buttons.
- Group needs: Party fit, Has a Tank, Has a Healer, Not Declined, Hide Class, and for the right
  classes Bloodlust and Battle Res.
- I sign up as: pick your roles once; Blizzard's sign-up dialog opens with them ticked.
- Sort by leader rating (default), Blizzard order, newest listings or most members.

### Raids
- Buttons for this season's raids, Normal / Heroic / Mythic, and a checkbox per boss (keep only
  groups that haven't killed it yet), plus Fresh run.
- Members, most tanks and most healers already in the group; Not Declined and Hide Class.
- With Raider.IO: raid rows show the leader's progress in that raid (for example 6/8 H; Mythic also
  shows Heroic, and the main's when it's better), and groups are sorted by it.

### Everywhere
- The filtered list uses Blizzard's own rows: signing up, the application timer and Cancel work
  like stock. Re-apply to groups whose application expired.
- Group rows can show the leader's rating, region (flag and tag), spec icons and a leader crown
  (gear menu).
- The footer shows how many groups match; refreshing never flashes the unfiltered list.
- Filters pause (Blizzard's list is shown) while Blizzard restricts add-ons: combat, boss
  encounters, Mythic+ runs, PvP matches.
- Spyglass button in the Group Finder turns LFG Spyglass on or off. Settings are saved per
  character. No slash commands or options pages.
- Raider.IO's profile window docks next to the filter panel.

### Embedded libraries (unmodified)
- Ace3 `Release-r1403` (official mirror github.com/WoWUIDev/Ace3): LibStub, CallbackHandler-1.0,
  AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceLocale-3.0. (AceConsole, AceGUI, AceConfig and
  AceDBOptions were removed with the slash commands, options page and profiles.)
- AceHook-3.0 is **not** embedded: hooks use plain `hooksecurefunc`.
