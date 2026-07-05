/* src/games/rewards/PixelArt.jsx
 * Reward mini-game: tap/click cells to color them and reveal a hidden picture.
 * Pure front-end, no state persistence needed — just fun!
 */
import { useState, useEffect, useRef } from 'preact/hooks';

// Pre-defined pixel art templates (8×8 grids)
// Each number maps to a color index (0 = background, 1-5 = palette)
const TEMPLATES = [
  {
    name: 'Bär 🐻',
    palette: ['#F5F4F0', '#8B5E3C', '#2C2C2A', '#F4C97A', '#D6905E', '#FFFFFF'],
    grid: [
      [0,1,1,0,0,1,1,0],
      [1,1,1,1,1,1,1,1],
      [1,4,1,1,1,1,4,1],
      [1,1,2,1,1,2,1,1],
      [1,1,1,3,3,1,1,1],
      [1,1,1,1,1,1,1,1],
      [0,1,1,1,1,1,1,0],
      [0,0,1,1,1,1,0,0],
    ]
  },
  {
    name: 'Stern ⭐',
    palette: ['#F5F4F0', '#F4C97A', '#C78D2B', '#FAEEDA', '#EF9F27', '#FFFFFF'],
    grid: [
      [0,0,0,1,1,0,0,0],
      [0,0,0,4,4,0,0,0],
      [3,3,2,4,4,2,3,3],
      [0,1,4,4,4,4,1,0],
      [0,0,4,4,4,4,0,0],
      [0,4,4,0,0,4,4,0],
      [4,4,0,0,0,0,4,4],
      [4,0,0,0,0,0,0,4],
    ]
  },
  {
    name: 'Herz ❤️',
    palette: ['#F5F4F0', '#E84B4B', '#C03030', '#F0A0A0', '#FF6B6B', '#FFFFFF'],
    grid: [
      [0,1,1,0,0,1,1,0],
      [1,4,4,1,1,4,4,1],
      [1,4,4,4,4,4,4,1],
      [1,4,4,4,4,4,4,1],
      [0,1,4,4,4,4,1,0],
      [0,0,1,4,4,1,0,0],
      [0,0,0,1,1,0,0,0],
      [0,0,0,0,0,0,0,0],
    ]
  }
];

const COLS = 8;
const ROWS = 8;
const STAR_COST = 10;

