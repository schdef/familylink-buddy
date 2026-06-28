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
│   └── child-android/        # Native Android child application (Kotlin)
│       ├── app/
│       │   └── src/main/     # Core application source codes
│       └── gradle/           # Gradle build wrapper (8.10.2 / JDK 21)
├── project-plan.md           # Product roadmap and principles
└── run_app.sh                # Root automation script to build, deploy, & run
```

---

## ✨ Key Features Implemented

### Phase 1: Child Widget MVP 📱
Allows children to immediately answer *"How much time do I have left?"* without launching any app:
* **Jetpack Glance Widget:** Premium dark blue theme displaying overall remaining screen time and per-app usage limits (e.g. YouTube & Minecraft mock metrics) using clean, battery-optimized layouts.
* **Service-Driven Real-time Sync:** A background foreground service that detects screen-on status to run a sync ticker, updating widget views dynamically and bypassing Android's 30-minute widget refresh limitation.
* **Offline Caching:** Powered by Jetpack DataStore to load limits instantaneously on device boot or network loss.

### Phase 2: Lock Warning Overlay ⏱️
A floating screen overlay designed to notify children when they have **3 minutes or less** remaining:
* **System Overlay Layer:** Uses Android's `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY` to float over any active application or game.
* **Smooth Second-by-Second Timer:** Animates a countdown visually on the screen until lock state (`00:00`).
* **Tactile Interactions:**
  * **Draggable:** Grab the overlay and drag it anywhere on the screen.
  * **Cyclic Sizing Button:** Press the sizing preset button to cycle dimensions between **Small** (160dp x 80dp), **Medium** (240dp x 120dp), and **Large** (320dp x 160dp) to prevent layout clipping.
* **On-Demand Permission Handling:** `MainActivity` checks overlay authorization at startup and displays a premium red setup card linking directly to Android's "Draw over other apps" system options if disabled.

---

## 🚀 Getting Started

### 📋 Prerequisites
* macOS / Linux environment.
* **Android SDK** installed and configured (e.g., path exported in `local.properties`).
* **OpenJDK 21** installed (Homebrew JDK 21 is automatically resolved via the local `gradle.properties` configs).
* A running Android emulator or device connected via USB with **USB Debugging** enabled.

### 🏃 How to Build and Run
We have provided a zero-dependency helper script `run_app.sh` in the root folder that handles compilation, checks for active devices/emulators, installs the APK, and opens the main screen.

Simply run:
```bash
chmod +x run_app.sh
./run_app.sh
```

---

## 🧪 Manual Verification Steps

1. Run the app using `./run_app.sh`.
2. On initial launch, grant the notification and overlay permission using the red **"Grant Permission"** card.
3. Minimize the app (press the Home button), long-press your screen, and drag the **FamilyLink Buddy** widget to your home screen.
4. Open the app again to access the **Mock Control Panel**:
   * Press **"+15 min"** / **"-15 min"** to update remaining time, and observe the widget redraw instantly.
   * Press **"Mock 3 min Alert"**. Exit to your home screen or launch another app: the widget's indicators will turn red, and the floating **Lock Warning Overlay** countdown will immediately appear.
   * Drag the overlay around or click **SIZE** to adjust dimensions.
   * Press **"Reset Mock Data"** to clear the alert state: the overlay will automatically close.