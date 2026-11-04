Development preview of AQWorlds Classic for iOS and iPadOS.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.7/AQWorlds-Classic-0.1.7.ipa)** · [Installation guide](https://github.com/krittayot611/aqworlds-classic-ios#installation)

### Fixes

- Restores the original game coordinates and Stage child order used by map rendering and walking.
- Removes the wrapper transform and clipping rectangle added in 0.1.6.
- Retains automatic startup and the supplied loading background.
- Displays the surrounding background through full-screen source scaling where supported.
- Keeps the bundle ID, app name and icon for in-place updates.

### Testing

The release checks exercise the official World map rasteriser and movement-coordinate conversion with a synthetic map, without signing in. They also check automatic startup, game loading and external asset loading in AIR mobile-device emulation on macOS. Physical-device login, server entry and gameplay remain unverified for 0.1.7.

### Installation

Sign and install the IPA with Sideloadly on Windows or macOS. To update an existing installation, reuse the same Apple ID, signing team and bundle ID.

The HARMAN launch screen remains part of the AIR free-tier build. Checksums are included in the release assets.

---

AQWorlds and its game assets belong to Artix Entertainment. This project is not affiliated with or endorsed by Artix Entertainment.
