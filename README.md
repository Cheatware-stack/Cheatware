# Cheatware

A clean, modern cheat panel for Roblox featuring ESP, Aimbot, and Silent Aim.

![UI Preview](https://i.imgur.com/placeholder.png)

## Features

### ESP
- Box ESP with outlines
- Tracers (bottom, mouse, or crosshair origin)
- Player names
- Health bars with numerical values
- Distance display
- Team check
- Max distance limit
- FOV circle indicator
- Custom crosshair

### Aimbot
- Smooth aim with configurable smoothness
- FOV-based target selection
- Part selection (Head, Root, Torso, etc.)
- Prediction for moving targets
- Visibility and wall checks
- Customizable keybind (default: RMB)

### Silent Aim
- FOV-based target acquisition
- Hit chance percentage
- Prediction for moving targets
- Part selection
- Team, visibility, and wall checks
- Weapon `FireServer` hooking

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/youruser/cheatware/main/Cheatware.lua"))()
```

| Key | Action |
|-----|--------|
| `Right Shift` | Toggle menu |
| `RMB` | Aimbot (configurable) |

## Configuration

The panel provides a fully graphical UI for all settings. No manual editing required.

### ESP Tab
| Setting | Description |
|---------|-------------|
| Enabled | Toggle all ESP visuals |
| Box ESP | 2D bounding boxes |
| Box Outline | Outline for boxes |
| Tracers | Lines from origin to players |
| Names | Display player names |
| Health | Health bars + values |
| Distance | Range to target |
| Team Check | Ignore teammates |
| Max Distance | Render distance limit |

### Aimbot Tab
| Setting | Description |
|---------|-------------|
| Enabled | Toggle aimbot |
| Keybind | Set activation key |
| Smoothness | Camera lerp speed |
| FOV | Targeting field of view |
| Prediction | Lead time for moving targets |
| Hit Part | Body part to target |
| Team Check | Ignore teammates |
| Visibility | Only target visible players |
| Wall Check | Check for obstructions |

### Silent Aim Tab
| Setting | Description |
|---------|-------------|
| Enabled | Toggle silent aim |
| FOV | Targeting cone |
| Hit Chance | Probability of successful hit |
| Prediction | Lead time for moving targets |
| Hit Part | Body part to redirect to |
| Team Check | Ignore teammates |
| Visibility | Only target visible players |
| Wall Check | Check for obstructions |

## Compatibility

Built for Roblox executors supporting:
- `Drawing` library
- `getrawmetatable` / `setreadonly` / `newcclosure`
- `mousemoverel`

## Disclaimer

This software is provided for educational purposes only. Use at your own risk. The authors are not responsible for any account penalties incurred.
