/* src/components/LanguageToggle.jsx */
import { useState, useEffect } from 'preact/hooks';
import { getLanguage, setLanguage, t } from '../utils/i18n';

export function LanguageToggle() {
  const [lang, setLang] = useState(getLanguage());

  useEffect(() => {
    const handleLangChange = () => {
      setLang(getLanguage());
    };
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  return (
    <div style={{ display: 'flex', gap: '6px' }}>
      <button
        type="button"
        class={`btn-secondary ${lang === 'de' ? 'active' : ''}`}
        style={{
          padding: '4px 8px',
          fontSize: '0.8rem',
          backgroundColor: lang === 'de' ? 'var(--color-success)' : 'transparent',
          color: lang === 'de' ? '#FFF' : 'var(--color-text-secondary)',
          borderColor: lang === 'de' ? 'var(--color-success)' : 'var(--color-border-primary)',
          borderRadius: 'var(--radius-sm)'
        }}
        onClick={() => setLanguage('de')}
      >
        DE
      </button>
      <button
        type="button"
        class={`btn-secondary ${lang === 'en' ? 'active' : ''}`}
        style={{
          padding: '4px 8px',
          fontSize: '0.8rem',
          backgroundColor: lang === 'en' ? 'var(--color-success)' : 'transparent',
          color: lang === 'en' ? '#FFF' : 'var(--color-text-secondary)',
          borderColor: lang === 'en' ? 'var(--color-success)' : 'var(--color-border-primary)',
          borderRadius: 'var(--radius-sm)'
        }}
        onClick={() => setLanguage('en')}
      >
        EN
      </button>
    </div>
  );
}
