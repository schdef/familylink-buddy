/* src/utils/shuffle.js */

/**
 * Robust Fisher-Yates algorithm for uniform random shuffling.
 * Avoids browser-biased sorting bugs.
 */
export function shuffle(array) {
  const result = [...array];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}
