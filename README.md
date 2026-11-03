<div align="center">

<img src="./icon.png" width="104" height="104" alt="AQWorlds Classic">

# AQWorlds Classic

An unofficial iOS and iPadOS port of AQWorlds Classic.

**[Download](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.3/AQWorlds-Classic-0.1.3-unsigned.ipa)** · [Release notes](https://github.com/krittayot611/aqworlds-classic-ios/releases/tag/v0.1.3)

Version 0.1.3 · Development preview

</div>

## Status

This project is under development. Version 0.1.3 replaces the remote launcher loading path to address SecurityError #2070. Game loading and Stage access passed a check in AIR's mobile-device emulation on macOS.

Version 0.1.2 was confirmed to start on a physical iPhone. On-device testing of 0.1.3 is pending. Login, server connections, map loading and touch controls remain unverified on physical devices.

## Installation

Use [Sideloadly](https://sideloadly.io/) on a Windows PC or Mac to sign and install the IPA.

1. Install Sideloadly. On Windows, follow its instructions for the required Apple components.
2. Download the IPA using the link above.
3. Connect your iPhone or iPad by USB, unlock it and select **Trust** when prompted.
4. Open Sideloadly, select your device and drag the IPA into the window.
5. Enter your Apple ID, click **Start** and complete authentication.
6. If prompted, enable **Settings → Privacy & Security → Developer Mode**, then restart and confirm. For an **Untrusted Developer** message, trust the signing profile under **Settings → General → VPN & Device Management**.

Open **AQWorlds Classic** and tap **Open game**. An internet connection is required.

Free Apple accounts generally require re-signing every seven days. See the [Sideloadly FAQ](https://sideloadly.io/faq) for refresh options and troubleshooting.

## Updating

Install the new IPA through Sideloadly using the same Apple ID, signing team and bundle ID as your existing installation. Keep any custom bundle ID setting unchanged to update the app in place.

The original package uses `com.personal.aqwprobe`. Retain your existing signing settings when updating.

## Releases

The current download is an unsigned IPA for iPhone and iPad. Personal signing is required.

[Checksums](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.3/SHA256SUMS.txt) · [All releases](https://github.com/krittayot611/aqworlds-classic-ios/releases)

## Issues

Report problems in [Issues](https://github.com/krittayot611/aqworlds-classic-ios/issues). Include your device model, iOS or iPadOS version, app version and a screenshot or description of the error.

---

AQWorlds and its game assets belong to Artix Entertainment. This project is not affiliated with or endorsed by Artix Entertainment.

