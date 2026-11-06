# Threat On Nameplate

WoW: Forever addon. Shows your threat left of every enemy nameplate while you are in combat (nameplates on: `V`).

- **Your target**: the threat difference in points (`+` = your lead, `-` = how much you are missing).
- **All other enemies**: your threat as a percentage of aggro (100% = you pull it).
- **Optional bar** (`/tonp bar`): a -100% … +100% bar next to the number. Red = you do not have aggro, green = you have it.

Why two kinds of numbers: on the Forever client only the target's threat values can be read by addons. For other
nameplates the values are hidden from addon code and may only be passed to display widgets, so the bar lets the game
draw the difference itself.

If an older WeakAura "Threat Differential on Nameplates" is installed, it is set to "never load" once so the target does
not show two numbers (nothing is deleted; re-enable it in WeakAuras under Load if you prefer it).

## Commands

- `/tonp`: help
- `/tonp bar`: show or hide the -100% … +100% bar
- `/tonp test`: preview on the visible nameplates outside combat

## Install

Copy the `ThreatOnNameplate` folder into `_forever_\Interface\AddOns`, or install it from CurseForge.

## License

MIT
