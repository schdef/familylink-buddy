/* src/components/TopBar.jsx */
import { useState, useEffect } from 'preact/hooks';
import { useRoute, navigate } from '../router';
import { t } from '../utils/i18n';
import { LanguageToggle } from './LanguageToggle';
import { StarCounter } from './StarCounter';

export function TopBar() {
  const { path } = useRoute();
  const [isParentView, setIsParentView] = useState(false);

  // Monitor path changes to adjust navigation elements contextually
  useEffect(() => {
    const parentPaths = ['/upload', '/manager', '/dashboard'];
    setIsParentView(parentPaths.includes(path));
  }, [path]);

  // Simple translations trigger re-render on languagechange
  const [, setForceUpdate] = useState(0);
  useEffect(() => {
    const handleLangChange = () => setForceUpdate(prev => prev + 1);
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  return (
    <header class="card" style={{
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '10px 16px',
      borderRadius: 'var(--radius-md)',
      backgroundColor: 'var(--color-bg-primary)',
      border: '1px solid var(--color-border-primary)',
      marginBottom: '1.5rem',
      flexWrap: 'wrap',
      gap: '12px'
    }}>
      {/* Left: Logo or Back link */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', cursor: 'pointer' }} onClick={() => navigate('/')}>
        <div style={{
          width: '36px',
          height: '36px',
          borderRadius: 'var(--radius-sm)',
          backgroundColor: 'var(--color-success)',
          color: '#FFF',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontWeight: '700',
          fontSize: '1.2rem'
        }}>
          🐻
        </div>
        <span style={{ fontWeight: '700', fontSize: '1.05rem', color: 'var(--color-text-primary)' }}>
          {t('app.logo_title')}
        </span>
      </div>

      {/* Center Navigation depending on Kid vs Parent Context */}
      <nav style={{ display: 'flex', gap: '8px' }}>
        {isParentView ? (
          <>
            <button type="button" class={`btn-ghost ${path === '/upload' ? 'active' : ''}`} style={{
              padding: '6px 12px',
              fontSize: '0.85rem',
              fontWeight: '600',
              borderRadius: 'var(--radius-full)',
              backgroundColor: path === '/upload' ? 'var(--color-bg-secondary)' : 'transparent',
              color: path === '/upload' ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
            }} onClick={() => navigate('/upload')}>
              {t('menu.upload')}
            </button>
            <button type="button" class={`btn-ghost ${path === '/manager' ? 'active' : ''}`} style={{
              padding: '6px 12px',
              fontSize: '0.85rem',
              fontWeight: '600',
              borderRadius: 'var(--radius-full)',
              backgroundColor: path === '/manager' ? 'var(--color-bg-secondary)' : 'transparent',
              color: path === '/manager' ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
            }} onClick={() => navigate('/manager')}>
              {t('menu.manager')}
            </button>
            <button type="button" class={`btn-ghost ${path === '/dashboard' ? 'active' : ''}`} style={{
              padding: '6px 12px',
              fontSize: '0.85rem',
              fontWeight: '600',
              borderRadius: 'var(--radius-full)',
              backgroundColor: path === '/dashboard' ? 'var(--color-bg-secondary)' : 'transparent',
              color: path === '/dashboard' ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
            }} onClick={() => navigate('/dashboard')}>
              {t('menu.dashboard')}
            </button>
          </>
        ) : (
          <>
            <button type="button" class={`btn-ghost ${path === '/topics' ? 'active' : ''}`} style={{
              padding: '6px 12px',
              fontSize: '0.85rem',
              fontWeight: '600',
              borderRadius: 'var(--radius-full)',
              backgroundColor: path === '/topics' ? 'var(--color-bg-secondary)' : 'transparent',
              color: path === '/topics' ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
            }} onClick={() => navigate('/topics')}>
              {t('menu.topics')}
            </button>
            <button type="button" class={`btn-ghost ${path === '/rewards' ? 'active' : ''}`} style={{
              padding: '6px 12px',
              fontSize: '0.85rem',
              fontWeight: '600',
              borderRadius: 'var(--radius-full)',
              backgroundColor: path === '/rewards' ? 'var(--color-bg-secondary)' : 'transparent',
              color: path === '/rewards' ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
            }} onClick={() => navigate('/rewards')}>
              {t('menu.rewards')}
            </button>
          </>
        )}
      </nav>

      {/* Right side: Stars, Language Toggle, and Portal link */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
        {/* Animated Star Counter — click to open Reward Games */}
        <StarCounter onClick={() => navigate('/rewards')} />

        <LanguageToggle />

        {/* View Switch Button */}
        {isParentView ? (
          <button type="button" class="btn btn-secondary" style={{ padding: '6px 12px', fontSize: '0.8rem' }} onClick={() => navigate('/topics')}>
            👦 Kids
          </button>
        ) : (
          <button type="button" class="btn btn-secondary" style={{ padding: '6px 12px', fontSize: '0.8rem' }} onClick={() => navigate('/dashboard')}>
            🔑 Parents
          </button>
        )}
      </div>
    </header>
  );
}
