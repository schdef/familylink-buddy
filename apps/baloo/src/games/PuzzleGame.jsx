/* src/games/PuzzleGame.jsx */
import { useState, useEffect, useRef } from 'preact/hooks';
import { addStars } from '../engine/StarEconomy';
import { getLanguage, t } from '../utils/i18n';
import { FeedbackBanner } from '../components/FeedbackBanner';

export function PuzzleGame({ topicId, puzzlePieces, onComplete }) {
  const lang = getLanguage();
  const arenaRef = useRef(null);

  const [snappedCount, setSnappedCount] = useState(0);
  const [currentTargetIdx, setCurrentTargetIdx] = useState(0);
  const [piecesState, setPiecesState] = useState([]);
  const [feedback, setFeedback] = useState({ status: null, message: '' });
  const [isDone, setIsDone] = useState(false);

  // Call onComplete when done
  useEffect(() => {
    if (isDone && onComplete) {
      onComplete();
    }
  }, [isDone]);
  const [highlightedId, setHighlightedId] = useState(null);

  // Dragging states
  const dragInfo = useRef({
    activePieceId: null,
    offsetX: 0,
    offsetY: 0,
    startX: 0,
    startY: 0,
    x: 0,
    y: 0
  });

  const getTranslated = (obj, field) => {
    if (!obj || !obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  // Initialize/reset puzzle pieces
  const initPuzzle = () => {
    setSnappedCount(0);
    setCurrentTargetIdx(0);
    setIsDone(false);
    setFeedback({ status: null, message: '' });
    setHighlightedId(null);

    // Initialize state with random positions in the tray area
    const initialized = puzzlePieces.map((p, idx) => ({
      ...p,
      index: idx,
      snapped: false,
      x: null, // Relative to arena when dragging, null if in tray
      y: null,
      inArena: false
    }));
    setPiecesState(initialized);
  };

  useEffect(() => {
    if (puzzlePieces && puzzlePieces.length > 0) {
      initPuzzle();
    }
  }, [puzzlePieces, topicId]);

  const currentTargetPiece = piecesState[currentTargetIdx];

  // Specific SVGs for the Eye pieces
  const renderEyePieceSVG = (id, strokeColor, fillColor) => {
    const s = 1.0;
    const x = 40;
    const y = 40;

    switch (id) {
      case 'sclera':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <ellipse cx="40" cy="40" rx="36" ry="34" fill="#f0ece0" stroke="#b4b2a9" stroke-width="2" />
            <text x="40" y="74" text-anchor="middle" font-size="8" fill="#5F5E5A">{t('game.tab.puzzle')}</text>
          </svg>
        );
      case 'choroid':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <ellipse cx="40" cy="40" rx="32" ry="30" fill="#D85A30" opacity="0.8" stroke="#993C1D" stroke-width="2" />
          </svg>
        );
      case 'retina':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <ellipse cx="40" cy="40" rx="28" ry="26" fill="#FAC775" opacity="0.8" stroke="#EF9F27" stroke-width="2" />
          </svg>
        );
      case 'vitreous':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <ellipse cx="40" cy="40" rx="24" ry="22" fill="#9FE1CB" opacity="0.7" stroke="#1D9E75" stroke-width="2" />
          </svg>
        );
      case 'lens':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <ellipse cx="40" cy="40" rx="12" ry="24" fill="#85B7EB" stroke="#185FA5" stroke-width="2" />
          </svg>
        );
      case 'iris':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <circle cx="40" cy="40" r="22" fill="#ED93B1" stroke="#D4537E" stroke-width="2" />
          </svg>
        );
      case 'pupil':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <circle cx="40" cy="40" r="20" fill="#2C2C2A" />
            <circle cx="33" cy="33" r="5" fill="white" opacity="0.4" />
          </svg>
        );
      case 'cornea':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <path d="M45,15 Q20,40 45,65" fill="none" stroke="#AFA9EC" stroke-width="10" stroke-linecap="round" opacity="0.9" />
            <path d="M45,15 Q20,40 45,65" fill="none" stroke="white" stroke-width="4" stroke-linecap="round" opacity="0.7" />
          </svg>
        );
      case 'opticnerve':
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <rect x="20" y="20" width="40" height="40" rx="6" fill="#D85A30" opacity="0.85" stroke="#993C1D" stroke-width="2" />
          </svg>
        );
      default:
        // Generic fallback box
        return (
          <svg viewBox="0 0 80 80" width="70" height="70">
            <rect x="10" y="10" width="60" height="60" rx="6" fill={fillColor || '#EAE6DF'} stroke={strokeColor || '#95908A'} stroke-width="2" />
          </svg>
        );
    }
  };

  // SVG representation in the final arena
  const renderArenaEyePiece = (piece, scale = 1.6) => {
    const x = 160;
    const y = 160;

    switch (piece.id) {
      case 'sclera':
        return <ellipse cx={x} cy={y} rx={52 * scale} ry={50 * scale} fill="#f0ece0" stroke="#b4b2a9" stroke-width="2" />;
      case 'choroid':
        return <ellipse cx={x} cy={y} rx={46 * scale} ry={44 * scale} fill="#D85A30" opacity="0.7" stroke="#993C1D" stroke-width="1.5" />;
      case 'retina':
        return <ellipse cx={x} cy={y} rx={40 * scale} ry={38 * scale} fill="#FAC775" opacity="0.6" stroke="#EF9F27" stroke-width="2" />;
      case 'vitreous':
        return <ellipse cx={x} cy={y} rx={32 * scale} ry={30 * scale} fill="#9FE1CB" opacity="0.5" stroke="#1D9E75" stroke-width="1.5" />;
      case 'lens':
        return <ellipse cx={x - 17 * scale} cy={y} rx={9 * scale} ry={18 * scale} fill="#85B7EB" opacity="0.85" stroke="#185FA5" stroke-width="2" />;
      case 'iris':
        return <circle cx={x - 33 * scale} cy={y} r={17 * scale} fill="#ED93B1" stroke="#D4537E" stroke-width="2" />;
      case 'pupil':
        return <circle cx={x - 33 * scale} cy={y} r={8 * scale} fill="#1a1a18" />;
      case 'cornea':
        return (
          <>
            <path d={`M${x - 48 * scale},${y - 18 * scale} Q${x - 68 * scale},${y} ${x - 48 * scale},${y + 18 * scale}`} fill="none" stroke="#AFA9EC" stroke-width={6 * scale} stroke-linecap="round" opacity="0.8" />
            <path d={`M${x - 48 * scale},${y - 18 * scale} Q${x - 68 * scale},${y} ${x - 48 * scale},${y + 18 * scale}`} fill="none" stroke="white" stroke-width={2.5 * scale} stroke-linecap="round" opacity="0.6" />
          </>
        );
      case 'opticnerve':
        return <rect x={x + 38 * scale} y={y - 20 * scale} width={18 * scale} height={40 * scale} rx={4 * scale} fill="#D85A30" opacity="0.8" stroke="#993C1D" stroke-width="1.5" />;
      default:
        // Generic circle layer placement fallback
        return <circle cx={x} cy={y} r={(30 - piece.index * 2) * scale} fill={piece.color} opacity="0.7" />;
    }
  };

  // Drag handles
  const handleStartDrag = (e, piece) => {
    if (piece.snapped || isDone) return;
    e.preventDefault();

    const clientX = e.type.startsWith('touch') ? e.touches[0].clientX : e.clientX;
    const clientY = e.type.startsWith('touch') ? e.touches[0].clientY : e.clientY;

    const el = e.currentTarget;
    const rect = el.getBoundingClientRect();
    const arenaRect = arenaRef.current.getBoundingClientRect();

    dragInfo.current = {
      activePieceId: piece.id,
      offsetX: clientX - rect.left,
      offsetY: clientY - rect.top,
      startX: clientX - arenaRect.left,
      startY: clientY - arenaRect.top
    };

    // Set initial position
    updatePiecePos(clientX, clientY);

    if (e.type.startsWith('touch')) {
      document.addEventListener('touchmove', handleDragMove, { passive: false });
      document.addEventListener('touchend', handleDragEnd);
    } else {
      document.addEventListener('mousemove', handleDragMove);
      document.addEventListener('mouseup', handleDragEnd);
    }
  };

  const handleDragMove = (e) => {
    if (!dragInfo.current.activePieceId) return;
    if (e.cancelable) e.preventDefault();

    const clientX = e.type.startsWith('touch') ? e.touches[0].clientX : e.clientX;
    const clientY = e.type.startsWith('touch') ? e.touches[0].clientY : e.clientY;

    updatePiecePos(clientX, clientY);
  };

  const updatePiecePos = (clientX, clientY) => {
    const arenaRect = arenaRef.current.getBoundingClientRect();
    const x = clientX - arenaRect.left - dragInfo.current.offsetX;
    const y = clientY - arenaRect.top - dragInfo.current.offsetY;

    dragInfo.current.x = x;
    dragInfo.current.y = y;

    setPiecesState(prev => prev.map(p => 
      p.id === dragInfo.current.activePieceId
        ? { ...p, x, y, inArena: true }
        : p
    ));
  };

  const handleDragEnd = (e) => {
    const activeId = dragInfo.current.activePieceId;
    if (!activeId) return;

    // Clean listeners
    document.removeEventListener('mousemove', handleDragMove);
    document.removeEventListener('mouseup', handleDragEnd);
    document.removeEventListener('touchmove', handleDragMove);
    document.removeEventListener('touchend', handleDragEnd);

    // Evaluate drop position relative to target
    const x = dragInfo.current.x;
    const y = dragInfo.current.y;
    const currentPiece = piecesState.find(p => p.id === activeId);
    
    // Arena center coords
    const arenaCenterX = 160;
    const arenaCenterY = 160;

    // Piece center coords
    const pieceWidth = 70;
    const pieceHeight = 70;
    const pieceCenterX = x + pieceWidth / 2;
    const pieceCenterY = y + pieceHeight / 2;

    // Distance from center of arena
    const dist = Math.sqrt((pieceCenterX - arenaCenterX) ** 2 + (pieceCenterY - arenaCenterY) ** 2);
    
    const isTarget = currentTargetPiece && currentTargetPiece.id === activeId;

    if (isTarget && dist < 70) {
      // Snap to correct position
      setPiecesState(prev => prev.map(p => 
        p.id === activeId
          ? { ...p, snapped: true, x: arenaCenterX - pieceWidth / 2, y: arenaCenterY - pieceHeight / 2 }
          : p
      ));

      setSnappedCount(prev => prev + 1);
      setFeedback({
        status: 'correct',
        message: t('game.feedback.puzzle_snapped', { part: getTranslated(currentPiece, 'name') })
      });

      // Advance target index
      const nextIdx = currentTargetIdx + 1;
      setCurrentTargetIdx(nextIdx);

      if (nextIdx >= puzzlePieces.length) {
        setIsDone(true);
        addStars(5); // Completion bonus stars!
      } else {
        setTimeout(() => {
          setFeedback({ status: null, message: '' });
        }, 1200);
      }
    } else {
      // Return to tray
      setPiecesState(prev => prev.map(p => 
        p.id === activeId
          ? { ...p, x: null, y: null, inArena: false }
          : p
      ));

      if (!isTarget) {
        setFeedback({
          status: 'wrong',
          message: t('game.feedback.wrong', { correct: getTranslated(currentTargetPiece, 'name') })
        });
      } else {
        setFeedback({
          status: 'wrong',
          message: 'Fast! Lege das Teil genau in die Mitte.'
        });
      }
    }

    dragInfo.current.activePieceId = null;
  };

  // Provide a Hint: highlights the required piece
  const giveHint = () => {
    if (!currentTargetPiece) return;
    setHighlightedId(currentTargetPiece.id);
    
    setFeedback({
      status: 'correct',
      message: `Tipp: Ziehe die/den ${getTranslated(currentTargetPiece, 'name')} in die Mitte!`
    });

    setTimeout(() => {
      setHighlightedId(null);
    }, 2000);
  };

  // Solve completely
  const solvePuzzle = () => {
    setPiecesState(prev => prev.map(p => ({
      ...p,
      snapped: true,
      inArena: true,
      x: 160 - 35,
      y: 160 - 35
    })));
    setSnappedCount(puzzlePieces.length);
    setCurrentTargetIdx(puzzlePieces.length);
    setIsDone(true);
    setFeedback({
      status: 'correct',
      message: t('game.puzzle.solved_all')
    });
  };

  return (
    <div class="puz-outer">
      
      {/* Target exercise display instruction */}
      <div class="puz-task">
        {isDone ? (
          t('game.puzzle.solved_all')
        ) : (
          currentTargetPiece ? (
            t('game.puzzle.next_part', { 
              name: getTranslated(currentTargetPiece, 'name')
            })
          ) : (
            t('game.puzzle.task')
          )
        )}
      </div>

      {/* Progress indicators */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        fontSize: '0.8rem',
        color: 'var(--color-text-secondary)',
        marginBottom: '10px'
      }}>
        <span>Fortschritt:</span>
        <span>{snappedCount} / {puzzlePieces.length}</span>
      </div>

      {/* Interactive Arena */}
      <div 
        ref={arenaRef}
        class="puz-arena" 
        style={{
          position: 'relative',
          backgroundColor: 'var(--color-bg-secondary)',
          border: '1px solid var(--color-border-primary)',
          borderRadius: 'var(--radius-lg)'
        }}
      >
        {/* Layered assembly inside the SVG */}
        <svg width="320" height="320" style={{ position: 'absolute', top: 0, left: 0, zIndex: 1, pointerEvents: 'none' }}>
          {/* Only draw layers that have snapped */}
          {piecesState.map((piece) => {
            if (!piece.snapped) return null;
            return renderArenaEyePiece(piece);
          })}
        </svg>

        {/* Dragging elements when inside the arena boundaries */}
        {piecesState.map((piece) => {
          if (!piece.inArena || piece.snapped) return null;
          return (
            <div
              key={`drag-${piece.id}`}
              style={{
                position: 'absolute',
                left: `${piece.x}px`,
                top: `${piece.y}px`,
                zIndex: 100,
                cursor: 'grabbing'
              }}
            >
              {renderEyePieceSVG(piece.id, piece.stroke, piece.color)}
            </div>
          );
        })}
      </div>

      {/* The Tray containing pieces yet to be snapped */}
      <div class="puz-tray">
        {piecesState.map((piece) => {
          if (piece.inArena || piece.snapped) return null;
          
          const isHighlighted = highlightedId === piece.id;
          
          return (
            <div
              key={piece.id}
              role="button"
              aria-label={getTranslated(piece, 'name')}
              class={`puz-piece ${isHighlighted ? 'highlight' : ''}`}
              style={{
                position: 'relative',
                cursor: 'grab',
                border: isHighlighted ? '2px solid var(--color-info)' : '1px solid transparent',
                borderRadius: 'var(--radius-sm)',
                boxShadow: isHighlighted ? 'var(--color-shadow-hover)' : 'none',
                animation: isHighlighted ? 'pulse 1s infinite' : 'none'
              }}
              onTouchStart={(e) => handleStartDrag(e, piece)}
              onMouseDown={(e) => handleStartDrag(e, piece)}
            >
              {renderEyePieceSVG(piece.id, piece.stroke, piece.color)}
              
              <div style={{
                fontSize: '0.65rem',
                fontWeight: '600',
                color: 'var(--color-text-secondary)',
                marginTop: '2px',
                textAlign: 'center',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                width: '70px'
              }}>
                {getTranslated(piece, 'name')}
              </div>
            </div>
          );
        })}
      </div>

      {/* Actions (Tipp, Auflösung, Reset) */}
      {!isDone && (
        <div class="puz-action-row">
          <button type="button" class="btn btn-warning" onClick={giveHint}>
            💡 {t('game.spelling.hint')}
          </button>
          <button type="button" class="btn btn-secondary" onClick={solvePuzzle}>
            {t('game.spelling.solve')}
          </button>
        </div>
      )}

      {/* Feedback Banner */}
      <FeedbackBanner status={feedback.status} message={feedback.message} />

      {/* Reset complete puzzle */}
      {isDone && (
        <button 
          type="button" 
          class="btn btn-primary btn-full" 
          onClick={initPuzzle}
          style={{ marginTop: '0.5rem' }}
        >
          🔄 {t('memory.play_again')}
        </button>
      )}

    </div>
  );
}
