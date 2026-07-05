/* src/pages/RewardPage.jsx
 * The "Spiele-Salon" — kids spend stars to unlock and play reward mini-games.
 * Shows available games as cards, manages the star-spending flow,
 * and launches the chosen game in-place.
 */
import { useState, useEffect } from 'preact/hooks';
import { getStarBalance, spendStars } from '../engine/StarEconomy';
import { navigate } from '../router';
import { t } from '../utils/i18n';
import { StarCounter } from '../components/StarCounter';
import { PixelArt } from '../games/rewards/PixelArt';
import { BubblePop } from '../games/rewards/BubblePop';

const STAR_COST = 10;

const GAMES = [
  {
    id: 'pixel',
    emoji: '🎨',
    name: 'Pixel-Kunst',
    desc: 'Male ein verstecktes Bild aus – Feld für Feld!',
    color: 'var(--color-info-bg)',
    border: 'var(--color-info-border)',
    accent: 'var(--color-info)'
  },
  {
    id: 'bubbles',
    emoji: '🫧',
    name: 'Blasen-Popper',
    desc: 'Platze so viele Blasen wie möglich in 30 Sekunden!',
    color: 'var(--color-success-bg)',
    border: 'var(--color-success-border)',
    accent: 'var(--color-success)'
  }
];

export function RewardPage() {
  const [stars, setStars] = useState(getStarBalance());
  const [activeGame, setActiveGame] = useState(null); // 'pixel' | 'bubbles' | null
  const [, forceUpdate] = useState(0);

  useEffect(() => {
    const onStarChange = (e) => setStars(e.detail.balance);
    window.addEventListener('starchange', onStarChange);
    return () => window.removeEventListener('starchange', onStarChange);
  }, []);

  const handleSpendStars = (amount) => {
    spendStars(amount);
    setStars(getStarBalance());
  };

  const handleExit = () => {
    setActiveGame(null);
    forceUpdate(n => n + 1);
  };

  // ---- Render active game in-place ----
  if (activeGame === 'pixel') {
    return (
      <div style={{ padding: '0.5rem 0' }}>
        <PixelArt
          starBalance={stars}
          onSpendStars={handleSpendStars}
          onExit={handleExit}
        />
      </div>
    );
  }

  if (activeGame === 'bubbles') {
    return (
      <div style={{ padding: '0.5rem 0' }}>
        <BubblePop
          starBalance={stars}
          onSpendStars={handleSpendStars}
          onExit={handleExit}
        />
      </div>
    );
  }

  // ---- Game selection lobby ----
  const canPlay = stars >= STAR_COST;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem', padding: '0.5rem 0' }}>

      {/* Header */}
      <div style={{ textAlign: 'left' }}>
        <h1 style={{ marginBottom: '4px' }}>🎮 {t('rewards.title')}</h1>
        <p style={{ fontSize: '0.9rem' }}>{t('rewards.subtitle')}</p>
      </div>

      {/* Star balance callout */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        backgroundColor: canPlay ? 'var(--color-warning-bg)' : 'var(--color-bg-secondary)',
        border: `1px solid ${canPlay ? 'var(--color-warning-border)' : 'var(--color-border-primary)'}`,
        borderRadius: 'var(--radius-md)',
        padding: '12px 16px'
      }}>
        <div>
          <p style={{ fontWeight: '700', color: 'var(--color-text-primary)', marginBottom: '2px' }}>
            {canPlay ? '🎉 Genug Sterne zum Spielen!' : `Noch ${STAR_COST - stars} Sterne fehlen!`}
          </p>
          <p style={{ fontSize: '0.82rem', color: 'var(--color-text-secondary)' }}>
            {canPlay
              ? 'Wähle ein Spiel aus!'
              : 'Löse Übungen, um Sterne zu sammeln.'}
          </p>
        </div>
        <StarCounter />
      </div>

      {/* Games Grid */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
        gap: '14px'
      }}>
        {GAMES.map(game => (
          <div
            key={game.id}
            class="card"
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: '12px',
              textAlign: 'left',
              backgroundColor: game.color,
              borderColor: game.border,
              opacity: canPlay ? 1 : 0.6,
              transition: 'var(--transition-normal)'
            }}
          >
            <div style={{ fontSize: '2.5rem' }}>{game.emoji}</div>
            <div>
              <h2 style={{ fontSize: '1.1rem', marginBottom: '4px' }}>{game.name}</h2>
              <p style={{ fontSize: '0.85rem', lineHeight: '1.4' }}>{game.desc}</p>
            </div>

            <button
              type="button"
              class="btn btn-primary"
              disabled={!canPlay}
              onClick={() => setActiveGame(game.id)}
              style={{
                marginTop: 'auto',
                backgroundColor: canPlay ? 'var(--color-success)' : 'var(--color-bg-tertiary)',
                color: canPlay ? '#FFF' : 'var(--color-text-muted)'
              }}
            >
              {canPlay ? `${t('rewards.play')}` : `${STAR_COST} ⭐ nötig`}
            </button>
          </div>
        ))}
      </div>

      {/* CTA to go earn stars */}
      {!canPlay && (
        <div style={{ textAlign: 'center' }}>
          <button type="button" class="btn btn-primary" onClick={() => navigate('/topics')}>
            📚 Sterne verdienen →
          </button>
        </div>
      )}

      {/* Tips section */}
      <div style={{
        backgroundColor: 'var(--color-bg-secondary)',
        borderRadius: 'var(--radius-md)',
        padding: '12px 16px',
        border: '1px solid var(--color-border-primary)',
        fontSize: '0.82rem',
        color: 'var(--color-text-secondary)',
        lineHeight: '1.5'
      }}>
        💡 <strong>Tipp:</strong> Du verdienst 1 ⭐ für jede richtige Antwort im Quiz, Memory oder Wörter-Spiel.
        Beim Puzzle gibt es sogar 5 ⭐ als Bonus!
      </div>

    </div>
  );
}
