/* src/engine/LectureStore.js
 * Client-side lecture management engine.
 * Stores user-created lectures in localStorage alongside the built-in topics.
 * Lectures are structured identically to the topic.json format so
 * the existing game modes work without any changes.
 *
 * Schema for a stored lecture:
 * {
 *   id: string,          // slug, e.g. "mein-thema-2024"
 *   title: { de, en },
 *   description: { de, en },
 *   icon: string,        // emoji
 *   source: 'user',      // vs 'builtin'
 *   status: 'new' | 'in_progress' | 'completed',
 *   createdAt: ISO string,
 *   updatedAt: ISO string,
 *   completedExercises: number,
 *   totalExercises: number,
 *   cards: Card[],
 *   puzzlePieces: [],
 * }
 */

const STORE_KEY = 'baloo_lectures';

function loadAll() {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY) || '[]');
  } catch {
    return [];
  }
}

function saveAll(lectures) {
  localStorage.setItem(STORE_KEY, JSON.stringify(lectures));
  window.dispatchEvent(new CustomEvent('lecturechange'));
}

export function getLectures() {
  return loadAll();
}

export function getLecture(id) {
  return loadAll().find(l => l.id === id) || null;
}

export function saveLecture(lecture) {
  const all = loadAll();
  const idx = all.findIndex(l => l.id === lecture.id);
  const now = new Date().toISOString();
  if (idx >= 0) {
    all[idx] = { ...all[idx], ...lecture, updatedAt: now };
  } else {
    all.unshift({ ...lecture, source: 'user', createdAt: now, updatedAt: now });
  }
  saveAll(all);
}

export function deleteLecture(id) {
  saveAll(loadAll().filter(l => l.id !== id));
}

export function updateLectureStatus(id, status) {
  const all = loadAll();
  const idx = all.findIndex(l => l.id === id);
  if (idx >= 0) {
    all[idx].status = status;
    all[idx].updatedAt = new Date().toISOString();
    saveAll(all);
  }
}

/** Mark an exercise session as started */
export function markStarted(id) {
  const all = loadAll();
  const idx = all.findIndex(l => l.id === id);
  if (idx >= 0 && all[idx].status === 'new') {
    all[idx].status = 'in_progress';
    all[idx].updatedAt = new Date().toISOString();
    saveAll(all);
  }
}

/** Increment completed exercises count and auto-complete */
export function incrementProgress(id) {
  const all = loadAll();
  const idx = all.findIndex(l => l.id === id);
  if (idx >= 0) {
    all[idx].completedExercises = (all[idx].completedExercises || 0) + 1;
    if (all[idx].completedExercises >= (all[idx].totalExercises || 1)) {
      all[idx].status = 'completed';
    }
    all[idx].updatedAt = new Date().toISOString();
    saveAll(all);
  }
}

/** Generate a URL-safe slug from a title */
export function makeSlug(title) {
  return title
    .toLowerCase()
    .replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 40)
    + '-' + Date.now().toString(36);
}
