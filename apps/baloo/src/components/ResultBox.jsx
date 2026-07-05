/* src/components/ResultBox.jsx */
import { t } from '../utils/i18n';
import { navigate } from '../router';

export function ResultBox({ correct, total, starsEarned = 0, onRetry }) {
  const percentage = total > 0 ? (correct / total) * 100 : 0;
  
  let subtitle = t('quiz.try_again');
  let emoji = '💪';
  
  if (percentage >= 85) {
    subtitle = t('quiz.great');
    emoji = '🏆';
  } else if (percentage >= 50) {
    subtitle = t('quiz.good');
    emoji = '🌟';
  }

  return (
    <div 
      class="card" 
      style={{
        textAlign: 'center',
        padding: '2.5rem 1.5rem',
        backgroundColor: 'var(--color-bg-secondary)',
        borderRadius: 'var(--radius-lg)',
        border: '1px solid var(--color-border-primary)',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '1rem',
        maxWidth: '400px',
        margin: '2rem auto'
      }}
    >
      <div style={{ fontSize: '3.5rem', userSelect: 'none' }}>{emoji}</div>
      
      <div>
        <h2 style={{ fontSize: '1.5rem', marginBottom: '4px' }}>
          {t('quiz.complete', { correct, total })}
        </h2>
        <p style={{ fontWeight: '600', color: 'var(--color-text-secondary)' }}>
          {subtitle}
        </p>
      </div>

      {starsEarned > 0 && (
        <div style={{
          backgroundColor: 'var(--color-warning-bg)',
          color: 'var(--color-warning)',
          border: '1px solid var(--color-warning-border)',
          borderRadius: 'var(--radius-md)',
          padding: '8px 16px',
          fontWeight: '700',
          display: 'inline-flex',
          alignItems: 'center',
          gap: '8px',
          fontSize: '1.05rem',
          margin: '0.5rem 0'
        }}>
          <span>⭐</span>
          <span>+{starsEarned} {t('app.stars_count')}!</span>
        </div>
      )}

      <div style={{
        display: 'flex',
        gap: '10px',
        width: '100%',
        justifyContent: 'center',
        marginTop: '0.5rem'
      }}>
        <button 
          type="button" 
          class="btn btn-secondary" 
          onClick={onRetry}
          style={{ flex: 1 }}
        >
          🔄 {t('memory.play_again')}
        </button>
        <button 
          type="button" 
          class="btn btn-primary" 
          onClick={() => navigate('/topics')}
          style={{ flex: 1 }}
        >
          🏠 {t('menu.topics')}
        </button>
      </div>
    </div>
  );
}
