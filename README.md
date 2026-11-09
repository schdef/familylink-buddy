# FamilyLink Buddy 🟢

> **The 100% Local-First, Zero-Cloud Companion for Android Parental Control.**
>
> FamilyLink Buddy gives parents real-time visibility, audio controls, silent camera checks, and app management for their children's Android tablets — **completely offline on your home Wi-Fi**, without cloud accounts, Firebase, or subscriptions.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Flutter-blue.svg)]()
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Local--First-green.svg)]()
[![Language](https://img.shields.io/badge/Language-English%20%7C%20Deutsch-orange.svg)]()

---

## 🌟 Why FamilyLink Buddy?

Google Family Link is useful, but it lacks critical real-time tools for parents at home:
* *How do I stop Spotify or YouTube from playing in the kid's bedroom after bedtime?*
* *How can I quickly check what's on the tablet screen or if my child is still awake?*
* *How do I instantly lock the screen or close smart-home apps (like Google Home) without cloud delays?*

Most third-party parental control apps upload private screenshots and camera photos to commercial cloud servers. **FamilyLink Buddy is 100% Local-First:**
- 🛡️ **Zero Cloud & Zero Firebase:** No accounts, no passwords, no servers. All data stays strictly inside your home Wi-Fi.
- ⚡ **Lightning Fast (50–100ms):** Direct peer-to-peer REST communication over LAN (port 8085).
- 🌐 **Full Multi-Language Support (EN & DE):** Automatic system language detection with in-app manual toggle between English (default) and German.
- 🔓 **F-Droid & Direct APK Ready:** No proprietary Google Play Services dependencies.

---

## ✨ Features

### 🎵 1. Real-Time Audio Playback Detection & Remote Stop
* **Live Audio Indicator:** The parent app automatically detects when audio (Spotify, YouTube, podcasts, games) is playing on the child tablet.
* **1-Tap Remote Stop:** Instantly pause playback from the parent phone via transient audio focus and media key events (`KEYCODE_MEDIA_PAUSE`).

### 📸 2. Silent Remote Camera (Flash OFF by default)
* **Silent Camera Snapshot:** Capture a photo on the child tablet from the parent phone (Front or Back camera).
* **Guaranteed Flash OFF (`FLASH_MODE_OFF`):** Does not trigger the camera flash, preventing disturbance or sudden glare.
* **Integrated Gallery:** View camera photos with clear badges (`📷 Front-Kamera` vs `📱 Bildschirm`), zoom in full-screen, or delete.

### 🖼️ 3. Remote Screenshots
* **Instant Screen Capture:** Request a real-time screenshot of the tablet's current screen in under 200ms.
* **Local Gallery & Batch Deletion:** Stored locally in parent app memory with option to delete individual shots or clear all history.

### 🛑 4. Instant App Blacklist (App Closer)
* **Block Specific Apps:** Close unwanted foreground apps (e.g. Google Home, Device Settings, browsers) the second they are opened.
* **Immediate Home Redirect:** Triggers `GLOBAL_ACTION_HOME` and displays a localized warning toast (`"[App] ist auf diesem Tablet gesperrt"`).
* **Installed Apps Picker:** Scan launcher apps on the tablet and manage the blacklist directly from the parent phone.

### ⏳ 5. Shared Category Limits & Bonus Minutes
* **Category Time Tracking:** Group apps into shared categories (e.g. *Gaming*, *Streaming*, *Social*) with shared daily minute limits.
* **Auto-Close on Limit Exceeded:** Automatically closes any app in the category once the daily quota is reached.
* **Quick Bonus Buttons:** Grant **+15 min** or **+30 min** bonus time directly from the parent app with a single tap.

### 🔒 6. Instant Remote Screen Lock
* **1-Tap Lock Button:** Remotely lock the tablet screen from the parent app at any time via Android Accessibility actions.

### 🌙 7. Bedtime Schedule & Wi-Fi Automation
* **Automated Bedtime Hours:** Set specific bedtime and wakeup times per weekday.
* **Nightly Wi-Fi Deactivation:** Optionally disable the tablet's Wi-Fi connection during bedtime to prevent late-night browsing.

### 📲 8. Zero-Config 1-Second QR-Code Pairing
* **No IP Typing:** The child tablet displays a high-contrast QR code containing local network discovery information and a random security token.
* **Instant Verification:** The parent phone scans the QR code with its camera, verifies connectivity via `GET /status`, and pairs immediately.

### 🔄 9. Dynamic mDNS & Subnet Auto-Discovery
* **DHCP Resilience:** If your home router assigns a new IP address to the tablet, the parent app automatically discovers the new IP via mDNS (`_familylinkbuddy._tcp`) or local subnet probing without requiring re-pairing.

### 🛡️ 10. Guided Setup Wizard (Android 13/14/15)
* **Bypass "Restricted Settings":** Step-by-step visual guidance helping non-technical parents navigate Android's *"Eingeschränkte Einstellungen zulassen"* security prompt.
* **Direct Shortcuts:** 1-tap buttons directly open App Info, Accessibility Settings, and Battery Optimization exemptions.

### 🔐 11. Anti-Tamper & 4-Digit Parent PIN
* **Settings Lock:** Accessing the Setup Wizard or configuration on the tablet requires entering a 4-digit parent PIN.
* **Accessibility Watchdog:** Automatically intercepts and blocks attempts by the child to turn off the Accessibility service in Android Settings.

### 🌐 12. Complete Multi-Language Support (English & German)
* **Automatic System Locale Detection:** Both Child Android and Parent Flutter apps automatically detect your device language and present the corresponding localized UI.
* **English Default with German Localization:** Defaults cleanly to English for international users, while providing native, natural German translations (`values-de/strings.xml` and `AppStringsDe`).
* **Manual In-App Language Toggle:** Switch languages on the fly via the top bar selector in the Parent app (`EN` / `DE`), with persistent user preferences stored locally.
* **100% Comprehensive Coverage:** Every dashboard card, dialog, setup step, toast notification, and error message is fully translated.

---

## 🏗️ Repository Architecture

```
familylink-buddy/
├── apps/
│   ├── child-android/        # Native Android Child App (Kotlin, Jetpack Compose, Camera2, Accessibility)
│   └── parent-flutter/       # Cross-Platform Parent App (Flutter, Material3 Dark Theme)
├── build/                    # Pre-compiled, signed Release APKs
│   ├── child-app-release.apk # Child tablet APK (25 MB)
│   └── parent-app-release.apk# Parent phone APK (85 MB)
├── .github/workflows/        # Automated GitHub Actions CI/CD release pipeline
├── build_release.sh          # Standalone release compiler script
├── run_tests.sh              # Unified unit test runner
└── run_app.sh                # Local Android deployment & emulator runner
```

---

## 🚀 Installation & Setup

### 📥 1. Download Pre-Compiled Release APKs
Download the latest signed APKs directly from the [GitHub Releases](../../releases) page or from the `build/` directory:
* **Child Tablet:** `child-app-release.apk`
* **Parent Phone:** `parent-app-release.apk`

### 📱 2. Setup on Child Tablet
1. Install `child-app-release.apk` on the child tablet.
2. Open the app — the **Setup Wizard** will guide you through 4 simple steps:
   * **Step 1:** Tap *Sicherheitseinstellung entsperren* (Android 13+: App-Info → 3 dots → *Eingeschränkte Einstellungen zulassen*).
   * **Step 2:** Tap *Bedienungshilfe einschalten* and enable **FamilyLink Buddy**.
   * **Step 3:** Tap *Akku-Optimierung deaktivieren* (Allows background execution).
   * **Step 4:** Set your 4-digit Parent PIN.
3. The tablet will display the **Kopplungs-QR-Code**.

### 👨‍👩‍👧 3. Setup on Parent Phone
1. Install `parent-app-release.apk` on your phone.
2. Open the app (no login or registration required!).
3. Tap **Gerät hinzufügen / Koppeln** and scan the QR code from the child tablet screen.
4. **Done!** The dashboard opens immediately and displays live volume, audio playback, camera, screenshot, and app limit controls.

---

## 🛠️ Building From Source

### Prerequisites
* **Java:** OpenJDK 17+
* **Android SDK:** API 34+
* **Flutter SDK:** 3.19+

### Compiling Release APKs
To build both APKs simultaneously into the `build/` directory:
```bash
./build_release.sh
```

### Running Automated Test Suites
To run both Android and Flutter unit and integration tests:
```bash
./run_tests.sh
```

---

## 🔒 Security & Privacy FAQ

* **Are my child's photos or screenshots uploaded to the internet?**
  **No.** FamilyLink Buddy contains no cloud SDKs, no tracking, and no external analytics. All communication occurs strictly within your local Wi-Fi router subnet using `http://<local-ip>:8085`.
* **Is the local connection secured?**
  **Yes.** Every LAN request between the parent phone and child tablet is authenticated with an `X-Buddy-Token` header exchanged securely during the initial QR-code scan.
* **Can other devices on my Wi-Fi access the camera or screenshots?**
  Requests without a valid `X-Buddy-Token` are immediately rejected with `HTTP 401 Unauthorized`.

---

## 📄 License
This project is licensed under the [MIT License](LICENSE).
