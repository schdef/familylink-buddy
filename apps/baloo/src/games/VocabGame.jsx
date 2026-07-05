/* src/games/VocabGame.jsx */
import { useState } from 'preact/hooks';
import { getLanguage, t } from '../utils/i18n';

export function VocabGame({ cards, onComplete }) {
  const lang = getLanguage();
  const [isDone, setIsDone] = useState(false);

  const getTranslated = (obj, field) => {
    if (!obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  const handleDone = () => {
    setIsDone(true);
    if (onComplete) {
      onComplete();
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem', width: '100%', alignItems: 'center' }}>
      
      {/* Grid of vocab cards */}
      <div class="vocab-grid" style={{ width: '100%' }}>
        {cards.map((card, idx) => {
          return (
            <div 
              key={idx} 
              class="vocab-card"
              style={{
                borderColor: 'var(--color-border-primary)',
                backgroundColor: 'var(--color-bg-primary)'
              }}
            >
              {/* SVG Illustration Container */}
              <div 
                dangerouslySetInnerHTML={{ __html: card.svg }} 
                style={{
                  width: '100%',
                  height: '90px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  overflow: 'hidden',
                  backgroundColor: card.bg || 'var(--color-bg-secondary)'
                }}
              />
              
              {/* Card content text */}
              <div class="vocab-body">
                <div class="vocab-term">
                  {getTranslated(card, 'term')}
                </div>
                <div class="vocab-def">
                  {getTranslated(card, 'def')}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Done Reading Button */}
      {!isDone ? (
        <button
          type="button"
          class="btn btn-primary"
          onClick={handleDone}
          style={{ padding: '12px 24px', fontSize: '1rem', fontWeight: 'bold', marginTop: '0.5rem', minWidth: '220px' }}
        >
          👍 {lang === 'de' ? 'Ich habe alle Karten gelesen!' : 'I read all the cards!'}
        </button>
      ) : (
        <div style={{
          backgroundColor: 'var(--color-success-bg, #E6F5EE)',
          color: 'var(--color-success, #1D9E75)',
          padding: '12px 24px',
          borderRadius: 'var(--radius-md)',
          fontWeight: 'bold',
          fontSize: '1rem',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          marginTop: '0.5rem'
        }}>
          <span>✅</span>
          <span>{lang === 'de' ? 'Prima gemacht!' : 'Great job!'}</span>
        </div>
      )}
      
    </div>
  );
}

