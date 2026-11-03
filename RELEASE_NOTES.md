Development preview of AQWorlds Classic for iOS and iPadOS.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.3/AQWorlds-Classic-0.1.3-unsigned.ipa)** · [Installation guide](https://github.com/krittayot611/aqworlds-classic-ios#installation)

### Fixes

- Replaced the remote launcher loading path that caused SecurityError #2070 when accessing the app's Stage.
- Fetches the current game version from Artix and imports the official game into the application's domain.
- Passes the official launch parameters directly to the game client.
- Shows which loading step failed if a new error occurs.
- Keeps the existing bundle ID, app name and icon for in-place updates.

### Testing

The release workflow checks compilation, IPA packaging, and loading the official game into an iPad simulator with the original and a changed bundle ID. Login, server connections and gameplay on physical devices still require testing.

### Installation

The IPA is unsigned. Sign and install it with Sideloadly on Windows or macOS. To update an existing installation, reuse the same Apple ID, signing team and bundle ID.

Checksums are included in the release assets.

---

AQWorlds and its game assets belong to Artix Entertainment. This project is not affiliated with or endorsed by Artix Entertainment.
