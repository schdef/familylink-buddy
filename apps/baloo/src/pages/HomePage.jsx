/* src/pages/HomePage.jsx */
import { useEffect, useState } from 'preact/hooks';
import { getTopicsList } from '../engine/ContentLoader';
import { navigate } from '../router';
import { t, getLanguage } from '../utils/i18n';

export function HomePage() {
  const [topics, setTopics] = useState([]);
  const [lang, setLang] = useState(getLanguage());

  useEffect(() => {
    setTopics(getTopicsList());

    const handleLangChange = () => {
      setLang(getLanguage());
    };
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  const getTranslated = (obj) => {
    if (!obj) return '';
    return obj[lang] || obj.de || '';
  };

  return (
    <div style={{ padding: '0.5rem 0', display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
      
      <div style={{ textAlign: 'left' }}>
        <h1 style={{ marginBottom: '4px' }}>🐻 {t('menu.topics')}</h1>
        <p style={{ fontSize: '0.95rem' }}>Wähle ein Thema aus, um mit dem Lernen zu beginnen!</p>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))',
        gap: '16px',
        marginTop: '0.5rem'
      }}>
        {topics.map(topic => {
          // Get saved progress from localStorage to show badge
          const statusKey = `baloo_progress_${topic.id}`;
          const isDone = localStorage.getItem(statusKey) === 'completed';

          return (
            <div
              key={topic.id}
              class="card"
              onClick={() => navigate(`/topic/${topic.id}`)}
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: '12px',
                textAlign: 'left',
                cursor: 'pointer',
                position: 'relative',
                borderWidth: isDone ? '2px' : '1px',
                borderColor: isDone ? 'var(--color-success)' : 'var(--color-border-primary)'
              }}
            >
              {/* Badge for completion status */}
              {isDone && (
                <div style={{
                  position: 'absolute',
                  top: '12px',
                  right: '12px',
                  backgroundColor: 'var(--color-success)',
                  color: '#FFF',
                  borderRadius: 'var(--radius-full)',
                  width: '24px',
                  height: '24px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '0.8rem',
                  fontWeight: 'bold'
                }}>
                  ✓
                </div>
              )}

              <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                <div style={{
                  fontSize: '2rem',
                  width: '52px',
                  height: '52px',
                  borderRadius: 'var(--radius-md)',
                  backgroundColor: 'var(--color-bg-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center'
                }}>
                  {topic.icon || '📖'}
                </div>
                <div>
                  <h2 style={{ fontSize: '1.1rem', marginBottom: '2px' }}>
                    {getTranslated(topic.title)}
                  </h2>
                  <span style={{
                    fontSize: '0.75rem',
                    fontWeight: '600',
                    color: 'var(--color-text-secondary)',
                    backgroundColor: 'var(--color-bg-secondary)',
                    padding: '2px 8px',
                    borderRadius: 'var(--radius-full)'
                  }}>
                    {topic.isCustom ? 'Eigene Lektion' : 'Biologie'}
                  </span>
                </div>
              </div>

              <p style={{
                fontSize: '0.85rem',
                lineHeight: '1.4',
                flex: '1',
                color: 'var(--color-text-secondary)'
              }}>
                {getTranslated(topic.description)}
              </p>

              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                borderTop: '1px solid var(--color-border-primary)',
                paddingTop: '10px',
                marginTop: '4px',
                fontSize: '0.75rem',
                color: 'var(--color-text-muted)'
              }}>
                <span>👶 {topic.ageRange ? `${topic.ageRange[0]}-${topic.ageRange[1]} Jahre` : 'Alle Alter'}</span>
                <span style={{ fontWeight: '600', color: 'var(--color-success)' }}>
                  {isDone ? 'Abgeschlossen! 🎉' : 'Starten →'}
                </span>
              </div>

            </div>
          );
        })}
      </div>
      
    </div>
  );
}
