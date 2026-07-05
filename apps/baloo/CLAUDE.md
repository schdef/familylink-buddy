# CLAUDE.md – Project Guidelines for Baloo / LernSpiel

## Project Identity

**Baloo** is an interactive educational web app for children (ages 6–12), inspired by the German [Anton app](https://anton.app). It helps kids learn biology and science topics through visual, game-based exercises.

The platform has two faces:
1. **For kids**: A calm, focused learning environment with 5 game modes and a star → reward-game economy
2. **For parents/teachers**: A content upload system (PDF, images, text → AI-generated exercises), lecture management, and progress tracking

## Primary Design Constraints

### 1. ADHD-First Design (Non-negotiable)

Every UI decision must be evaluated through the lens of a child with ADHD. This means:

- **Minimal visual clutter** — Clean layouts with generous whitespace. No busy backgrounds, excessive decorations, or auto-playing distractions.
- **Calm color palette** — Use soothing, muted tones. Avoid overstimulating neon colors. High contrast only for actionable elements.
- **Controlled, purposeful motion** — No gratuitous animations. Animations must serve a function (feedback, transition). Respect `prefers-reduced-motion`.
- **Chunked content** — Break tasks into small, clearly numbered steps. Show progress indicators ("Schritt 2 von 4") so the child always knows where they are.
- **No time pressure** — Never use countdown timers or rushing mechanics. Allow pausing, resuming, and exploring at own pace.
- **Predictable navigation** — Headers, menus, and buttons stay in the same position across all screens. Reduce memory load.
- **One task at a time** — Progressive disclosure. Only show what's needed for the current step.
- **Immediate, positive feedback** — Celebrate correct answers warmly but calmly. Never shame wrong answers. Use "Fast! Versuch es nochmal" instead of "Falsch!".

### 2. Visual Learning Priority

The app's primary learning modality is **visual**. This means:

- **SVG illustrations are first-class content**, not decoration. Every concept must have a clear, labeled visual representation.
- **Color-coding** — Each anatomical part/concept gets a consistent color across all game modes.
- **Diagram-based learning** — Prefer annotated diagrams over text-heavy explanations.
- **Show, don't tell** — Definitions should be short (≤10 words). Let the image carry the meaning.
- **Spatial learning** — The puzzle mode (drag-to-assemble) is a core differentiator. Invest in making it excellent.

## Gamification Model (Anton-inspired)

Follow the Anton app's proven reward system:

- **Stars** — Earned by completing exercises correctly. Stars are the primary currency.
- **Reward games** — Stars can be spent to unlock/play fun mini-games (not educational, purely recreational). This creates an intrinsic motivation loop.
- **No penalties** — Children never lose stars. Wrong answers simply don't earn stars.
- **Progress tracking** — Visual progress bars per topic. Parents can see an overview dashboard.
- **Trophies/Badges** — Milestone rewards for completing topics, streaks, or perfect scores.

## Responsive Design Requirements

- **Tablet-first** design (iPad, Android tablets) — this is the primary device for kids
- **Touch targets** — Minimum 44×44px for all interactive elements
- **Laptop support** — Full keyboard navigation, hover states
- **Breakpoints**:
  - `< 600px` — phone (single column, stacked layout)
  - `600px – 1024px` — tablet (primary target, 2-column grids)
  - `> 1024px` — laptop/desktop (wider layouts, side panels)

## Landing Page (Parent-Facing)

- Default language: **German**. Fallback: **English**
- Must explain the ADHD-friendly design philosophy to parents
- Must explain the star → reward game motivation system
- Must mention content upload capability
- Design: Calm, spacious, ADHD-friendly palette — no flashy marketing aesthetics
- CTA goes directly to the topic selection or sign-up

## Content Upload & Lecture Management

- Parents/teachers can upload PDFs, images, or type text descriptions
- AI (Gemini API via Firebase AI Logic) extracts learning content and generates:
  - Vocabulary cards (term + short definition)
  - Quiz questions (multiple choice)
  - Spelling words
- Parents review and approve AI-generated content before it's available to kids
- Lectures are organized in a folder/project structure with categories
- Each lecture tracks execution status: new → in progress → completed
- Per-exercise progress is visible in the lecture detail view

## Code Style

- No `innerHTML` with dynamic data — use `createElement` + `textContent` for XSS safety
- Encapsulated state per game mode (no global variables)
- Fisher-Yates shuffle instead of `sort(() => Math.random() - 0.5)`
- Event listeners with proper cleanup (no inline `onclick`)
- All text strings must be i18n-ready (extractable to translation files)
- Default language: German. Fallback: English

## Tech Stack

- **Frontend**: Vite + Preact (JSX components)
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions)
- **AI**: Firebase AI Logic (Gemini API) for content extraction
- **Hosting**: Firebase Hosting
- **Styling**: Vanilla CSS using custom properties (CSS variables) for strict layout parameters
- **Routing**: Lightweight, custom dependency-free client-side hash router
- **i18n**: Static JSON language dictionaries with translation key formatting helpers

## Key Architecture Constraints

1. **Strict Data-View Separation**: Game engines (Quiz, Memory, Spelling, Puzzle) must be completely agnostic to the content topics. They configure themselves dynamically by loading a structured JSON schema.
2. **State Isolation**: To prevent bugs, individual game components must hold and clean up their own state. Global state is strictly limited to user balance (stars) and current routing parameters.
3. **No Dynamic innerHTML**: For security (XSS prevention) on user-uploaded or AI-generated content, dynamic texts/labels must be assigned using `textContent` or Preact JSX children.
4. **Offline Resilience**: App design must utilize inline SVGs and localStorage fallbacks, enabling basic offline usability without requiring network access.

## Core Functionality

- **Landing Page**: Explains the ADHD-friendly concept, visual teaching, and star reward system to parents.
- **Vokabelkarten (Bilder)**: Visually engaging inline SVG flashcards with short descriptions.
- **Quiz**: Multiple-choice testing with chunked progress tracking.
- **Memory**: Pair-matching game using visual cards.
- **Wörter (Spelling)**: Drag-and-drop letter sorting tiles to assemble vocabulary terms.
- **Puzzle**: Spatial drag-and-drop layer stacking matching anatomical parts.
- **Star economy**: Users earn stars for correct exercises and spend them to play reward mini-games.
- **AI Upload Hub**: Parents upload materials (PDFs, images, text) that the Gemini API processes into new lectures.
- **Lecture Manager**: File-explorer style folders and execution state checks (New, In Progress, Completed).

## Key Learnings

- **Memory Card UX**: Card-backs must have a distinct border and icon (e.g. inline eye SVG) to prevent layout invisibility when flipped.
- **ADHD Sizing**: Constraining the viewport wrapper to `max-width: 640px` drastically improves target focus and reduces horizontal visual scanning fatigue.
- **Fisher-Yates Uniformity**: Native `Array.sort(() => Math.random() - 0.5)` generates highly skewed shuffles. A proper Fisher-Yates implementation is required to keep quiz questions random and engaging.
- **Muted Visuals**: Vibrant/neon colors cause cognitive sensory overload in ADHD learners. Soothing, low-saturation pastel backgrounds combined with high contrast focus outlines are optimal.

## Accessibility

- WCAG 2.1 AA compliance minimum
- All interactive elements must be keyboard-accessible
- ARIA labels on all buttons and interactive SVG elements
- `aria-live` regions for feedback messages
- High contrast mode support
- Screen reader compatible

