Development preview of AQWorlds Classic for iOS and iPadOS.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.8/AQWorlds-Classic-0.1.8.ipa)** · [Installation guide](https://github.com/krittayot611/aqworlds-classic-ios#installation)

### Changes

- Loading, login and gameplay now fill the display without letterbox borders or cropped controls.
- Keeps the supplied texture on the loading screen.
- Preserves the original game coordinates used by map rendering and walking.
- Retains automatic startup, the app icon and the bundle ID for in-place updates.

Full-screen scaling adjusts the image proportions to each device's aspect ratio.

### Testing

Release checks cover automatic startup, official game and external asset loading, map rasterisation and movement-coordinate conversion in phone and tablet layouts using AIR mobile-device emulation on macOS. They do not sign into a game account. Full-screen rendering, touch input and gameplay still need confirmation on physical iOS devices.

### Installation

Sign and install the IPA with Sideloadly on Windows or macOS. To update an existing installation, reuse the same Apple ID, signing team and bundle ID.

The HARMAN launch screen remains part of the AIR free-tier build. Checksums are included in the release assets.

---

AQWorlds and its game assets belong to Artix Entertainment. This project is not affiliated with or endorsed by Artix Entertainment.
