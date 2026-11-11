# HideTrackerForever

Hides the default Blizzard objective/quest tracker so guide addons like **RestedXP** and **Zygor** can own the right side of the screen.

Built for **World of Warcraft: Forever**.

## Features

- Hides Blizzard's objective/quest tracker (`WatchFrame` / `ObjectiveTrackerFrame`)
- Keeps it hidden when the client tries to re-show it
- Minimap button to toggle hide on/off
- Remembers your last setting across login and `/reload`
- Lightweight - no libraries

## Commands

| Command | Action |
|---------|--------|
| `/htf` | Toggle tracker hide |
| `/htf on` / `/htf off` | Force on or off |
| `/htf minimap` | Show/hide the minimap button |

## Install

Copy the `HideTrackerForever` folder into:

`World of Warcraft/_forever_/Interface/AddOns/`

Then enable it in the in-game AddOns list.

## License

MIT
