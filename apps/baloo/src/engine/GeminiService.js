/* src/engine/GeminiService.js
 * Gemini AI content extraction service.
 *
 * Sends parent-uploaded content (text description OR base64 image) to the
 * Gemini API and receives back a structured JSON array of learning cards
 * compatible with the Baloo topic.json schema.
 *
 * API key: stored in .env as VITE_GEMINI_API_KEY
 * If no key is configured the service returns demo/placeholder cards so the
 * app still works in development without a key.
 */

const API_KEY = import.meta.env.VITE_GEMINI_API_KEY || '';
const GEMINI_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

// The structured prompt that instructs Gemini to generate Baloo cards
function buildPrompt(userText, customPrompt = '') {
  let promptText = `Du bist ein Pädagoge für Kinder von 6–12 Jahren mit ADHS. 
Analysiere den folgenden Lerninhalt und erstelle daraus genau 6 Lernkarten für die Baloo-Lern-App.

LERNINHALT:
${userText}
`;

  if (customPrompt.trim()) {
    promptText += `\nZUSÄTZLICHE ANWEISUNG DER ELTERN:\n${customPrompt.trim()}\n`;
  }

  promptText += `
ANTWORTFORMAT – Antworte NUR mit diesem JSON-Array, ohne Erklärungen:
[
  {
    "term": { "de": "Begriff auf Deutsch", "en": "Term in English" },
    "def": { "de": "Kurze Definition ≤10 Wörter", "en": "Short definition ≤10 words" },
    "color": "#HEX",
    "bg": "#HEX"
  }
]

Regeln:
- Genau 6 Karten
- Jede Karte hat eine eigene Farbe (color) und passende Hintergrundfarbe (bg, helle Version)
- Definitionen max. 10 Wörter, kindgerecht und einfach
- Verwende KEINE Sonderzeichen außer in den Definitionen
- Gib NUR den JSON-Array zurück, kein Markdown, kein Text davor oder danach`;

  return promptText;
}

// Fallback demo cards when no API key is configured
function makeDemoCards(title) {
  const colors = [
    { color: '#1D9E75', bg: '#E1F5EE' },
    { color: '#185FA5', bg: '#E6F1FB' },
    { color: '#BA7517', bg: '#FAEEDA' },
    { color: '#D85A30', bg: '#FAECE7' },
    { color: '#534AB7', bg: '#EEEDFE' },
    { color: '#D4537E', bg: '#FBEAF0' },
  ];
  const demoTerms = [
    { de: 'Begriff 1', en: 'Term 1', def_de: 'Erste Beispiel-Definition', def_en: 'First example definition' },
    { de: 'Begriff 2', en: 'Term 2', def_de: 'Zweite Beispiel-Definition', def_en: 'Second example definition' },
    { de: 'Begriff 3', en: 'Term 3', def_de: 'Dritte Beispiel-Definition', def_en: 'Third example definition' },
    { de: 'Begriff 4', en: 'Term 4', def_de: 'Vierte Beispiel-Definition', def_en: 'Fourth example definition' },
    { de: 'Begriff 5', en: 'Term 5', def_de: 'Fünfte Beispiel-Definition', def_en: 'Fifth example definition' },
    { de: 'Begriff 6', en: 'Term 6', def_de: 'Sechste Beispiel-Definition', def_en: 'Sixth example definition' },
  ];
  return demoTerms.map((t, i) => ({
    term: { de: t.de, en: t.en },
    def: { de: t.def_de, en: t.def_en },
    color: colors[i].color,
    bg: colors[i].bg,
    svg: makePlaceholderSvg(t.de, colors[i].color, colors[i].bg)
  }));
}

function makePlaceholderSvg(label, color, bg) {
  // Safe SVG without embedded text labels (quiz-safe)
  return `<svg viewBox="0 0 160 90" xmlns="http://www.w3.org/2000/svg"><rect width="160" height="90" fill="${bg}"/><circle cx="80" cy="40" r="25" fill="${color}" opacity="0.7"/><circle cx="80" cy="40" r="15" fill="${color}" opacity="0.4"/><circle cx="80" cy="40" r="6" fill="${color}"/></svg>`;
}

/**
 * Extract cards from a text description using Gemini.
 * @param {string} text  - User-provided text content
 * @param {string} title - Lecture title (used for demo fallback)
 * @param {string} customPrompt - Optional custom prompt from parent
 * @returns {Promise<Card[]>}
 */
export async function extractCardsFromText(text, title = '', customPrompt = '') {
  if (!API_KEY) {
    // No API key — return demo cards after a short artificial delay
    await new Promise(r => setTimeout(r, 1200));
    return makeDemoCards(title);
  }

  const body = {
    contents: [{ parts: [{ text: buildPrompt(text, customPrompt) }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.4,
      maxOutputTokens: 1024,
    }
  };

  const res = await fetch(`${GEMINI_URL}?key=${API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    throw new Error(`Gemini API error: ${res.status}`);
  }

  const data = await res.json();
  const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text || '[]';
  
  let cards;
  try {
    cards = JSON.parse(rawText);
  } catch {
    throw new Error('Gemini hat kein gültiges JSON zurückgegeben.');
  }

  // Add placeholder SVGs for each card
  return cards.map(card => ({
    ...card,
    svg: makePlaceholderSvg(card.term?.de || '', card.color || '#888', card.bg || '#EEE')
  }));
}

/**
 * Extract cards from a base64-encoded image using Gemini Vision.
 * @param {string} base64Data  - Base64 image data (without data URI prefix)
 * @param {string} mimeType    - e.g. 'image/jpeg', 'image/png'
 * @param {string} title
 * @param {string} customPrompt - Optional custom prompt from parent
 * @returns {Promise<Card[]>}
 */
export async function extractCardsFromImage(base64Data, mimeType, title = '', customPrompt = '') {
  if (!API_KEY) {
    await new Promise(r => setTimeout(r, 1800));
    return makeDemoCards(title);
  }

  const promptText = buildPrompt('Das Bild zeigt Lerninhalt. Analysiere das Bild und erstelle Lernkarten.', customPrompt);

  const body = {
    contents: [{
      parts: [
        { text: promptText },
        { inlineData: { mimeType, data: base64Data } }
      ]
    }],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.4,
      maxOutputTokens: 1024,
    }
  };

  const res = await fetch(`${GEMINI_URL}?key=${API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!res.ok) throw new Error(`Gemini API error: ${res.status}`);

  const data = await res.json();
  const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text || '[]';
  
  let cards;
  try {
    cards = JSON.parse(rawText);
  } catch {
    throw new Error('Gemini hat kein gültiges JSON zurückgegeben.');
  }

  return cards.map(card => ({
    ...card,
    svg: makePlaceholderSvg(card.term?.de || '', card.color || '#888', card.bg || '#EEE')
  }));
}
