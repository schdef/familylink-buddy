/* src/games/rewards/BubblePop.jsx
 * Reward mini-game: bubbles float upwards — tap/click to pop them before they escape!
 * No canvas needed — pure CSS + Preact state animation.
 */
import { useState, useEffect, useRef, useCallback } from 'preact/hooks';
import { t } from '../../utils/i18n';

const STAR_COST = 10;
const GAME_DURATION = 30; // seconds
const SPAWN_INTERVAL = 900; // ms between new bubbles
const BUBBLE_COLORS = [
  '#ED93B1', '#85B7EB', '#9FE1CB', '#FAC775', '#AFA9EC', '#F0997B'
];

let nextId = 0;

function makeBubble() {
  const size = 40 + Math.random() * 35; // 40–75px
  return {
    id: nextId++,
    x: 5 + Math.random() * 82, // % from left (leaves margin)
    size,
    color: BUBBLE_COLORS[Math.floor(Math.random() * BUBBLE_COLORS.length)],
    speed: 3.5 + Math.random() * 3, // seconds to cross viewport
    popped: false,
    born: Date.now()
  };
}

export function BubblePop({ starBalance, onSpendStars, onExit }) {
  const [started, setStarted] = useState(false);
  const [bubbles, setBubbles] = useState([]);
  const [score, setScore] = useState(0);
  const [timeLeft, setTimeLeft] = useState(GAME_DURATION);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  const spawnRef = useRef(null);
  const timerRef = useRef(null);
  const containerRef = useRef(null);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearInterval(spawnRef.current);
      clearInterval(timerRef.current);
    };
  }, []);

  const startGame = () => {
    if (starBalance < STAR_COST) {
      setError(`Du brauchst ${STAR_COST} Sterne! Löse erst Übungen.`);
      return;
    }
    onSpendStars(STAR_COST);
    setError('');
    setScore(0);
    setTimeLeft(GAME_DURATION);
    setDone(false);
    setBubbles([makeBubble()]);
    setStarted(true);

    // Spawn bubbles
    spawnRef.current = setInterval(() => {
      setBubbles(prev => [...prev.filter(b => !b.popped), makeBubble()]);
    }, SPAWN_INTERVAL);

    // Count down timer
    timerRef.current = setInterval(() => {
      setTimeLeft(prev => {
        if (prev <= 1) {
          clearInterval(spawnRef.current);
          clearInterval(timerRef.current);
          setDone(true);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  };

  const popBubble = useCallback((id) => {
    setBubbles(prev => prev.map(b => b.id === id ? { ...b, popped: true } : b));
    setScore(prev => prev + 1);
    // Remove popped bubble after animation
    setTimeout(() => {
      setBubbles(prev => prev.filter(b => b.id !== id));
    }, 300);
  }, []);

  const resetGame = () => {
    clearInterval(spawnRef.current);
    clearInterval(timerRef.current);
    setBubbles([]);
    setScore(0);
    setTimeLeft(GAME_DURATION);
    setDone(false);
    setStarted(false);
    setError('');
  };

  const getScoreMessage = () => {
    if (score >= 20) return '🏆 Weltklasse!';
    if (score >= 12) return '⭐ Super gemacht!';
    if (score >= 6) return '👍 Gut!';
    return '💪 Üb weiter!';
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1rem' }}>
      <h2 style={{ fontSize: '1.25rem' }}>🫧 Blasen-Popper</h2>

      {!started && !done && (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1rem', textAlign: 'center', padding: '1rem' }}>
          <p style={{ fontSize: '0.95rem', color: 'var(--color-text-secondary)' }}>
            Tippe auf die Blasen bevor sie verschwinden!<br />
            Du hast <strong>{GAME_DURATION} Sekunden</strong>.<br />
            Kostet <strong>{STAR_COST} ⭐</strong> pro Runde.
          </p>
          {/* Decorative preview bubbles */}
          <div style={{ display: 'flex', gap: '12px', margin: '0.5rem 0' }}>
            {BUBBLE_COLORS.slice(0, 4).map((c, i) => (
              <div key={i} style={{
                width: `${35 + i * 5}px`, height: `${35 + i * 5}px`,
                borderRadius: '50%', backgroundColor: c,
                opacity: 0.75,
                boxShadow: `inset -4px -4px 8px rgba(0,0,0,0.12), inset 3px 3px 6px rgba(255,255,255,0.5)`
              }} />
            ))}
          </div>
          {error && <p style={{ color: 'var(--color-error)', fontWeight: '600', fontSize: '0.9rem' }}>{error}</p>}
          <button type="button" class="btn btn-primary" onClick={startGame}>
            🎮 Spielen ({STAR_COST} ⭐)
          </button>
          <button type="button" class="btn btn-ghost" onClick={onExit} style={{ fontSize: '0.85rem' }}>
            Zurück
          </button>
        </div>
      )}

      {done && (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1rem', textAlign: 'center' }}>
          <div style={{ fontSize: '3rem' }}>{score >= 12 ? '🎉' : '😊'}</div>
          <h3>{getScoreMessage()}</h3>
          <p style={{ color: 'var(--color-text-secondary)' }}>
            Du hast <strong>{score}</strong> Blasen geplatzt!
          </p>
          <div style={{ display: 'flex', gap: '10px' }}>
            <button type="button" class="btn btn-primary" onClick={resetGame}>
              🔄 Nochmal ({STAR_COST} ⭐)
            </button>
            <button type="button" class="btn btn-ghost" onClick={onExit}>
              Zurück
            </button>
          </div>
        </div>
      )}

      {started && !done && (
        <>
          {/* HUD */}
          <div style={{
            display: 'flex', gap: '1.5rem', alignItems: 'center',
            fontSize: '1rem', fontWeight: '700'
          }}>
            <span style={{ color: 'var(--color-warning)' }}>💥 {score}</span>
            <span style={{
              color: timeLeft <= 10 ? 'var(--color-error)' : 'var(--color-text-secondary)',
              transition: 'color 0.3s'
            }}>
              ⏱ {timeLeft}s
            </span>
          </div>

          {/* Game Arena */}
          <div
            ref={containerRef}
            style={{
              position: 'relative',
              width: '100%',
              maxWidth: '380px',
              height: '340px',
              backgroundColor: 'var(--color-bg-secondary)',
              border: '1px solid var(--color-border-primary)',
              borderRadius: 'var(--radius-lg)',
              overflow: 'hidden',
              touchAction: 'none'
            }}
          >
            <style>{`
              @keyframes float-up {
                from { bottom: -80px; opacity: 1; }
                to   { bottom: 110%; opacity: 0.6; }
              }
              @keyframes pop-out {
                0%   { transform: scale(1); opacity: 1; }
                50%  { transform: scale(1.5); opacity: 0.6; }
                100% { transform: scale(0); opacity: 0; }
              }
            `}</style>

            {bubbles.map(bubble => (
              <div
                key={bubble.id}
                onClick={() => popBubble(bubble.id)}
                style={{
                  position: 'absolute',
                  left: `${bubble.x}%`,
                  width: `${bubble.size}px`,
                  height: `${bubble.size}px`,
                  borderRadius: '50%',
                  backgroundColor: bubble.color,
                  boxShadow: `inset -6px -6px 12px rgba(0,0,0,0.1), inset 4px 4px 8px rgba(255,255,255,0.5)`,
                  cursor: 'pointer',
                  animation: bubble.popped
                    ? 'pop-out 0.3s ease-out forwards'
                    : `float-up ${bubble.speed}s linear forwards`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: `${bubble.size * 0.45}px`,
                  userSelect: 'none'
                }}
              >
                {bubble.popped ? '💥' : ''}
              </div>
            ))}
          </div>

          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)' }}>
            Tippe schnell auf die Blasen!
          </p>
        </>
      )}
    </div>
  );
}
