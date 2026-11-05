AQWorlds Classic 0.1.9 is the Stable release for iOS and iPadOS.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.9/AQWorlds-Classic-0.1.9.ipa)** · [Installation guide](https://github.com/krittayot611/aqworlds-classic-ios#installation)

### Changes

- Restores the game's original aspect ratio during login and gameplay.
- Uses the supplied texture to fill the surrounding screen margins through a native iOS view.
- Keeps the loading screen full-screen.
- Leaves game coordinates unchanged and disables input on the background view.
- Retains automatic startup, the app icon and the bundle ID for in-place updates.

### Testing

Release checks cover the native background in iOS Simulator, including texture loading, transparent game-area clipping, phone and tablet margin geometry, and disabled background input. AIR checks also exercise official game and external asset loading, map rasterisation and movement-coordinate conversion without signing in.

### Release channels

Stable is the full release. Upcoming updates are published as Unstable pre-releases with `-unstable.ipa` filenames. The current build for each channel is listed under [Downloads](https://github.com/krittayot611/aqworlds-classic-ios#downloads).

### Installation

Sign and install the IPA with Sideloadly on Windows or macOS. To update an existing installation, reuse the same Apple ID, signing team and bundle ID.

Checksums are included in the release assets.

AI tools assist with coding, debugging and documentation.

---

AQWorlds and all related game content, artwork and trademarks belong to Artix Entertainment. This independent project is not affiliated with, endorsed by or supported by Artix Entertainment. The software is provided as is, without warranty.
