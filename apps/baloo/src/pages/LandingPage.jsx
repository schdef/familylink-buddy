/* src/pages/LandingPage.jsx */
import { useEffect, useState } from 'preact/hooks';
import { navigate } from '../router';
import { t } from '../utils/i18n';

export function LandingPage() {
  // Translate force render on languagechange
  const [, setForceUpdate] = useState(0);
  useEffect(() => {
    const handleLangChange = () => setForceUpdate(prev => prev + 1);
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '2.5rem', padding: '0.5rem 0' }}>
      
      {/* 1. Hero Section */}
      <section style={{
        textAlign: 'center',
        padding: '2.5rem 1.5rem',
        borderRadius: 'var(--radius-lg)',
        backgroundColor: 'var(--color-success-bg)',
        border: '1px solid var(--color-success-border)',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '1.25rem'
      }}>
        <div style={{ fontSize: '3.5rem', userSelect: 'none' }}>🐻🎨📖</div>
        <h1 style={{ fontSize: '1.85rem', color: 'var(--color-text-primary)' }}>
          {t('landing.title')}
        </h1>
        <p style={{
          fontSize: '1rem',
          maxWidth: '480px',
          color: 'var(--color-text-secondary)',
          lineHeight: '1.5'
        }}>
          {t('landing.subtitle')}
        </p>
        <div style={{ display: 'flex', gap: '12px', marginTop: '0.5rem' }}>
          <button type="button" class="btn btn-primary" onClick={() => navigate('/topics')}>
            {t('landing.start_btn')}
          </button>
          <a href="#parents-info" class="btn btn-secondary" style={{ textDecoration: 'none' }}>
            {t('landing.for_parents_btn')}
          </a>
        </div>
      </section>

      {/* 2. Features Grid: Why Baloo? */}
      <section style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
        <h2 style={{ textAlign: 'center' }}>{t('landing.why.title')}</h2>
        
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
          gap: '1rem'
        }}>
          <div class="card" style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <h3 style={{ fontSize: '1.05rem' }}>{t('landing.why.adhd.title')}</h3>
            <p style={{ fontSize: '0.85rem' }}>{t('landing.why.adhd.desc')}</p>
          </div>
          
          <div class="card" style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <h3 style={{ fontSize: '1.05rem' }}>{t('landing.why.visual.title')}</h3>
            <p style={{ fontSize: '0.85rem' }}>{t('landing.why.visual.desc')}</p>
          </div>
          
          <div class="card" style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <h3 style={{ fontSize: '1.05rem' }}>{t('landing.why.stars.title')}</h3>
            <p style={{ fontSize: '0.85rem' }}>{t('landing.why.stars.desc')}</p>
          </div>
        </div>
      </section>

      {/* 3. Interactive Steps explanation */}
      <section style={{
        backgroundColor: 'var(--color-bg-secondary)',
        padding: '1.5rem',
        borderRadius: 'var(--radius-md)',
        border: '1px solid var(--color-border-primary)',
        display: 'flex',
        flexDirection: 'column',
        gap: '1rem'
      }}>
        <h2 style={{ fontSize: '1.2rem', textAlign: 'center' }}>{t('landing.how.title')}</h2>
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '8px',
          textAlign: 'left',
          maxWidth: '440px',
          margin: '0 auto',
          width: '100%'
        }}>
          <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
            <span style={{ fontSize: '1.25rem' }}>📚</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>{t('landing.how.step1')}</span>
          </div>
          <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
            <span style={{ fontSize: '1.25rem' }}>🧩</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>{t('landing.how.step2')}</span>
          </div>
          <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
            <span style={{ fontSize: '1.25rem' }}>⭐</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>{t('landing.how.step3')}</span>
          </div>
          <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
            <span style={{ fontSize: '1.25rem' }}>🎮</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>{t('landing.how.step4')}</span>
          </div>
        </div>
      </section>

      {/* 4. Parent Section & Upload Intro */}
      <section id="parents-info" style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '1rem',
        textAlign: 'left',
        scrollMarginTop: '2rem'
      }}>
        <h2>{t('landing.parents.title')}</h2>
        <p style={{ lineHeight: '1.6' }}>
          {t('landing.parents.desc')}
        </p>
        
        <div class="card" style={{
          backgroundColor: 'var(--color-info-bg)',
          border: '1px solid var(--color-info-border)',
          display: 'flex',
          flexDirection: 'column',
          gap: '8px'
        }}>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ color: 'var(--color-info)', fontWeight: 'bold' }}>✓</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '600', color: 'var(--color-text-primary)' }}>
              {t('landing.parents.feature1')}
            </span>
          </div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ color: 'var(--color-info)', fontWeight: 'bold' }}>✓</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '600', color: 'var(--color-text-primary)' }}>
              {t('landing.parents.feature2')}
            </span>
          </div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ color: 'var(--color-info)', fontWeight: 'bold' }}>✓</span>
            <span style={{ fontSize: '0.9rem', fontWeight: '600', color: 'var(--color-text-primary)' }}>
              {t('landing.parents.feature3')}
            </span>
          </div>
        </div>

        <div style={{ textAlign: 'center', marginTop: '0.5rem' }}>
          <button type="button" class="btn btn-primary" onClick={() => navigate('/dashboard')}>
            🔑 {t('menu.dashboard')}
          </button>
        </div>
      </section>

      {/* 5. Footer */}
      <footer style={{
        marginTop: '2rem',
        paddingTop: '1rem',
        borderTop: '1px solid var(--color-border-primary)',
        fontSize: '0.8rem',
        color: 'var(--color-text-muted)',
        textAlign: 'center'
      }}>
        <p>© 2026 Baloo LernSpiel. Alle Rechte vorbehalten. | Werbefreie Bildung für Kinder.</p>
      </footer>

    </div>
  );
}
