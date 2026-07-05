/* src/games/SpellingGame.jsx */
import { useState, useEffect } from 'preact/hooks';
import { shuffle } from '../utils/shuffle';
import { addStars } from '../engine/StarEconomy';
import { getLanguage, t } from '../utils/i18n';
import { ProgressBar } from '../components/ProgressBar';
import { FeedbackBanner } from '../components/FeedbackBanner';
import { ResultBox } from '../components/ResultBox';
import { stripSvgLabels } from '../utils/svgUtils';

export function SpellingGame({ cards, onComplete }) {
  const lang = getLanguage();
  const [words, setWords] = useState([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [slots, setSlots] = useState([]);
  const [tiles, setTiles] = useState([]);
  const [solvedCount, setSolvedCount] = useState(0);
  const [starsEarned, setStarsEarned] = useState(0);
  const [firstAttempt, setFirstAttempt] = useState(true);
  const [isDone, setIsDone] = useState(false);

  // Call onComplete when done
  useEffect(() => {
    if (isDone && onComplete) {
      onComplete();
    }
  }, [isDone]);
  const [feedback, setFeedback] = useState({ status: null, message: '' });
  const [showNextButton, setShowNextButton] = useState(false);

  const getTranslated = (obj, field) => {
    if (!obj || !obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  // Initialize word list
  useEffect(() => {
    if (cards.length > 0) {
      setWords(shuffle(cards));
      setCurrentIdx(0);
      setSolvedCount(0);
      setStarsEarned(0);
      setIsDone(false);
      setShowNextButton(false);
      setFeedback({ status: null, message: '' });
    }
  }, [cards]);

  // Set up specific word spelling screen
  useEffect(() => {
    if (words.length > 0 && currentIdx < words.length) {
      const card = words[currentIdx];
      const wordString = getTranslated(card, 'term').toUpperCase();
      
      // Empty slots
      setSlots(Array(wordString.length).fill(null));
      
      // Collect letters, add some random distractors
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      const wordLetters = wordString.split('');
      const distractors = shuffle(alphabet.split('').filter(l => !wordLetters.includes(l))).slice(0, 4);
      
      // Generate unique tile IDs
      const allTiles = shuffle([...wordLetters, ...distractors]).map((letter, i) => ({
        id: `tile-${i}`,
        letter,
        used: false
      }));

      setTiles(allTiles);
      setFirstAttempt(true);
      setFeedback({ status: null, message: '' });
      setShowNextButton(false);
    }
  }, [words, currentIdx]);

  // Click on a tile
  const handleTileClick = (tile) => {
    if (tile.used || showNextButton) return;

    // Find first empty slot
    const emptyIdx = slots.indexOf(null);
    if (emptyIdx === -1) return;

    // Update slot
    const newSlots = [...slots];
    newSlots[emptyIdx] = tile;
    setSlots(newSlots);

    // Mark tile as used
    setTiles(prev => prev.map(t => t.id === tile.id ? { ...t, used: true } : t));

    // If all filled, check spelling
    if (newSlots.indexOf(null) === -1) {
      checkSpelling(newSlots);
    }
  };

  // Click on a slot (Withdraws letter)
  const handleSlotClick = (slotIdx) => {
    if (showNextButton) return;
    
    const tile = slots[slotIdx];
    if (!tile) return;

    // Empty slot
    const newSlots = [...slots];
    newSlots[slotIdx] = null;
    setSlots(newSlots);

    // Mark tile as unused
    setTiles(prev => prev.map(t => t.id === tile.id ? { ...t, used: false } : t));
    
    // Clear feedback
    setFeedback({ status: null, message: '' });
  };

  const checkSpelling = (currentSlots) => {
    const card = words[currentIdx];
    const targetWord = getTranslated(card, 'term').toUpperCase();
    const guessedWord = currentSlots.map(s => s.letter).join('');

    if (guessedWord === targetWord) {
      setFeedback({
        status: 'correct',
        message: t('game.spelling.success', { term: getTranslated(card, 'term') })
      });
      setShowNextButton(true);
      
      if (firstAttempt) {
        setSolvedCount(prev => prev + 1);
        setStarsEarned(prev => prev + 1);
        addStars(1);
      }
    } else {
      setFeedback({
        status: 'wrong',
        message: t('game.spelling.try_again')
      });
      setFirstAttempt(false);
      
      // Auto-clear wrong slots after delay to guide kid
      setTimeout(() => {
        setSlots(prev => {
          const resetSlots = [...prev];
          const newTiles = [...tiles];
          
          resetSlots.forEach((s, idx) => {
            if (s && s.letter !== targetWord[idx]) {
              // Reset tile
              const tileIdx = newTiles.findIndex(t => t.id === s.id);
              if (tileIdx !== -1) newTiles[tileIdx].used = false;
              resetSlots[idx] = null;
            }
          });
          
          setTiles(newTiles);
          return resetSlots;
        });
        setFeedback({ status: null, message: '' });
      }, 1500);
    }
  };

  // Provide a Hint: fills the next empty slot with the correct letter
  const giveHint = () => {
    if (showNextButton) return;

    const card = words[currentIdx];
    const targetWord = getTranslated(card, 'term').toUpperCase();
    const nextEmptySlotIdx = slots.indexOf(null);
    
    if (nextEmptySlotIdx === -1) return;

    const correctLetter = targetWord[nextEmptySlotIdx];

    // Find an unused tile with this letter
    const unusedTile = tiles.find(t => t.letter === correctLetter && !t.used);
    if (unusedTile) {
      handleTileClick(unusedTile);
      setFirstAttempt(false); // Used hint, so no star reward for first attempt
    }
  };

  // Solve completely
  const solveWord = () => {
    if (showNextButton) return;

    const card = words[currentIdx];
    const targetWord = getTranslated(card, 'term').toUpperCase();

    // Map correct tiles directly to slots
    const correctSlots = targetWord.split('').map((letter, idx) => ({
      id: `solved-${idx}`,
      letter
    }));

    setSlots(correctSlots);
    setTiles(prev => prev.map(t => ({ ...t, used: true })));
    setFeedback({
      status: 'correct',
      message: t('game.spelling.success', { term: getTranslated(card, 'term') })
    });
    setFirstAttempt(false);
    setShowNextButton(true);
  };

  const handleNext = () => {
    if (currentIdx + 1 >= words.length) {
      setIsDone(true);
    } else {
      setCurrentIdx(prev => prev + 1);
    }
  };

  if (words.length === 0) return null;

  if (isDone) {
    return (
      <ResultBox 
        correct={solvedCount} 
        total={words.length} 
        starsEarned={starsEarned}
        onRetry={() => {
          setWords(shuffle(cards));
          setCurrentIdx(0);
          setSolvedCount(0);
          setStarsEarned(0);
          setIsDone(false);
          setShowNextButton(false);
          setFeedback({ status: null, message: '' });
        }}
      />
    );
  }

  const currentCard = words[currentIdx];

  return (
    <div class="buchstaben-wrap">
      
      {/* Spelling Stats header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
        <span>⭐ {starsEarned} {t('app.stars_count')}</span>
        <span>{t('game.score', { correct: solvedCount, total: currentIdx + 1 })}</span>
      </div>

      <ProgressBar current={currentIdx} total={words.length} />

      {/* SVG Image Box */}
      <div class="q-svg-box" style={{ height: '200px', marginBottom: '1rem' }}>
        <div 
          dangerouslySetInnerHTML={{ __html: stripSvgLabels(currentCard.svg) }} 
          style={{ width: '100%', height: '100%' }}
        />
      </div>

      {/* Muted Definition hint */}
      <div style={{
        backgroundColor: 'var(--color-bg-secondary)',
        borderRadius: 'var(--radius-md)',
        padding: '10px 14px',
        fontSize: '0.85rem',
        color: 'var(--color-text-secondary)',
        marginBottom: '1rem',
        border: '1px solid var(--color-border-primary)',
        lineHeight: '1.4'
      }}>
        {getTranslated(currentCard, 'def')}
      </div>

      {/* Spelling Slots */}
      <div class="b-slots">
        {slots.map((slot, idx) => {
          const isCorrect = slot && feedback.status === 'correct';
          const isWrong = slot && feedback.status === 'wrong';
          
          let slotClass = 'b-slot';
          if (slot) slotClass += ' filled';
          if (isCorrect) slotClass += ' correct-s';
          if (isWrong) slotClass += ' wrong-s';

          return (
            <button
              key={idx}
              type="button"
              class={slotClass}
              onClick={() => handleSlotClick(idx)}
            >
              {slot ? slot.letter : ''}
            </button>
          );
        })}
      </div>

      {/* Interactive Tile Buttons */}
      <div class="b-tiles">
        {tiles.map((tile) => (
          <button
            key={tile.id}
            type="button"
            class={`b-tile ${tile.used ? 'used' : ''}`}
            disabled={tile.used || showNextButton}
            onClick={() => handleTileClick(tile)}
          >
            {tile.letter}
          </button>
        ))}
      </div>

      {/* Actions (Tipp, Auflösung) */}
      {!showNextButton && (
        <div class="b-action-row">
          <button type="button" class="btn btn-warning" onClick={giveHint}>
            💡 {t('game.spelling.hint')}
          </button>
          <button type="button" class="btn btn-secondary" onClick={solveWord}>
            {t('game.spelling.solve')}
          </button>
        </div>
      )}

      {/* Correct / Incorrect Banners */}
      <FeedbackBanner status={feedback.status} message={feedback.message} />

      {/* Next button */}
      {showNextButton && (
        <button 
          type="button" 
          class="btn btn-primary btn-full" 
          onClick={handleNext}
          style={{ marginTop: '0.5rem' }}
        >
          {t('game.next')}
        </button>
      )}

    </div>
  );
}
