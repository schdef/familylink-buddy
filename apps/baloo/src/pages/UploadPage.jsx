/* src/pages/UploadPage.jsx
 * Upload page for parents to create new lectures from text, image, or PDF.
 * Uses Gemini AI to extract structured cards, shows a review screen, and saves to LectureStore.
 */
import { useState } from 'preact/hooks';
import { extractCardsFromText, extractCardsFromImage } from '../engine/GeminiService';
import { saveLecture, makeSlug } from '../engine/LectureStore';
import { navigate } from '../router';
import { t, getLanguage } from '../utils/i18n';

const PRESET_CATEGORIES = ['Biologie', 'Geografie', 'Geschichte', 'Sprachen', 'Mathematik', 'Sonstiges'];
const PRESET_EMOJIS = ['👁️', '👂', '🧠', '🦖', '🌍', '📐', '🧪', '🪐', '🦴', '🦁', '🌳', '🏛️'];

export function UploadPage() {
  const lang = getLanguage();
  
  // Form states
  const [title, setTitle] = useState('');
  const [category, setCategory] = useState('Biologie');
  const [customCategory, setCustomCategory] = useState('');
  const [icon, setIcon] = useState('👁️');
  const [inputType, setInputType] = useState('text'); // 'text' | 'image' | 'pdf'
  
  const [textInput, setTextInput] = useState('');
  const [file, setFile] = useState(null);
  const [filePreview, setFilePreview] = useState(null);
  
  const [customPrompt, setCustomPrompt] = useState('');
  
  // App states
  const [isLoading, setIsLoading] = useState(false);
  const [statusMessage, setStatusMessage] = useState('');
  const [extractedCards, setExtractedCards] = useState(null);
  const [error, setError] = useState('');

  // Handle file drop/select
  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];
    if (!selectedFile) return;

    setFile(selectedFile);
    setError('');

    if (selectedFile.type.startsWith('image/')) {
      const reader = new FileReader();
      reader.onloadend = () => {
        setFilePreview(reader.result);
      };
      reader.readAsDataURL(selectedFile);
    } else {
      setFilePreview(null);
    }
  };

  // Convert File to Base64
  const fileToBase64 = (file) => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.readAsDataURL(file);
      reader.onload = () => {
        const base64String = reader.result.split(',')[1];
        resolve(base64String);
      };
      reader.onerror = (error) => reject(error);
    });
  };

  // Run AI extraction
  const handleExtract = async (e) => {
    e.preventDefault();
    if (!title.trim()) {
      setError(lang === 'de' ? 'Bitte gib einen Lektionstitel ein.' : 'Please enter a lecture title.');
      return;
    }

    setIsLoading(true);
    setError('');
    setExtractedCards(null);
    setStatusMessage(lang === 'de' ? 'KI liest den Lernstoff...' : 'AI is reading the content...');

    try {
      let cards = [];
      const finalTitle = title.trim();

      if (inputType === 'text') {
        if (!textInput.trim() && !customPrompt.trim()) {
          throw new Error(lang === 'de' ? 'Bitte gib einen Lernstoff-Text oder Anweisungen ein.' : 'Please enter some learning text or instructions.');
        }
        setStatusMessage(lang === 'de' ? 'Erstelle kindgerechte Karten...' : 'Generating child-friendly cards...');
        cards = await extractCardsFromText(textInput, finalTitle, customPrompt);
      } else {
        if (!file) {
          throw new Error(lang === 'de' ? 'Bitte wähle eine Datei aus.' : 'Please select a file.');
        }
        
        setStatusMessage(lang === 'de' ? 'Lese Datei ein...' : 'Reading file contents...');
        const base64Data = await fileToBase64(file);
        
        setStatusMessage(lang === 'de' ? 'Künstliche Intelligenz analysiert Datei...' : 'AI is analyzing file contents...');
        // extractCardsFromImage works for both images and pdfs because it passes the mimeType to inlineData
        cards = await extractCardsFromImage(base64Data, file.type, finalTitle, customPrompt);
      }

      if (!cards || cards.length === 0) {
        throw new Error(lang === 'de' ? 'Es konnten keine Lernkarten extrahiert werden.' : 'No learning cards could be extracted.');
      }

      setExtractedCards(cards);
    } catch (err) {
      console.error(err);
      setError(err.message || (lang === 'de' ? 'Fehler bei der KI-Generierung.' : 'AI generation failed.'));
    } finally {
      setIsLoading(false);
      setStatusMessage('');
    }
  };

  // Card changes during review
  const handleCardChange = (index, field, langKey, val) => {
    const updated = [...extractedCards];
    if (langKey) {
      updated[index][field] = {
        ...updated[index][field],
        [langKey]: val
      };
    } else {
      updated[index][field] = val;
    }
    setExtractedCards(updated);
  };

  // Final save
  const handleSave = () => {
    const finalCategory = category === 'custom' ? (customCategory.trim() || 'Sonstiges') : category;
    
    // Create new lecture object in topic.json structure
    const lectureId = makeSlug(title);
    const newLecture = {
      id: lectureId,
      title: {
        de: title,
        en: title
      },
      description: {
        de: lang === 'de' ? `Lerne das Thema "${title}"` : `Learn about "${title}"`,
        en: `Learn about "${title}"`
      },
      icon: icon,
      category: finalCategory,
      ageRange: [6, 12],
      difficulty: 'Mittel',
      status: 'new',
      completedExercises: 0,
      totalExercises: 5, // Vocab, Quiz, Memory, Spelling, Puzzle (or 4 if puzzle is omitted, let's keep 4 or 5)
      cards: extractedCards,
      // Custom cards don't have puzzle SVG parts, we generate dynamic labels if they play puzzle mode
      puzzlePieces: extractedCards.map((c, index) => ({
        id: `card_${index}`,
        name: c.term,
        hint: c.def,
        targetX: 30 + (index * 20) % 100,
        targetY: 40 + (index * 15) % 60,
        color: c.color,
        stroke: c.color
      }))
    };

    saveLecture(newLecture);
    navigate('/manager');
  };

  const getTranslated = (obj) => {
    if (!obj) return '';
    return obj[lang] || obj.de || '';
  };

  return (
    <div style={{ maxWidth: '720px', margin: '0 auto', padding: '1rem 0' }}>
      <div style={{ textAlign: 'left', marginBottom: '1.5rem' }}>
        <h1 style={{ marginBottom: '4px' }}>📤 {t('menu.upload')}</h1>
        <p style={{ fontSize: '0.95rem', color: 'var(--color-text-secondary)' }}>
          {lang === 'de' 
            ? 'Erstelle in wenigen Sekunden eine eigene Lektion für dein Kind per Künstlicher Intelligenz (Gemini).' 
            : 'Create custom lectures for your child in seconds using artificial intelligence (Gemini).'}
        </p>
      </div>

      {error && (
        <div style={{
          backgroundColor: '#FBEBEB',
          border: '1px solid var(--color-danger)',
          color: 'var(--color-danger)',
          padding: '12px 16px',
          borderRadius: 'var(--radius-md)',
          marginBottom: '1.5rem',
          fontSize: '0.9rem'
        }}>
          ⚠️ {error}
        </div>
      )}

      {/* STAGE 1: Configuration & File Upload */}
      {!extractedCards && !isLoading && (
        <form onSubmit={handleExtract} class="card" style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1.25rem', textAlign: 'left' }}>
          
          {/* Title input */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontWeight: '600', fontSize: '0.9rem' }}>
              {lang === 'de' ? '1. Titel der Lektion' : '1. Lecture Title'}
            </label>
            <input
              type="text"
              placeholder={lang === 'de' ? 'z. B. Das Ohr, Die Blüte, Bundesländer...' : 'e.g. The Ear, Parts of a Flower...'}
              value={title}
              onInput={(e) => setTitle(e.target.value)}
              style={{
                padding: '10px 12px',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--color-border-primary)',
                fontSize: '1rem',
                outline: 'none'
              }}
              required
            />
          </div>

          {/* Category & Emoji Row */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label style={{ fontWeight: '600', fontSize: '0.9rem' }}>
                {lang === 'de' ? '2. Fachbereich / Kategorie' : '2. Category'}
              </label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                style={{
                  padding: '10px',
                  borderRadius: 'var(--radius-md)',
                  border: '1px solid var(--color-border-primary)',
                  fontSize: '0.95rem'
                }}
              >
                {PRESET_CATEGORIES.map(cat => (
                  <option key={cat} value={cat}>{cat}</option>
                ))}
                <option value="custom">{lang === 'de' ? 'Eigene Kategorie...' : 'Custom Category...'}</option>
              </select>
              {category === 'custom' && (
                <input
                  type="text"
                  placeholder={lang === 'de' ? 'Kategoriename' : 'Category Name'}
                  value={customCategory}
                  onInput={(e) => setCustomCategory(e.target.value)}
                  style={{
                    padding: '8px 10px',
                    borderRadius: 'var(--radius-md)',
                    border: '1px solid var(--color-border-primary)',
                    fontSize: '0.9rem',
                    marginTop: '4px'
                  }}
                  required
                />
              )}
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label style={{ fontWeight: '600', fontSize: '0.9rem' }}>
                {lang === 'de' ? '3. Symbol (Emoji)' : '3. Icon (Emoji)'}
              </label>
              <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
                <span style={{
                  fontSize: '2rem',
                  padding: '4px 10px',
                  backgroundColor: 'var(--color-bg-secondary)',
                  borderRadius: 'var(--radius-md)',
                  border: '1px solid var(--color-border-primary)',
                  display: 'inline-block',
                  minWidth: '50px',
                  textAlign: 'center'
                }}>
                  {icon}
                </span>
                <select
                  value={icon}
                  onChange={(e) => setIcon(e.target.value)}
                  style={{
                    padding: '8px',
                    borderRadius: 'var(--radius-md)',
                    border: '1px solid var(--color-border-primary)',
                    fontSize: '0.9rem',
                    flex: '1'
                  }}
                >
                  {PRESET_EMOJIS.map(em => (
                    <option key={em} value={em}>{em} Select</option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          {/* Input Type Select Tab */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
            <label style={{ fontWeight: '600', fontSize: '0.9rem' }}>
              {lang === 'de' ? '4. Art der Inhaltsquelle' : '4. Content Source Type'}
            </label>
            <div style={{
              display: 'flex',
              backgroundColor: 'var(--color-bg-secondary)',
              padding: '4px',
              borderRadius: 'var(--radius-md)',
              gap: '4px'
            }}>
              <button
                type="button"
                onClick={() => { setInputType('text'); setFile(null); }}
                style={{
                  flex: '1',
                  padding: '8px',
                  borderRadius: 'var(--radius-sm)',
                  border: 'none',
                  backgroundColor: inputType === 'text' ? '#FFF' : 'transparent',
                  fontWeight: inputType === 'text' ? '600' : 'normal',
                  boxShadow: inputType === 'text' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  fontSize: '0.9rem'
                }}
              >
                📝 {lang === 'de' ? 'Text beschreiben' : 'Text Input'}
              </button>
              <button
                type="button"
                onClick={() => { setInputType('image'); setFile(null); }}
                style={{
                  flex: '1',
                  padding: '8px',
                  borderRadius: 'var(--radius-sm)',
                  border: 'none',
                  backgroundColor: inputType === 'image' ? '#FFF' : 'transparent',
                  fontWeight: inputType === 'image' ? '600' : 'normal',
                  boxShadow: inputType === 'image' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  fontSize: '0.9rem'
                }}
              >
                📸 {lang === 'de' ? 'Foto hochladen' : 'Photo Upload'}
              </button>
              <button
                type="button"
                onClick={() => { setInputType('pdf'); setFile(null); }}
                style={{
                  flex: '1',
                  padding: '8px',
                  borderRadius: 'var(--radius-sm)',
                  border: 'none',
                  backgroundColor: inputType === 'pdf' ? '#FFF' : 'transparent',
                  fontWeight: inputType === 'pdf' ? '600' : 'normal',
                  boxShadow: inputType === 'pdf' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  fontSize: '0.9rem'
                }}
              >
                📄 {lang === 'de' ? 'PDF Dokument' : 'PDF Document'}
              </button>
            </div>
          </div>

          {/* Conditional Input Forms */}
          {inputType === 'text' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label style={{ fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
                {lang === 'de'
                  ? 'Füge hier den Lerninhalt, Stichpunkte, Buchtexte oder eine Beschreibung ein (mind. 20 Wörter):'
                  : 'Paste learning contents, summary points, textbook texts, or a description here (min 20 words):'}
              </label>
              <textarea
                placeholder={lang === 'de'
                  ? 'Kopiere hier z. B. Text über die Fotosynthese, Planeten oder Vulkane hinein. Die KI erstellt passende Vokabeln und Erklärungen.'
                  : 'Paste text about photosynthesis, planets, or volcanoes here. The AI will extract vocabulary cards and short definitions.'}
                value={textInput}
                onInput={(e) => setTextInput(e.target.value)}
                style={{
                  minHeight: '140px',
                  padding: '10px 12px',
                  borderRadius: 'var(--radius-md)',
                  border: '1px solid var(--color-border-primary)',
                  fontSize: '0.95rem',
                  lineHeight: '1.5',
                  outline: 'none',
                  fontFamily: 'inherit',
                  resize: 'vertical'
                }}
                required
              />
            </div>
          )}

          {(inputType === 'image' || inputType === 'pdf') && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
                {inputType === 'image'
                  ? (lang === 'de' ? 'Lade ein Foto einer Buchseite, eines Tafelbilds oder Diagramms hoch:' : 'Upload a photo of a textbook page, blackboard, or diagram:')
                  : (lang === 'de' ? 'Lade ein PDF-Dokument des Lernstoffs hoch:' : 'Upload a learning material PDF:')}
              </label>

              <div style={{
                border: '2px dashed var(--color-border-secondary)',
                borderRadius: 'var(--radius-lg)',
                padding: '2rem',
                textAlign: 'center',
                backgroundColor: 'var(--color-bg-secondary)',
                cursor: 'pointer',
                position: 'relative'
              }}>
                <input
                  type="file"
                  accept={inputType === 'image' ? 'image/png, image/jpeg, image/webp' : 'application/pdf'}
                  onChange={handleFileChange}
                  style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    width: '100%',
                    height: '100%',
                    opacity: 0,
                    cursor: 'pointer'
                  }}
                />
                
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                  <span style={{ fontSize: '2.5rem' }}>{inputType === 'image' ? '🖼️' : '📁'}</span>
                  <span style={{ fontWeight: '600', fontSize: '0.95rem' }}>
                    {file ? file.name : (lang === 'de' ? 'Datei hier ablegen oder anklicken' : 'Click or drag file here')}
                  </span>
                  <span style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)' }}>
                    {inputType === 'image' 
                      ? 'PNG, JPG, WEBP (max. 10MB)' 
                      : 'PDF (max. 10MB)'}
                  </span>
                </div>
              </div>

              {filePreview && (
                <div style={{ textAlign: 'center', marginTop: '10px' }}>
                  <img
                    src={filePreview}
                    alt="Preview"
                    style={{ maxHeight: '160px', borderRadius: 'var(--radius-md)', border: '1px solid var(--color-border-primary)' }}
                  />
                </div>
              )}
            </div>
          )}

          {/* Custom AI Prompt (Optional) */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '8px' }}>
            <label style={{ fontWeight: '600', fontSize: '0.9rem' }}>
              {lang === 'de' ? '5. Eigene KI-Anweisung (Optional)' : '5. Custom AI Prompt (Optional)'}
            </label>
            <label style={{ fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
              {lang === 'de' 
                ? 'Beispiel: "Generiere nur Nomen", "Fokussiere dich auf Jahreszahlen" oder "Passe es für einen 7-Jährigen an".' 
                : 'Example: "Generate only nouns", "Focus on dates" or "Adapt for a 7-year-old".'}
            </label>
            <textarea
              placeholder={lang === 'de' ? 'Spezielle Anweisungen für die KI...' : 'Special instructions for the AI...'}
              value={customPrompt}
              onInput={(e) => setCustomPrompt(e.target.value)}
              style={{
                minHeight: '60px',
                padding: '10px 12px',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--color-border-primary)',
                fontSize: '0.95rem',
                lineHeight: '1.4',
                outline: 'none',
                fontFamily: 'inherit',
                resize: 'vertical'
              }}
            />
          </div>

          {/* Submit button */}
          <button
            type="submit"
            class="btn btn-primary"
            style={{
              width: '100%',
              padding: '12px',
              fontSize: '1rem',
              fontWeight: 'bold',
              marginTop: '0.5rem',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px'
            }}
          >
            ✨ {lang === 'de' ? 'Lernkarten mit KI generieren' : 'Generate Cards with AI'}
          </button>
        </form>
      )}

      {/* STAGE 2: Loader spinner */}
      {isLoading && (
        <div class="card" style={{ padding: '3rem 2rem', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1.5rem' }}>
          <div style={{
            width: '64px',
            height: '64px',
            borderRadius: '50%',
            border: '5px solid var(--color-bg-secondary)',
            borderTopColor: 'var(--color-primary)',
            animation: 'spin 1.2s linear infinite'
          }}></div>
          <div>
            <h3 style={{ marginBottom: '8px' }}>{lang === 'de' ? 'Lektion wird erstellt...' : 'Generating Lecture...'}</h3>
            <p style={{ color: 'var(--color-text-secondary)', fontSize: '0.95rem' }}>{statusMessage}</p>
          </div>
          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)', maxWidth: '400px' }}>
            {lang === 'de' 
              ? 'Dies kann bis zu einer Minute dauern. Unsere KI analysiert den Text und bereitet ihn visuell und vereinfacht auf.' 
              : 'This may take up to a minute. Our AI is analyzing the material to present it in a simplified, visual format.'}
          </p>
          
          <style>{`
            @keyframes spin {
              0% { transform: rotate(0deg); }
              100% { transform: rotate(360deg); }
            }
          `}</style>
        </div>
      )}

      {/* STAGE 3: Review / Edit Extracted Content */}
      {extractedCards && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          
          <div style={{
            backgroundColor: '#E6F1FB',
            border: '1px solid #99C2EC',
            color: '#0B4277',
            padding: '12px 16px',
            borderRadius: 'var(--radius-md)',
            textAlign: 'left',
            fontSize: '0.9rem',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}>
            <span>✨</span>
            <div>
              <strong>{lang === 'de' ? 'Lernkarten erfolgreich erstellt!' : 'Cards generated successfully!'}</strong>
              <div style={{ fontSize: '0.85rem', marginTop: '2px' }}>
                {lang === 'de' 
                  ? 'Überprüfe die Begriffe und Definitionen. Du kannst sie anpassen, bevor du die Lektion endgültig speicherst.' 
                  : 'Review the terms and definitions. You can customize them before saving the lecture.'}
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {extractedCards.map((card, idx) => (
              <div
                key={idx}
                class="card"
                style={{
                  padding: '16px',
                  display: 'flex',
                  gap: '16px',
                  textAlign: 'left',
                  alignItems: 'flex-start',
                  borderLeft: `6px solid ${card.color || 'var(--color-primary)'}`
                }}
              >
                {/* SVG icon preview */}
                <div
                  style={{
                    width: '90px',
                    height: '60px',
                    borderRadius: 'var(--radius-sm)',
                    overflow: 'hidden',
                    backgroundColor: card.bg || 'var(--color-bg-secondary)',
                    flexShrink: 0
                  }}
                  dangerouslySetInnerHTML={{ __html: card.svg }}
                />

                {/* Term & Definition Edits */}
                <div style={{ flex: '1', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                  
                  {/* German side */}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    <div style={{ fontSize: '0.75rem', fontWeight: 'bold', color: 'var(--color-text-muted)' }}>DEUTSCH (Standard)</div>
                    <input
                      type="text"
                      value={card.term.de}
                      onInput={(e) => handleCardChange(idx, 'term', 'de', e.target.value)}
                      placeholder="Begriff (DE)"
                      style={{
                        padding: '6px 8px',
                        fontSize: '0.9rem',
                        fontWeight: '600',
                        borderRadius: 'var(--radius-sm)',
                        border: '1px solid var(--color-border-primary)'
                      }}
                    />
                    <textarea
                      value={card.def.de}
                      onInput={(e) => handleCardChange(idx, 'def', 'de', e.target.value)}
                      placeholder="Definition (DE)"
                      style={{
                        padding: '6px 8px',
                        fontSize: '0.8rem',
                        borderRadius: 'var(--radius-sm)',
                        border: '1px solid var(--color-border-primary)',
                        minHeight: '44px',
                        resize: 'none',
                        lineHeight: '1.3'
                      }}
                    />
                  </div>

                  {/* English side */}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    <div style={{ fontSize: '0.75rem', fontWeight: 'bold', color: 'var(--color-text-muted)' }}>ENGLISH (Fallback)</div>
                    <input
                      type="text"
                      value={card.term.en}
                      onInput={(e) => handleCardChange(idx, 'term', 'en', e.target.value)}
                      placeholder="Term (EN)"
                      style={{
                        padding: '6px 8px',
                        fontSize: '0.9rem',
                        fontWeight: '600',
                        borderRadius: 'var(--radius-sm)',
                        border: '1px solid var(--color-border-primary)'
                      }}
                    />
                    <textarea
                      value={card.def.en}
                      onInput={(e) => handleCardChange(idx, 'def', 'en', e.target.value)}
                      placeholder="Definition (EN)"
                      style={{
                        padding: '6px 8px',
                        fontSize: '0.8rem',
                        borderRadius: 'var(--radius-sm)',
                        border: '1px solid var(--color-border-primary)',
                        minHeight: '44px',
                        resize: 'none',
                        lineHeight: '1.3'
                      }}
                    />
                  </div>

                </div>
              </div>
            ))}
          </div>

          {/* Action Row */}
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end', marginTop: '1rem' }}>
            <button
              type="button"
              class="btn btn-secondary"
              onClick={() => setExtractedCards(null)}
              style={{ padding: '10px 18px', fontSize: '0.95rem' }}
            >
              ← {lang === 'de' ? 'Verwerfen' : 'Discard'}
            </button>
            <button
              type="button"
              class="btn btn-primary"
              onClick={handleSave}
              style={{ padding: '10px 24px', fontSize: '0.95rem', fontWeight: 'bold' }}
            >
              💾 {lang === 'de' ? 'Lektion speichern & freischalten' : 'Save & Unlock Lecture'}
            </button>
          </div>

        </div>
      )}
    </div>
  );
}
