# ArmorySnap

**Passive gear & talent snapshots for your entire raid — enchants, gems, specs, and all.**

ArmorySnap is a World of Warcraft addon for **TBC Anniversary** (Classic TBC) that silently inspects every member of your 10- or 25-man raid in the background and stores a complete copy of their equipped gear and talent spec. Browse any snapshot later in a paper-doll inventory view with full item tooltips — no more hunting people down mid-raid to check if they're gemmed, enchanted, or even specced correctly.

---

## Features

- **Fully passive scanning** — walks through your raid roster automatically, one inspect every few seconds, until everyone is captured. No buttons to press.
- **Enchants & gems captured** — item links in TBC embed enchant IDs and all three gem sockets. ArmorySnap stores the full link, so tooltips render enchants and gems exactly as the game displays them.
- **Talent spec capture** — stores the full talent tree breakdown (e.g. `5/51/15 Protection`) for every raid member. Talent icons and point distributions display beneath the paper doll.
- **Paper-doll browser** — left/right slot columns and a bottom weapon row mirroring the character frame layout. Hover any slot for the native game tooltip; Shift-click to link items into chat.
- **Enchant & gem summary** — each character view shows a quick count of total enchants and gems at a glance so you can spot gaps without hovering every slot.
- **Live scan progress** — a status bar at the top of the browse frame shows X/Y members captured, updating in real time. The minimap button tooltip shows the same.
- **Automatic retry** — anyone out of inspect range gets retried every 2 minutes. Roster changes (joins, swaps) are detected within 10 seconds.
- **Zone-aware sessions** — entering a new raid instance starts a fresh snapshot session automatically. Snapshots are labeled with timestamp + zone name.
- **Group scan checkbox** — enable "Scan in group" to test the addon in a 5-man dungeon, open-world group, or any non-raid setting. Persists across sessions.
- **ElvUI theme** — toggle a dark flat theme that matches ElvUI's aesthetic. Pixel borders, dark panels, ElvUI accent colours. Toggle via the checkbox in the browse frame, right-click the minimap button, or `/as theme`.
- **Draggable minimap button** — drag it anywhere around the minimap edge. Position is saved across sessions.
- **Manual snapshot** — `/as snap` still available if you want a separate point-in-time capture independent of the passive session.
- **Persistent storage** — all snapshots live in SavedVariables and survive logouts, disconnects, and patches.

---

## Installation

1. Download or clone this repo.
2. Copy the `ArmorySnap` folder into your WoW `Interface/AddOns/` directory.
3. Restart WoW or `/reload` if you're already in-game.

```
World of Warcraft/
└── _classic_/
    └── Interface/
        └── AddOns/
            └── ArmorySnap/
                ├── ArmorySnap.toc
                ├── Core.lua
                └── UI.lua
```

> **Note:** The `.toc` uses `## Interface: 20504`. If your TBC Anniversary client reports a different interface version, update that number to match.

---

## Usage

### Passive scanning (default behavior)

Just zone into a raid instance. ArmorySnap starts scanning automatically — you'll see progress messages in chat:

```
[ArmorySnap] Auto-scan started in Serpentshrine Cavern  (25 members)
[ArmorySnap]   Scanned Tanky (16 items  5/51/15 Protection)  [1/25]
[ArmorySnap]   Scanned Healbot (15 items  41/20/0 Holy)  [2/25]
...
[ArmorySnap] All 25 raid members captured!
```

Members out of range are retried every 2 minutes. New members joining the raid are picked up within 10 seconds.

### Browsing snapshots

Click the **minimap button** or type `/as` to open the browser. Select a snapshot from the dropdown, click a name in the raid member list, and their gear appears in the paper-doll view. Hover any slot for the full tooltip with enchants and gems. Talent spec and tree breakdown display below the gear.

### Minimap button

| Action | Result |
|---|---|
| **Left-click** | Open/close the browser |
| **Right-click** | Toggle ElvUI theme |
| **Drag** | Reposition around minimap (saved) |

### Slash commands

| Command | Description |
|---|---|
| `/as` | Open/close the gear browser |
| `/as snap [label]` | Take a manual snapshot (immediate, separate from passive) |
| `/as list` | List all saved snapshots with member counts |
| `/as delete <name>` | Delete a snapshot by its label |
| `/as group` | Toggle group scanning on/off |
| `/as theme` | Toggle ElvUI theme on/off |
| `/as status` | Print current scanner state to chat |
| `/as reset` | Reset the current scan session |

---

## How it works

### Gear capture

ArmorySnap uses the game's `NotifyInspect` / `INSPECT_READY` API to request gear data for each raid member. The full `GetInventoryItemLink` is stored for every equipment slot — in TBC's item link format, enchant IDs and gem IDs (all 3 sockets) are embedded directly in the link string:

```
|cff...|Hitem:itemId:enchantId:gem1:gem2:gem3:...|h[Item Name]|h|r
```

When you hover a slot in the browser, `GameTooltip:SetHyperlink(link)` renders the complete tooltip with all enchant and gem information exactly as the game would show it on a live inspect.

### Talent capture

After `INSPECT_READY` fires, ArmorySnap calls `GetTalentTabInfo(tab, inspect)` for all three talent trees. It stores the tree name, icon texture, and points spent per tree. For the player character, it reads talents directly without the inspect flag. The spec is determined by whichever tree has the most points.

### Scan cycle

1. **Tick** every 3 seconds while in a raid instance (or group, if checkbox enabled)
2. **Pick** the next uncaptured member from the roster
3. **Inspect** if in range, or add to the failed queue if not
4. **Store** gear + talents on `INSPECT_READY`, then move to the next target
5. **Retry** failed members after a 2-minute cooldown
6. **Watch** for roster changes every 10 seconds once all current members are captured

---

## FAQ

**Does it work outside of raids?**
By default, only inside 10m and 25m raid instances. Check the "Scan in group" box (or `/as group`) to scan in any group setting.

**Will it interfere with other inspect addons?**
ArmorySnap uses the same `NotifyInspect` API as any inspect addon. If you have another addon that inspects on mouseover (like Examiner), there could be occasional conflicts if both try to inspect simultaneously. In practice this is rare since ArmorySnap only fires one inspect every 3 seconds.

**How much memory does it use?**
Each snapshot stores item links and talent data per member. A 25-man snapshot is roughly 20–30 KB in SavedVariables. You can store dozens of snapshots with negligible impact.

**Can I share snapshots with guildmates?**
The data lives in `WTF/Account/<account>/SavedVariables/ArmorySnap.lua`. You could share that file, but there's no built-in import/export yet — that's on the roadmap.

**Does the ElvUI theme require ElvUI?**
No. The theme is self-contained — it just reskins ArmorySnap's own frames to match ElvUI's visual style. ElvUI does not need to be installed.

---

## Roadmap

- [ ] Export snapshot to CSV or text for external review
- [ ] Highlight missing enchants / empty gem sockets with warning indicators on the paper doll
- [ ] Side-by-side comparison between two snapshots (gear changes over time)
- [ ] Optional 3D character model in the browse frame using `DressUpModel:TryOn`
- [ ] LibDataBroker support for broker display addons
- [ ] Full talent tree tooltip showing individual talent names and ranks on hover

---

## License

MIT — use it, fork it, snap it.
