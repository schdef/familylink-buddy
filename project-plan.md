I think this changes the project for the better. It becomes much more focused and much easier to explain.

The three decisions I'd make are:

* **Name:** **FamilyLink Buddy**
* **No Home Assistant dependency.** Instead, expose a clean REST/WebSocket API. If someone wants a Home Assistant integration, it can simply consume your API.
* **Open-core model:** one codebase, two deployment options (self-hosted and managed cloud).

I would also rethink the project from first principles.

---

# Product Vision

The current vision is:

> Show remaining screen time.

I think that is too narrow.

Instead:

> **FamilyLink Buddy is the missing companion for Google Family Link.**
>
> It gives parents and children a beautiful, real-time view of their Family Link data, helping families reduce conflicts around screen time through transparency instead of additional control.
>
> FamilyLink Buddy never replaces Google Family Link. It enhances it.

That sentence immediately defines what belongs in the product—and what does not.

---

# Product Principles

These should guide every future feature.

### Principle 1

Google Family Link remains the source of truth.

Never duplicate parental controls.

---

### Principle 2

Children should understand.

Parents should configure.

---

### Principle 3

Everything should reduce arguments.

If a feature doesn't make family life easier, don't build it.

---

### Principle 4

Transparency over surveillance.

The child should know exactly which information is collected.

---

### Principle 5

Fast.

Opening the app should never be required to answer:

> "How much time do I have left?"

---

### Principle 6

Open by design.

Every family owns its data.

---

### Principle 7

One codebase.

Hosted and self-hosted users receive exactly the same features.

---

# Product Positioning

Not

> parental control

Not

> screen time app

Instead

> **Google Family Link Companion**

That makes the product understandable in one sentence.

---

# Open Source Strategy

```
                GitHub

                   │

        FamilyLink Buddy Core

                   │

      ┌────────────┴─────────────┐

 Self Hosted              FamilyLink Buddy Cloud

 Docker                    Managed Service

 Free                      €2.99/month

```

Both versions use exactly the same code.

Only the backend endpoint changes.

---

# Architecture

Instead of

```
Flutter

↓

Firestore

↓

Cloud Functions
```

I'd build

```
Flutter Parent App

Android Child App

↓

FamilyLink Buddy API

↓

Domain Services

↓

Storage Provider

↓

Firestore (today)

↓

Other storage (future)
```

The apps should never know whether they are talking to your hosted service or a self-hosted Docker installation.

---

# API-first Architecture

Everything should be accessible via APIs.

For example

```
GET /family

GET /children

GET /remaining-time

GET /daily-usage

GET /device-status

POST /notifications

POST /heartbeat

POST /pair-device
```

Now integrations become easy.

Someone else can later build:

* Home Assistant
* Grafana
* Apple Shortcuts
* Node-RED
* Homey

without you maintaining them.

---

# Rethinking the MVP

This is where I think the current plan can improve the most.

The MVP should solve **one** problem extremely well.

## Child

"I want to know how much time I have left."

Nothing more.

---

## Parent

"I want to know whether everything is working."

Nothing more.

---

Everything else can wait.

---

# New Roadmap

Instead of 10 feature-heavy phases, I'd build in vertical slices.

---

## Phase 0 — Architecture

No UI.

Only:

* repository setup
* Docker
* backend abstraction
* API contract
* CI
* coding guidelines

Deliverable:

A project that can be built forever.

---

## Phase 1 — Child Widget MVP ⭐ ✅ IMPLEMENTED

This is where we started.

Goal:

Without opening an app, the child immediately sees:

```
Today

42 min remaining

App Usage:
- YouTube: 15m / 30m
- Minecraft: 20m / 1h

Updates automatically

```

Deliverables:

* ✅ Android Widget (Jetpack Glance `FamilyBuddyWidget`)
* ✅ Background sync (`WidgetUpdateService` foreground service)
* ✅ Usage display (overall + per-app remaining time)
* ✅ Offline cache (Jetpack DataStore `FamilyTimeRepository`)
* ✅ Beautiful design (gradient backgrounds, progress bars)
* ✅ Battery optimized (screen-on/off receiver gating)

---

## Phase 2 — Child Companion App ✅ IMPLEMENTED

Only enough UI to support the widget.

Features:

* ✅ remaining time
* ✅ today's usage (overall and per app)
* ✅ device status
* ✅ permissions (overlay permission check & grant flow)
* ✅ diagnostics (mock data controls in `MainActivity`)
* ✅ **Lock Warning Overlay:** When an app or the device has 3 minutes left before locking, a countdown overlay appears with a **Space Rocket Launch Mission** animation (preparing → liftoff → orbit). It can be moved on the screen, resized via `+` button, and dismissed with a 4-tap gesture.
* ✅ Lock reason display: shows whether the **device** or a specific **app** (by name) triggered the lock
* ✅ Bilingual support: German (default) and English
* ✅ 5-second post-countdown visibility delay before auto-dismiss

