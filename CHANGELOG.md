# Changelog

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
