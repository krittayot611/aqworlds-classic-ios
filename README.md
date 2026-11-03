<p align="center"><img src="./icon.png" width="104" height="104" alt="AQWorlds Classic icon"></p>

# AQWorlds Classic for iOS / iPadOS

**Work in progress — unofficial experimental port.** This project is bringing AQWorlds Classic to iPhone and iPad with touch controls. It is still under development and is not a finished or official iOS release.

**โปรเจกต์พอร์ต AQWorlds Classic ลง iOS/iPadOS ยังอยู่ระหว่างพัฒนา** รุ่นนี้เป็นไฟล์ทดสอบ ไม่ใช่เวอร์ชันสมบูรณ์หรือแอปทางการจาก Artix Entertainment

## Download / ดาวน์โหลด

### [⬇ Download IPA v0.1.2 — กดเพื่อดาวน์โหลดไฟล์โดยตรง](https://github.com/krittayot611/aqworlds-classic-ios/releases/download/v0.1.2/AQWorlds-Classic-0.1.2-unsigned.ipa)

[Release notes and all downloads](https://github.com/krittayot611/aqworlds-classic-ios/releases)

The download is an **unsigned IPA**, not a ZIP. Downloading it does not install the app; use Sideloadly on a computer to sign and install it.

## Development status / สถานะการพัฒนา

| Item | Status |
| --- | --- |
| App name and golden dragon icon | Included |
| Touch input wrapper | Implemented; gameplay on a physical device remains unverified |
| Startup with the original bundle ID | Passed in an iPad (10th generation) simulator running iPadOS 18.6 |
| Startup after changing the bundle ID and re-signing | Passed in the same simulator |
| Real iPhone/iPad installation, login, server connection and map loading | Not yet verified |
| Touch combat, keyboard input, performance and long sessions | Not yet verified |

**Simulator startup passing does not mean that the full game is confirmed playable.** Please treat this as a development test build.

## ติดตั้งด้วย Sideloadly

1. ใช้คอมพิวเตอร์ Windows หรือ macOS ดาวน์โหลด [Sideloadly จากเว็บทางการ](https://sideloadly.io/) และติดตั้ง บน Windows ให้ทำตามคำแนะนำเรื่องส่วนประกอบ iTunes/iCloud ในเว็บนั้นด้วย
2. ดาวน์โหลดไฟล์ IPA จากปุ่มด้านบนลงคอมพิวเตอร์
3. ต่อ iPhone/iPad ด้วย USB ปลดล็อกเครื่อง และกด **Trust / เชื่อถือคอมพิวเตอร์** หากมีคำถาม
4. เปิด Sideloadly เลือกอุปกรณ์ แล้วลากไฟล์ `.ipa` ใส่โปรแกรม
5. ใส่ Apple ID กด **Start** และทำขั้นตอนยืนยันตัวตนตามที่โปรแกรมแสดง
6. ถ้าเครื่องขอ Developer Mode ให้เปิดที่ **Settings > Privacy & Security > Developer Mode** แล้วทำตามคำสั่งรีสตาร์ตและยืนยันบนเครื่อง
7. ถ้าขึ้น Untrusted Developer ให้ไป **Settings > General > VPN & Device Management** เลือกบัญชีที่ใช้เซ็น แล้วเชื่อถือโปรไฟล์นั้น
8. เปิด **AQWorlds Classic** แล้วกด **Open game** เพื่อโหลด launcher ทางการ ต้องเชื่อมต่ออินเทอร์เน็ต

บัญชี Apple แบบฟรีมีอายุการเซ็นโดยทั่วไป 7 วัน ต้องเซ็นใหม่ก่อนหมดอายุ หรือใช้ระบบรีเฟรชของ Sideloadly ตามเงื่อนไขใน [FAQ ทางการ](https://sideloadly.io/faq)

## อัปเดตทับแอปเดิม

ใช้ **Apple ID/ทีมเซ็นเดิม และ Bundle ID ที่ใช้ติดตั้งครั้งก่อน** เมื่อลาก IPA รุ่นใหม่เข้า Sideloadly หากเคยกำหนด Custom Bundle ID ให้ใช้ค่าเดิม จึงจะอัปเดตทับแอปเดิมโดยไม่ต้องลบก่อน

Bundle ID ในไฟล์ต้นฉบับคือ `com.personal.aqwprobe` แต่ sideloader อาจปรับรหัสระหว่างเซ็น ให้คงการตั้งค่าเดิมในการอัปเดต

## Install with Sideloadly (English)

1. Install [Sideloadly](https://sideloadly.io/) on Windows/macOS; follow its Windows Apple-component setup instructions.
2. Download the IPA, connect and unlock your iPhone/iPad, and trust the computer when asked.
3. Select your device in Sideloadly, drag in the IPA, enter your Apple ID, click **Start**, and complete authentication.
4. If requested, enable **Settings > Privacy & Security > Developer Mode**, restart, and confirm. For **Untrusted Developer**, trust the signing profile under **Settings > General > VPN & Device Management**.
5. Open **AQWorlds Classic**, then tap **Open game** while online.

For updates, reuse your previous signing account/team and effective bundle ID. Free-account signing generally lasts seven days; see Sideloadly's refresh instructions.

## Build information

| Field | Value |
| --- | --- |
| Version | 0.1.2 — development pre-release |
| File | AQWorlds-Classic-0.1.2-unsigned.ipa |
| Package | Physical iOS arm64, iPhone and iPad |
| Package minimum OS | iOS/iPadOS 12.0; actual device compatibility is not confirmed |
| Original bundle ID | com.personal.aqwprobe |
| Signing | Personal signing required; no personal certificate or provisioning profile included |

SHA-256:

```text
a6e6301dc727a0e5251e3663c39f98dd24cae2f3139038436fb1ca56c22a6af6
```

## Reporting a problem

Open an issue with the device model, iOS/iPadOS version, app version, and the screen or error where it stopped. State whether installation, startup, login, or gameplay failed.

## References and credits

- [Sideloadly and Windows setup](https://sideloadly.io/)
- [Sideloadly FAQ: refresh, profiles and updating an installed app](https://sideloadly.io/faq)
- [Apple: enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

AQWorlds and its game assets belong to Artix Entertainment. This is an unofficial development project, not affiliated with or endorsed by Artix Entertainment. This repository distributes the experimental client package and installation documentation.
