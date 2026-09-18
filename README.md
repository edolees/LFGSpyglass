# LFG Spyglass

A lightweight **filter for the Premade Group Finder** in World of Warcraft Retail (12.1).
LFG Spyglass keeps Blizzard's own look. It only changes *which* groups you see and in what order.

## Features (Raids)

- **Raids**: click a current raid's button (Encounter Journal icon) and **Normal / Heroic / Mythic**.
- **Bosses**: tick bosses of the raid to keep only groups that haven't killed them yet, or
  one-click **Fresh run** (no bosses killed).
- **Ranges**: members (min / max), most tanks and most healers already in the group.
- **Group needs**: Not Declined and Hide Class.
- **Sort**: the leader's raid progress from Raider.IO (default; groups without it by difficulty and
  bosses defeated), Blizzard order, newest listings, most members.
- With **Raider.IO** installed, raid rows show the leader's progress in that raid (for example
  **6/8 H**) and their main's when it's better (gear menu: **Show leader progress**).

## Features (Dungeons / Mythic+)

- **Dungeons**: click dungeon buttons (with their Mythic+ icons) to show only those dungeons, or use
  **All** / **None**.
- **Leader rating range**: min and max boxes, plus quick 2000+ / 3000+ / 3200+ / 3500+ buttons.
- **Group needs**:
  - **Party fit**: only groups with an open spot for one of your sign-up roles, or for your whole party.
  - **Has a Tank** / **Has a Healer**: only groups that already have a tank / a healer.
  - **Not Declined**: hide groups that already declined you.
  - **Hide Class**: hide groups that already have someone of your class.
  - Based on your class, **Bloodlust** (Shaman, Mage, Evoker, Hunter): hide groups that already have Bloodlust.
  - **Battle Res** (Druid, Death Knight, Warlock, Paladin): hide groups that already have a
    battle res.
- **I sign up as**: pick the roles you want to sign up as, shown with role icons (roles your class
  can't play are locked; your spec's role is ticked by default). Blizzard's sign-up dialog opens with those roles ticked, and Party fit uses them.
- **Sort**: leader rating high to low (default), Blizzard order, newest listings, or most members.
- **Re-apply** to groups whose application expired (Blizzard's list blocks them; groups that
  declined you stay blocked).
- The filtered list uses Blizzard's own rows, so signing up, the application timer and the
  **Cancel** button work exactly like stock.
- **Reset all** (last option in the gear menu); the panel footer shows how many groups match.
- Each group row shows the **leader's Mythic+ rating** and **region** (flag + tag such as
  East/Central/West with a US flag, OCE, BR, LATAM, or the EU language). Each row can also show every member's **spec icon** with a role badge and a **crown on
  the leader**. Toggle all of these from the panel's **gear icon**, which can also show
  **dungeon abbreviations** (KR, RLP, ...) on the dungeon buttons, and turn **Show ranges** off (hides
  the leader rating section; no leader rating filter while hidden).
- Works with Raider.IO: its profile window docks to the right of the filter panel.

## Known limits

- **No key level filter.** The key level only appears in the group title, and Blizzard does not
  let addons read titles. You can still type a level in Blizzard's own search box.
- **Filters pause during combat, boss encounters, active Mythic+ runs and PvP matches.**
  Blizzard restricts addon access to Group Finder data at those times; LFG Spyglass shows the normal
  list and says "Filters paused" instead of working around it.
- LFG Spyglass never searches, refreshes, signs up, cancels, invites or chats for you. Every action is
  a click on Blizzard's own buttons.
- Using LFG Spyglass together with another Group Finder filter (such as Premade Groups Filter) is not
  recommended; results may be filtered by both.

## Install

Install from CurseForge or Wago, or copy the `LFGSpyglass` folder into
`World of Warcraft/_retail_/Interface/AddOns/` and restart the game.

## Using it

Click the **spyglass** button in the Group Finder (above the Filter button) to turn LFG Spyglass on or
off. Everything else is in the LFG Spyglass panel next to the Group Finder; the **gear icon** holds
the display options and **Reset all**. There are no slash commands or options pages.
Settings are saved per character.

## Policy

LFG Spyglass is free, its code is fully readable, and it shows no ads or donation requests in game.
It follows Blizzard's UI Add-On Development Policy.

## Credits

- Flag icons: [Twemoji](https://github.com/jdecked/twemoji) graphics, © Twitter, Inc. and other
  contributors, licensed under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  Resized and converted to TGA.
- Realm region data: derived (modified and reduced) from
  [LibRealmInfo](https://github.com/phanx-wow/LibRealmInfo), © 2014-2019 Phanx, zlib license
  (continued by [janekjl](https://github.com/janekjl/LibRealmInfo)). See the license notice in
  `Data/RealmData.lua`.
- Libraries: [Ace3](https://github.com/WoWUIDev/Ace3) (see `Libs/Ace3-LICENSE.txt`).

## License

LFG Spyglass is released under the [MIT License](LICENSE). Bundled third-party code and art keep
their own licenses (see Credits).
