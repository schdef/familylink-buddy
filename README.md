# FamilyLink Buddy 🟢

> **The missing companion for Google Family Link.**
>
> FamilyLink Buddy gives parents and children a beautiful, real-time view of their screen time limits, helping families reduce arguments through transparency rather than additional parental control.

---

## 🏗️ Repository Architecture

The project is structured as a monorepo containing:
```
familylink-buddy/
├── apps/
│   ├── child-android/        # Native Android child application (Kotlin)
│   ├── parent-flutter/       # Cross-platform parent dashboard (Flutter)
│   └── baloo/                # ADHD-friendly educational web application (Preact/Vite)
├── project-plan.md           # Product roadmap and principles
└── run_app.sh                # Root automation script to build, deploy, & run
```

---

## ✨ Key Features Implemented

### Phase 1: Child Widget MVP 📱
Allows children to immediately answer *"How much time do I have left?"* without launching any app:
* **On-Demand Permission Handling:** `MainActivity` checks overlay authorization at startup and displays a premium red setup card linking directly to Android's "Draw over other apps" system options if disabled.
* **Jetpack Glance Widget:** Premium dark blue theme displaying overall remaining screen time and per-app usage limits (e.g. YouTube & Minecraft mock metrics).
* **Service-Driven Real-time Sync:** A background foreground service that detects screen-on status to run a sync ticker, updating widget views dynamically and bypassing Android's 30-minute widget refresh limitation.
* **Offline Caching:** Powered by Jetpack DataStore to load limits instantaneously on device boot or network loss.

### Phase 2: Lock Warning Overlay ⏱️
A floating screen overlay designed to notify children when they have **3 minutes or less** remaining:
* **System Overlay Layer:** Uses Android's `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY` to float over any active application or game.
* **Smooth Second-by-Second Timer:** Animates a countdown visually on the screen until lock state (`00:00`).
* **Tactile Interactions:** Draggable overlay with cycle sizing presets (**Small**, **Medium**, **Large**).

### Phase 3: Remote Volume Control ⭐
Allows parents to adjust volume levels remotely on the child device.
* **Remote Volume Control:** Parents can set media, ringtone, or alarm volumes.
* **Instant FCM Updates:** Real-time push synchronization using Firestore-based command triggers.

### Phase 4: Time Coins (Earn & Spend Reward System) ⏳
An ADHD-friendly allowance currency allowing children to earn screen time tokens for completing tasks and spend them in a Reward Store:
* **Independent Reward Economy:** Coins represent privileges (e.g. "1 Std. Minecraft") rather than direct lock commands. Keeps Google Family Link as the single source of truth for device locks.
* **ADHD UX Principles:**
  - **Fidget Interaction:** Tapping the main coin balance flips and spins the coin with particle sparkles.
  - **Max 3 Items:** Avoids choice paralysis by listing a maximum of 3 tasks and 3 rewards.
  - **Countdown Task Timer:** Timer tasks auto-complete when the countdown finishes.
  - **Low Coins Warning:** Pulsing red glow alert when balance drops to 5 coins or fewer.
  - **Synthesized Audio:** Triumphal sounds play on task completion and coin earn.
  - **FCM Coin Rain Confetti:** Immediate visual reward splash when parent awards coins.
* **Glance Widget Integration:** Adds a custom coin balance row to the Glance home widget.

### Phase 9: Educational Rewards Loop (Baloo Integration) 🎮
Allows children to earn screen time dynamically by completing educational modules:
* **ADHD-Friendly Learning:** Children learn biology and science topics at their own pace without timers or stress.
* **Firestore Screen Time Bridge:** Baloo writes completed achievements directly to FamilyLink Buddy's Firestore pairings using a lightweight REST client, updating the Android widget and countdown timer instantly.
* **Parent Dashboard Controls:** Enables parents to configure integration status, enter child pairing tokens, and adjust reward conversion rates (e.g. 1 Star = 2 minutes screen time) in Baloo's settings.

---

## 🚀 Getting Started

### 📋 Prerequisites
* macOS / Linux environment.
* **Android SDK** installed and configured (e.g., path exported in `local.properties`).
* **OpenJDK 21** installed.
* **Flutter SDK** (v3.18+) configured.
* A running Android emulator or device connected via USB with **USB Debugging** enabled.

### 🏃 How to Build and Run
We have provided a zero-dependency helper script `run_app.sh` in the root folder that handles compilation, checks for active devices/emulators, installs the APK, and opens the main screen.

Simply run:
```bash
chmod +x run_app.sh
./run_app.sh
```

### 🎮 Running Baloo (Educational App)
1. Navigate to the Baloo directory:
   ```bash
   cd apps/baloo
   ```
2. Install dependencies and start the development server:
   ```bash
   npm install
   npm run dev
   ```
3. To deploy to production Firebase Hosting, run:
   ```bash
   npm run build
   npx -y firebase-tools@latest deploy --only hosting --project familylink-buddy
   ```

To run the parent app:
```bash
cd apps/parent-flutter
flutter run
```

---

## 🧪 Automated Testing

We maintain automated non-UI unit tests for repositories, state controllers, model parsers, and thresholds.

### Running Child Android Tests:
```bash
cd apps/child-android
./gradlew test
```

### Running Parent Flutter Tests:
```bash
cd apps/parent-flutter
flutter test
```