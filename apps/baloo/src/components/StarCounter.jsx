/* src/components/StarCounter.jsx
 * Animated star counter for the TopBar.
 * Listens to the 'starchange' event and plays a pop animation when stars are added.
 */
import { useState, useEffect, useRef } from 'preact/hooks';
import { getStarBalance } from '../engine/StarEconomy';
import { t } from '../utils/i18n';

export function StarCounter({ onClick }) {
  const [stars, setStars] = useState(getStarBalance());
  const [pop, setPop] = useState(false);
  const prevStars = useRef(stars);

  useEffect(() => {
    const handleStarChange = (e) => {
      const newBalance = e.detail.balance;
      if (newBalance > prevStars.current) {
        // Stars were added — trigger pop animation
        setPop(true);
        setTimeout(() => setPop(false), 600);
      }
      prevStars.current = newBalance;
      setStars(newBalance);
    };

    window.addEventListener('starchange', handleStarChange);
    return () => window.removeEventListener('starchange', handleStarChange);
  }, []);

  return (
    <>
      <style>{`
        @keyframes star-pop {
          0%   { transform: scale(1); }
          40%  { transform: scale(1.4); }
          70%  { transform: scale(0.9); }
          100% { transform: scale(1); }
        }
        .star-counter-pop {
          animation: star-pop 0.5s ease-out;
        }
      `}</style>

      <button
        type="button"
        aria-label={t('app.stars_earned', { count: stars })}
        onClick={onClick}
        class={pop ? 'star-counter-pop' : ''}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '5px',
          fontWeight: '700',
          color: 'var(--color-warning)',
          backgroundColor: 'var(--color-warning-bg)',
          padding: '5px 12px',
          borderRadius: 'var(--radius-full)',
          fontSize: '0.92rem',
          border: '1.5px solid var(--color-warning-border)',
          cursor: onClick ? 'pointer' : 'default',
          transition: 'var(--transition-fast)',
          userSelect: 'none',
          whiteSpace: 'nowrap'
        }}
      >
        <span style={{ fontSize: '1rem' }}>⭐</span>
        <span>{stars}</span>
      </button>
    </>
  );
}
