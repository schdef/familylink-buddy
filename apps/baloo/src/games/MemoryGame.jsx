/* src/games/MemoryGame.jsx */
import { useState, useEffect } from 'preact/hooks';
import { shuffle } from '../utils/shuffle';
import { addStars } from '../engine/StarEconomy';
import { getLanguage, t } from '../utils/i18n';
import { ResultBox } from '../components/ResultBox';

export function MemoryGame({ cards, onComplete }) {
  const lang = getLanguage();
  const [pairs, setPairs] = useState([]);
  const [flipped, setFlipped] = useState([]);
  const [matchedIds, setMatchedIds] = useState([]);
  const [locked, setLocked] = useState(false);
  const [starsEarned, setStarsEarned] = useState(0);
  const [rounds, setRounds] = useState(0);
  const [isDone, setIsDone] = useState(false);

  // Call onComplete when done
  useEffect(() => {
    if (isDone && onComplete) {
      onComplete();
    }
  }, [isDone]);

  const getTranslated = (obj, field) => {
    if (!obj || !obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  // Initialize Memory game pairs
  const initGame = () => {
    const gamePairs = [];
    cards.forEach((c, idx) => {
      // Card 1: Term Card
      gamePairs.push({
        id: `term-${idx}`,
        pairIndex: idx,
        type: 'term',
        content: getTranslated(c, 'term'),
        color: c.color,
        bg: c.bg,
        svg: c.svg
      });
      // Card 2: Definition Card
      gamePairs.push({
        id: `def-${idx}`,
        pairIndex: idx,
        type: 'def',
        content: getTranslated(c, 'def'),
        color: c.color,
        bg: c.bg,
        svg: c.svg
      });
    });

    setPairs(shuffle(gamePairs));
    setFlipped([]);
    setMatchedIds([]);
    setLocked(false);
    setStarsEarned(0);
    setRounds(0);
    setIsDone(false);
  };

  useEffect(() => {
    if (cards.length > 0) {
      initGame();
    }
  }, [cards]);

  const handleCardClick = (card) => {
    if (locked || isDone) return;
    if (flipped.some(f => f.id === card.id)) return; // Already clicked
    if (matchedIds.includes(card.id)) return; // Already matched

    const newFlipped = [...flipped, card];
    setFlipped(newFlipped);

    if (newFlipped.length === 2) {
      setLocked(true);
      setRounds(prev => prev + 1);

      const [first, second] = newFlipped;

      if (first.pairIndex === second.pairIndex && first.id !== second.id) {
        // Success match!
        setTimeout(() => {
          setMatchedIds(prev => [...prev, first.id, second.id]);
          setFlipped([]);
          setLocked(false);
          
          // Earn 1 star per match
          setStarsEarned(prev => prev + 1);
          addStars(1);

          // Check if all pairs are matched
          if (matchedIds.length + 2 === pairs.length) {
            setIsDone(true);
          }
        }, 600);
      } else {
        // Failed match, flip back over
        setTimeout(() => {
          setFlipped([]);
          setLocked(false);
        }, 1200);
      }
    }
  };

  if (pairs.length === 0) return null;

  if (isDone) {
    return (
      <ResultBox 
        correct={cards.length} 
        total={cards.length} 
        starsEarned={starsEarned}
        onRetry={initGame}
      />
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', width: '100%' }}>
      
      {/* Top status labels */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
        <span>⭐ {starsEarned} {t('app.stars_count')}</span>
        <span>
          {t('memory.pairs_found', { found: matchedIds.length / 2, total: cards.length })}
        </span>
      </div>

      {/* Grid of memory cards */}
      <div class="mem-grid">
        {pairs.map((card) => {
          const isFlipped = flipped.some(f => f.id === card.id);
          const isMatched = matchedIds.includes(card.id);
          
          let cardClass = 'mem-card';
          if (isFlipped || isMatched) cardClass += ' flip';
          if (isMatched) cardClass += ' matched';

          return (
            <div
              key={card.id}
              class={cardClass}
              onClick={() => handleCardClick(card)}
            >
              {/* Back side of the card (Facing down) */}
              <div class="mem-front">
                <div class="mem-front-icon">
                  {/* Inline Eye SVG instead of missing Tabler icon */}
                  <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                    <circle cx="12" cy="12" r="3" />
                  </svg>
                </div>
              </div>

              {/* Front side of the card (Facing up) */}
              <div 
                class="mem-back" 
                style={{
                  display: (isFlipped || isMatched) ? 'flex' : 'none',
                  backgroundColor: isMatched ? 'var(--color-success-bg)' : 'var(--color-bg-primary)'
                }}
              >
                {card.type === 'term' ? (
                  <>
                    <div style={{ fontSize: '2rem', marginBottom: '6px' }}>📖</div>
                    <div class="mem-label" style={{ fontSize: '1rem', fontWeight: '700', wordBreak: 'break-word', padding: '0 6px' }}>
                      {card.content}
                    </div>
                  </>
                ) : (
                  <>
                    <div style={{ 
                      fontSize: '0.9rem', 
                      textAlign: 'center', 
                      padding: '6px', 
                      color: 'var(--color-text-primary)', 
                      fontWeight: '500', 
                      lineHeight: '1.3',
                      flex: 1,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center'
                    }}>
                      {card.content}
                    </div>
                    <div class="mem-label" style={{ fontSize: '0.75rem', color: 'var(--color-text-muted)', borderTop: '1px solid var(--color-border-primary)', width: '100%', paddingTop: '5px' }}>
                      {t('memory.card_question')}
                    </div>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>

    </div>
  );
}