export function PixelArt({ starBalance, onSpendStars, onExit }) {
  const [templateIdx, setTemplateIdx] = useState(() => Math.floor(Math.random() * TEMPLATES.length));
  const [painted, setPainted] = useState(() => Array(ROWS).fill(null).map(() => Array(COLS).fill(false)));
  const [activeColorIdx, setActiveColorIdx] = useState(1);
  const [completed, setCompleted] = useState(false);
  const [started, setStarted] = useState(false);
  const [error, setError] = useState('');
  const isPainting = useRef(false);

  const template = TEMPLATES[templateIdx];

  // Check completion after each paint
  useEffect(() => {
    if (!started) return;
    const allDone = painted.every((row, r) =>
      row.every((cell, c) => {
        const target = template.grid[r][c];
        return target === 0 ? true : cell; // bg cells don't need painting
      })
    );
    if (allDone) setCompleted(true);
  }, [painted, started, template]);

  const handleStart = () => {
    if (starBalance < STAR_COST) {
      setError(`Du brauchst ${STAR_COST} Sterne! Löse erst Übungen.`);
      return;
    }
    onSpendStars(STAR_COST);
    setStarted(true);
    setError('');
  };

  const paintCell = (r, c) => {
    if (!started || completed) return;
    const target = template.grid[r][c];
    if (target === 0) return; // skip background
    setPainted(prev => {
      const next = prev.map(row => [...row]);
      next[r][c] = true;
      return next;
    });
  };

  const handleReset = () => {
    const nextIdx = (templateIdx + 1) % TEMPLATES.length;
    setTemplateIdx(nextIdx);
    setPainted(Array(ROWS).fill(null).map(() => Array(COLS).fill(false)));
    setCompleted(false);
    setStarted(false);
    setActiveColorIdx(1);
    setError('');
  };

  const CELL = 36; // px per cell

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1.25rem' }}>
      <h2 style={{ fontSize: '1.25rem' }}>🎨 Pixel-Kunst: {template.name}</h2>

      {!started ? (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          gap: '1rem', padding: '1.5rem', textAlign: 'center'
        }}>
          <p style={{ fontSize: '0.95rem', color: 'var(--color-text-secondary)' }}>
            Male das Bild aus, indem du die Felder antippst!<br />
            Kostet <strong>{STAR_COST} ⭐</strong> pro Runde.
          </p>
          {/* Preview of target image */}
          <div style={{
            display: 'grid',
            gridTemplateColumns: `repeat(${COLS}, 18px)`,
            gap: '2px',
            opacity: 0.6
          }}>
            {template.grid.map((row, r) =>
              row.map((val, c) => (
                <div key={`${r}-${c}`} style={{
                  width: '18px', height: '18px',
                  backgroundColor: template.palette[val],
                  borderRadius: '2px',
                  border: val === 0 ? 'none' : '1px solid rgba(0,0,0,0.08)'
                }} />
              ))
            )}
          </div>
          {error && <p style={{ color: 'var(--color-error)', fontWeight: '600', fontSize: '0.9rem' }}>{error}</p>}
          <button type="button" class="btn btn-primary" onClick={handleStart}>
            🎮 Spielen ({STAR_COST} ⭐)
          </button>
          <button type="button" class="btn btn-ghost" onClick={onExit} style={{ fontSize: '0.85rem' }}>
            Zurück
          </button>
        </div>
      ) : completed ? (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1rem', textAlign: 'center' }}>
          <div style={{ fontSize: '3rem' }}>🎉</div>
          <h3>Fertig! Super gemacht!</h3>
          <div style={{
            display: 'grid',
            gridTemplateColumns: `repeat(${COLS}, ${CELL}px)`,
            gap: '3px'
          }}>
            {template.grid.map((row, r) =>
              row.map((val, c) => (
                <div key={`${r}-${c}`} style={{
                  width: `${CELL}px`, height: `${CELL}px`,
                  backgroundColor: template.palette[val],
                  borderRadius: '4px',
                  border: '1px solid rgba(0,0,0,0.06)',
                  transition: 'background-color 0.2s'
                }} />
              ))
            )}
          </div>
          <div style={{ display: 'flex', gap: '10px' }}>
            <button type="button" class="btn btn-primary" onClick={handleReset}>
              🎨 Nächstes Bild ({STAR_COST} ⭐)
            </button>
            <button type="button" class="btn btn-ghost" onClick={onExit}>
              Zurück
            </button>
          </div>
        </div>
      ) : (
        <>
          {/* Color Picker palette */}
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginRight: '4px' }}>Farbe:</span>
            {template.palette.slice(1).map((color, idx) => (
              <button
                key={idx}
                type="button"
                aria-label={`Farbe ${idx + 1}`}
                onClick={() => setActiveColorIdx(idx + 1)}
                style={{
                  width: '28px', height: '28px',
                  borderRadius: '50%',
                  backgroundColor: color,
                  border: activeColorIdx === idx + 1
                    ? '3px solid var(--color-text-primary)'
                    : '2px solid rgba(0,0,0,0.12)',
                  cursor: 'pointer',
                  transition: 'transform 0.1s',
                  transform: activeColorIdx === idx + 1 ? 'scale(1.25)' : 'scale(1)'
                }}
              />
            ))}
          </div>

          {/* Painting Grid */}
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: `repeat(${COLS}, ${CELL}px)`,
              gap: '3px',
              touchAction: 'none',
              userSelect: 'none'
            }}
            onMouseLeave={() => { isPainting.current = false; }}
          >
            {template.grid.map((row, r) =>
              row.map((target, c) => {
                const isBg = target === 0;
                const isPainted = painted[r][c];
                const cellColor = isPainted ? template.palette[target] : (isBg ? 'transparent' : '#E8E6E0');

                return (
                  <div
                    key={`${r}-${c}`}
                    style={{
                      width: `${CELL}px`,
                      height: `${CELL}px`,
                      backgroundColor: cellColor,
                      borderRadius: '4px',
                      border: isBg ? 'none' : `1px solid ${isPainted ? 'rgba(0,0,0,0.08)' : 'var(--color-border-primary)'}`,
                      cursor: isBg ? 'default' : 'pointer',
                      transition: 'background-color 0.15s'
                    }}
                    onMouseDown={() => { isPainting.current = true; paintCell(r, c); }}
                    onMouseUp={() => { isPainting.current = false; }}
                    onMouseEnter={() => { if (isPainting.current) paintCell(r, c); }}
                    onTouchStart={(e) => { e.preventDefault(); paintCell(r, c); }}
                  />
                );
              })
            )}
          </div>

          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)' }}>
            Tippe auf die grauen Felder zum Ausmalen!
          </p>

          <button type="button" class="btn btn-ghost" onClick={onExit} style={{ fontSize: '0.85rem' }}>
            Zurück zu den Lektionen
          </button>
        </>
      )}
    </div>
  );
}
