Development preview of AQWorlds Classic for iOS and iPadOS.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.4/AQWorlds-Classic-0.1.4.ipa)** · [Installation guide](https://github.com/krittayot611/aqworlds-classic-ios#installation)

### Fixes

- Centres the game on wide displays while preserving its aspect ratio and touch coordinates.
- Supplies the official game asset URL so files loaded after login resolve to the game server instead of the local app folder.
- Checks external asset loading through the game's own loader before publishing a release.
- Keeps the existing bundle ID, app name and icon for in-place updates.

### Testing

The release workflow checks compilation, IPA packaging, the game viewport and loading the official external asset library in AIR's mobile-device emulation on macOS. Version 0.1.3 reaches the login screen on a physical iPhone. Full login, server entry and gameplay with 0.1.4 still require on-device testing.

### Installation

Sign and install the IPA with Sideloadly on Windows or macOS. To update an existing installation, reuse the same Apple ID, signing team and bundle ID.

Checksums are included in the release assets.

---

AQWorlds and its game assets belong to Artix Entertainment. This project is not affiliated with or endorsed by Artix Entertainment.
