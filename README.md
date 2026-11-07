# Canopy Chase

An original, offline Quest VR playground inspired by arm-driven climbing and tag. **Early prototype with simple procedural art.** Not affiliated with Gorilla Tag.

## Download and install

[Download the Quest APK (169.6 MB)](https://github.com/markovandermerwe549-ops/literate-octo-funicular/releases/download/v0.1.0/CanopyChase-Quest.apk) · [All release files](https://github.com/markovandermerwe549-ops/literate-octo-funicular/releases/tag/v0.1.0)

Enable Quest Developer Mode, connect over USB, accept USB debugging, and sideload the APK using SideQuest. Or run:

```sh
adb install -r CanopyChase-Quest.apk
```

Launch **Canopy Chase** from **Unknown Sources**. Targets Quest 2, Quest 3/3S, and Quest Pro with tracked Touch controllers. This is a development-signed ARM64 APK.

**No physical Quest was available for testing. Installation, controller tracking, comfort, audio, and headset frame rate still need device testing. Offline bots only; no online multiplayer or voice chat.**

![Desktop preview of Emerald Canopy](docs/CanopyChase-Preview.png)

## Features

- Four arenas: Emerald Canopy, Sunstone Canyon, Glacier Hollow, and Neon Overgrowth.
- Five modes per arena: free roam, bot tag, infection, time trial, and crystal hunt.
- Palm pushing, grip climbing, release momentum, body collisions, and haptics.
- Five bots with obstacle steering; infection can spread between bots.
- Nine race gates, saved best times, 30 collectible crystals per arena, and 90-second rounds.
- Collectible shards, five unlockable hand colors, and local progression saves.
- Day/night lighting, movement speed settings, stick assist, and 30/45-degree snap turning.
- VR menu, head-mounted status display, camp reset, and four original two-minute ambient scores.

## Quest controls

| Input | Action |
| --- | --- |
| Push solid surfaces with your palms | Propel yourself |
| Grip near a solid surface, then pull | Climb; release to carry momentum |
| Either hand touches a bot | Tag |
| Left stick | Assisted movement, when enabled |
| Right stick | Snap turn |
| X or B | Toggle menu |
| Y | Return to camp |
| Right controller pointer + trigger | Select menu buttons |

## Source and building

Import `project.godot` into **Godot 4.6.3**. The OpenXR Vendors 5.1.0 addon is included with its licenses. If no OpenXR runtime is available, use `godot --path . --xr-mode off` for the desktop preview. Desktop controls: WASD, mouse, Space, Tab, and R.

For Quest exports, install matching Godot Android templates and use **Project > Install Android Build Template**. Configure a full JDK and the Android SDK in Editor Settings. This build used JDK 17, Android API 36, and build tools 36.1.0. Export the included **Quest** preset with your own configured signing key. Generated build folders and private keys are excluded.

The APK is larger than 100 MB because it includes used stereo ambient audio and the native VR runtime, with no size-only filler.

## Validation

All 20 arena/mode combinations passed headless checks, plus collection rewards, race completion, bot tagging, infection victory, settings, reset, and save actions. A Linux OpenGL desktop render was inspected. APK signature, alignment, archive integrity, ARM64 libraries, and Quest/OpenXR manifest settings passed checks. See [build details](docs/BUILD-INFO.txt) and [full installation/build guide](START-HERE.txt).

## License

Original game code, procedural content, icon, and audio: [MIT](LICENSE.txt). Godot and bundled vendor components retain their own licenses; see the included notices and addon license files.