---

## Phase 3 — Remote Volume Control 🚧 NEXT

Parents can remotely adjust the volume on their child's device.

This phase introduces the **Parent App** and extends the **Child App** with a volume control listener.

### Parent App (`apps/parent-flutter/` or `apps/parent-android/`)

* Google Account login (OAuth 2.0) to authenticate the parent
* Device discovery: list paired child devices from the family group
* **Remote Volume Control UI:**
  * Slider to set the child device volume (media, ringtone, alarm)
  * Mute / unmute toggle
  * Current volume level indicator (synced from child)
* Communication channel: Firebase Cloud Messaging (FCM) or direct WebSocket to push volume commands to the child device

### Child App Extension (`apps/child-android/`)

* FCM receiver / WebSocket listener for incoming volume commands
* `AudioManager` integration to programmatically set device volume (media, ringtone, alarm streams)
* Report current volume level back to parent app
* Permission handling: ensure `MODIFY_AUDIO_SETTINGS` and notification access are granted
* Volume change broadcast receiver to detect manual volume changes on the device and sync back

### Security & Pairing

* Parent must authenticate with Google and prove family group membership
* Child device pairing via one-time code or QR scan
* All volume commands are authenticated and encrypted
* Child app shows a brief notification when volume is remotely adjusted (transparency principle)

### Deliverables

* Parent app with Google login and volume control dashboard
* Child app FCM/WebSocket volume command receiver
* Bidirectional volume state sync
* Secure pairing flow

---

## Phase 4 — Parent Dashboard

Expand the parent app with a read-only overview.

Dashboard:

```
Emma

42 min left

Online

Battery

Last Sync

Volume: 60%

```

Read-only status + volume control (from Phase 3).

No additional management.

No notifications.

---

## Phase 5 — Family Pairing

Now:

Google Login (already implemented in Phase 3)

Invite

Second parent

Pair child

Everything secure.

---

## Phase 6 — Live Updates

Realtime sync

Heartbeat

Offline detection

Widget updates

Status changes

Volume state sync

---

## Phase 7 — Nice UX

Overlay (partially done in Phase 2)

Notifications (including "Limit Reached" alerts)

Warnings

Animations (partially done in Phase 2: rocket launch)

Localization (i18n — DE/EN done in Phase 2)

Accessibility

---

## Phase 8 — Hosted Platform

Now build:

Authentication

Cloud

Billing

Docker

Deployment

Admin Portal

Monitoring

Feature Flags

Account Deletion & Data Export (GDPR compliance)

---

## Phase 9 — Public Release

Play Store

Documentation

Website

Privacy

Legal

Telemetry

Crash reporting

---

# Things I'd Remove from the Early Roadmap

RevenueCat

Advanced analytics

Export (until Phase 7)

Delete (until Phase 7)

Multi-language (until Phase 6)

Second parent (until Phase 4)

CI deployment to production

Most Cloud Functions

*Note: Version forcing was originally here, but it is critical for SaaS to enforce minimum versions to prevent breaking API changes. It should be included in Phase 0/1 Architecture.*

---

# Resilience & Error Handling

*(Addressing old flaws-to-fix)*
The app must fail gracefully. This deserves its own strategy:

* **Family Link unavailable:** Cache the last known state and clearly indicate "Last updated X mins ago."
* **Google Authentication expired:** Show a clear "Login expired" state in the parent app and prompt for re-authentication.
* **Network offline:** The child widget/app must still open instantly and show the offline cache with a visible offline indicator.
* **Permissions revoked (e.g., Overlay, Usage Access):** The child app should detect this and trigger a setup warning, and potentially notify the parent app.
* **App Uninstalled / FCM delayed:** Implement a 6-hour heartbeat in the child app. If the parent app doesn't receive a heartbeat for 12 hours, show a warning ("App may be uninstalled or offline").
* **Old app version:** Include a minimum version check in the backend API. If the app is too old, show a non-dismissible "Force Update" screen.

---

# Repository Structure

I'd organize it like this:

```
familylink-buddy/

    apps/

        child-android/

        parent-flutter/

    backend/

        api/

        services/

        storage/

    packages/

        api-contract/

        shared-models/

        shared-ui/

    docs/

        vision.md

        architecture.md

        api.md

        roadmap.md

        contributing.md

    docker/

    scripts/

```

---

# What I Would Build First

I would spend the first few weeks on just one question:

> **Can we build the best Android home-screen widget for Google Family Link?**

Imagine the child unlocks the phone and immediately sees:

```
──────────────────

🟢 Today

45 min remaining

████████░░

Updates a few seconds after Family Link changes.

──────────────────
```

No app launch.

No advertisements.

No menus.

No friction.

If you achieve that, you've already created something that Google Family Link itself doesn't offer in a polished, glanceable way. Everything else—parent dashboards, hosted cloud, self-hosting, APIs, notifications, and premium services—can be layered on top of that solid foundation without losing focus on the product's core value.
