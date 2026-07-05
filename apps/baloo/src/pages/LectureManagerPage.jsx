/* src/pages/LectureManagerPage.jsx
 * Page for parents/teachers to manage uploaded and built-in lectures.
 * Displays them in a categorized folder structure with expansion states, completion metrics, and deletion tools.
 */
import { useEffect, useState } from 'preact/hooks';
import { getLectures, deleteLecture, getLecture } from '../engine/LectureStore';
import { getTopicsList } from '../engine/ContentLoader';
import { navigate } from '../router';
import { t, getLanguage } from '../utils/i18n';

export function LectureManagerPage() {
  const lang = getLanguage();
  const [lectures, setLectures] = useState([]);
  const [expandedCategories, setExpandedCategories] = useState({});

  const loadData = () => {
    // ContentLoader returns both built-in topics AND custom lectures
    const list = getTopicsList();
    setLectures(list);

    // Auto-expand all categories on load
    const categories = [...new Set(list.map(l => l.category || 'Biologie'))];
    const initialExpanded = {};
    categories.forEach(c => {
      initialExpanded[c] = true;
    });
    setExpandedCategories(initialExpanded);
  };

  useEffect(() => {
    loadData();

    // Listen to changes in the store to update immediately
    const handleStoreChange = () => loadData();
    window.addEventListener('lecturechange', handleStoreChange);
    
    const handleLangChange = () => loadData();
    window.addEventListener('languagechange', handleLangChange);

    return () => {
      window.removeEventListener('lecturechange', handleStoreChange);
      window.removeEventListener('languagechange', handleLangChange);
    };
  }, []);

  // Toggle Category Folders
  const toggleCategory = (category) => {
    setExpandedCategories(prev => ({
      ...prev,
      [category]: !prev[category]
    }));
  };

  // Delete lecture
  const handleDelete = (id, e) => {
    e.stopPropagation();
    const confirmMsg = lang === 'de' 
      ? 'Möchtest du diese Lektion wirklich dauerhaft löschen?' 
      : 'Are you sure you want to delete this lecture permanently?';
    if (window.confirm(confirmMsg)) {
      deleteLecture(id);
      loadData();
    }
  };

  const getTranslated = (obj) => {
    if (!obj) return '';
    return obj[lang] || obj.de || '';
  };

  // Group lectures by category
  const grouped = lectures.reduce((acc, lec) => {
    const cat = lec.category || 'Biologie';
    if (!acc[cat]) acc[cat] = [];
    acc[cat].push(lec);
    return acc;
  }, {});

  // Fetch status details
  const getLectureDetails = (lec) => {
    // If it's custom, we load full metadata from LectureStore
    if (lec.isCustom) {
      const stored = getLecture(lec.id);
      if (stored) {
        return {
          status: stored.status || 'new',
          completedExercises: stored.completedExercises || 0,
          totalExercises: stored.totalExercises || 5
        };
      }
    }
    
    // For built-in topics, get progress from localStorage
    const statusKey = `baloo_progress_${lec.id}`;
    const scoreKey = `baloo_score_${lec.id}`; // e.g. completed games
    const isDone = localStorage.getItem(statusKey) === 'completed';
    
    // Calculate simple stats
    let completedCount = 0;
    const gameModes = ['vocab', 'quiz', 'memory', 'spelling', 'puzzle'];
    gameModes.forEach(mode => {
      if (localStorage.getItem(`baloo_done_${lec.id}_${mode}`) === 'true') {
        completedCount++;
      }
    });

    return {
      status: isDone ? 'completed' : (completedCount > 0 ? 'in_progress' : 'new'),
      completedExercises: completedCount,
      totalExercises: 5
    };
  };

  const renderStatusBadge = (status) => {
    switch (status) {
      case 'completed':
        return (
          <span style={{
            fontSize: '0.8rem',
            padding: '2px 8px',
            backgroundColor: 'var(--color-success-bg, #E6F5EE)',
            color: 'var(--color-success, #1D9E75)',
            borderRadius: 'var(--radius-full)',
            fontWeight: '600',
            display: 'inline-flex',
            alignItems: 'center',
            gap: '4px'
          }}>
            ✅ {lang === 'de' ? 'Erledigt' : 'Done'}
          </span>
        );
      case 'in_progress':
        return (
          <span style={{
            fontSize: '0.8rem',
            padding: '2px 8px',
            backgroundColor: '#FFF4E6',
            color: '#D87A0B',
            borderRadius: 'var(--radius-full)',
            fontWeight: '600',
            display: 'inline-flex',
            alignItems: 'center',
            gap: '4px'
          }}>
            🔄 {lang === 'de' ? 'In Arbeit' : 'In Progress'}
          </span>
        );
      case 'new':
      default:
        return (
          <span style={{
            fontSize: '0.8rem',
            padding: '2px 8px',
            backgroundColor: 'var(--color-bg-secondary)',
            color: 'var(--color-text-secondary)',
            borderRadius: 'var(--radius-full)',
            fontWeight: '500',
            display: 'inline-flex',
            alignItems: 'center',
            gap: '4px'
          }}>
            📝 {lang === 'de' ? 'Neu' : 'New'}
          </span>
        );
    }
  };

  return (
    <div style={{ maxWidth: '720px', margin: '0 auto', padding: '1rem 0' }}>
      
      {/* Header and buttons */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem', flexWrap: 'wrap', gap: '12px' }}>
        <div style={{ textAlign: 'left' }}>
          <h1 style={{ marginBottom: '4px' }}>📂 {t('menu.manager')}</h1>
          <p style={{ fontSize: '0.95rem', color: 'var(--color-text-secondary)' }}>
            {lang === 'de' 
              ? 'Verwalte Lektionen, siehst den Fortschritt deines Kindes und erstelle neue Inhalte.' 
              : 'Manage lectures, check your child’s progress, and upload new materials.'}
          </p>
        </div>
        <button
          type="button"
          class="btn btn-primary"
          onClick={() => navigate('/upload')}
          style={{ padding: '10px 16px', display: 'flex', alignItems: 'center', gap: '8px', fontWeight: 'bold' }}
        >
          ➕ {lang === 'de' ? 'Neue Lektion (mit KI) erstellen' : 'Create New Lecture (with AI)'}
        </button>
      </div>

      {lectures.length === 0 ? (
        <div class="card" style={{ padding: '3rem 2rem', textAlign: 'center' }}>
          <span style={{ fontSize: '3rem' }}>📂</span>
          <h3 style={{ marginTop: '1rem', marginBottom: '8px' }}>Keine Lektionen vorhanden</h3>
          <p style={{ color: 'var(--color-text-secondary)', fontSize: '0.95rem', marginBottom: '1.5rem' }}>
            Erstelle deine erste Lektion, um sie hier zu verwalten!
          </p>
          <button type="button" class="btn btn-primary" onClick={() => navigate('/upload')}>
            Lektion erstellen
          </button>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {Object.entries(grouped).map(([categoryName, items]) => {
            const isExpanded = expandedCategories[categoryName];
            
            return (
              <div key={categoryName} class="card" style={{ padding: '0', overflow: 'hidden', textAlign: 'left' }}>
                
                {/* Folder Header */}
                <div
                  onClick={() => toggleCategory(categoryName)}
                  style={{
                    padding: '14px 20px',
                    backgroundColor: 'var(--color-bg-secondary)',
                    borderBottom: isExpanded ? '1px solid var(--color-border-primary)' : 'none',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    cursor: 'pointer',
                    userSelect: 'none'
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontWeight: 'bold', fontSize: '1rem' }}>
                    <span style={{ fontSize: '1.3rem' }}>{isExpanded ? '📂' : '📁'}</span>
                    <span>{categoryName}</span>
                    <span style={{
                      fontSize: '0.75rem',
                      fontWeight: 'normal',
                      backgroundColor: 'var(--color-border-secondary, #E2E1DA)',
                      color: 'var(--color-text-secondary)',
                      padding: '2px 8px',
                      borderRadius: 'var(--radius-full)',
                      marginLeft: '4px'
                    }}>
                      {items.length} {items.length === 1 ? 'Lektion' : 'Lektionen'}
                    </span>
                  </div>
                  <span style={{
                    fontSize: '0.85rem',
                    transform: isExpanded ? 'rotate(90deg)' : 'rotate(0deg)',
                    transition: 'transform 0.2s',
                    color: 'var(--color-text-secondary)'
                  }}>
                    ▶
                  </span>
                </div>

                {/* Folder Body (Lecture list) */}
                {isExpanded && (
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    {items.map((lec, idx) => {
                      const details = getLectureDetails(lec);
                      
                      return (
                        <div
                          key={lec.id}
                          onClick={() => navigate(`/topic/${lec.id}`)}
                          style={{
                            padding: '16px 20px',
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center',
                            borderBottom: idx < items.length - 1 ? '1px solid var(--color-border-primary)' : 'none',
                            cursor: 'pointer',
                            transition: 'background-color 0.2s',
                            backgroundColor: 'transparent'
                          }}
                          onMouseEnter={(e) => e.currentTarget.style.backgroundColor = 'rgba(0,0,0,0.02)'}
                          onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
                        >
                          <div style={{ display: 'flex', alignItems: 'center', gap: '14px', flex: '1', minWidth: '0' }}>
                            <div style={{
                              fontSize: '1.6rem',
                              width: '42px',
                              height: '42px',
                              borderRadius: 'var(--radius-sm)',
                              backgroundColor: 'var(--color-bg-secondary)',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                              flexShrink: 0
                            }}>
                              {lec.icon || '📖'}
                            </div>

                            <div style={{ minWidth: '0' }}>
                              <div style={{ fontWeight: '600', fontSize: '0.95rem', marginBottom: '2px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                                <span style={{ textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
                                  {getTranslated(lec.title)}
                                </span>
                                {lec.isCustom && (
                                  <span style={{
                                    fontSize: '0.65rem',
                                    backgroundColor: 'var(--color-primary-bg, #EEEDFE)',
                                    color: 'var(--color-primary, #534AB7)',
                                    padding: '1px 6px',
                                    borderRadius: 'var(--radius-sm)',
                                    fontWeight: 'bold',
                                    textTransform: 'uppercase'
                                  }}>
                                    KI
                                  </span>
                                )}
                              </div>
                              <div style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)', display: 'flex', alignItems: 'center', gap: '10px' }}>
                                <span>{lang === 'de' ? `Übungen gelöst: ${details.completedExercises}/${details.totalExercises}` : `Exercises: ${details.completedExercises}/${details.totalExercises}`}</span>
                                <span>•</span>
                                <span>{lec.cards?.length || 0} {lang === 'de' ? 'Karten' : 'Cards'}</span>
                              </div>
                            </div>
                          </div>

                          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                            {renderStatusBadge(details.status)}
                            
                            {lec.isCustom && (
                              <div style={{ display: 'flex', gap: '4px' }}>
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    const prompt = window.prompt(lang === 'de' ? 'Anweisung für die KI zur Überarbeitung:' : 'Instructions for AI to regenerate:');
                                    if (prompt) {
                                      // TODO: Implement regenerate
                                      alert("Regenerate not yet implemented");
                                    }
                                  }}
                                  style={{
                                    border: 'none',
                                    backgroundColor: 'transparent',
                                    color: 'var(--color-text-muted)',
                                    cursor: 'pointer',
                                    fontSize: '1.1rem',
                                    padding: '8px',
                                    borderRadius: 'var(--radius-sm)',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    transition: 'color 0.2s, background-color 0.2s'
                                  }}
                                  onMouseEnter={(e) => {
                                    e.currentTarget.style.color = 'var(--color-primary)';
                                    e.currentTarget.style.backgroundColor = '#EEEDFE';
                                  }}
                                  onMouseLeave={(e) => {
                                    e.currentTarget.style.color = 'var(--color-text-muted)';
                                    e.currentTarget.style.backgroundColor = 'transparent';
                                  }}
                                  title={lang === 'de' ? 'Lektion mit KI überarbeiten' : 'Regenerate lecture with AI'}
                                >
                                  🔄
                                </button>

                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    navigate(`/print/${lec.id}`);
                                  }}
                                  style={{
                                    border: 'none',
                                    backgroundColor: 'transparent',
                                    color: 'var(--color-text-muted)',
                                    cursor: 'pointer',
                                    fontSize: '1.1rem',
                                    padding: '8px',
                                    borderRadius: 'var(--radius-sm)',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    transition: 'color 0.2s, background-color 0.2s'
                                  }}
                                  onMouseEnter={(e) => {
                                    e.currentTarget.style.color = 'var(--color-primary)';
                                    e.currentTarget.style.backgroundColor = '#EEEDFE';
                                  }}
                                  onMouseLeave={(e) => {
                                    e.currentTarget.style.color = 'var(--color-text-muted)';
                                    e.currentTarget.style.backgroundColor = 'transparent';
                                  }}
                                  title={lang === 'de' ? 'Arbeitsblatt drucken' : 'Print worksheet'}
                                >
                                  🖨️
                                </button>

                                <button
                                  type="button"
                                  onClick={(e) => handleDelete(lec.id, e)}
                                  style={{
                                    border: 'none',
                                    backgroundColor: 'transparent',
                                    color: 'var(--color-text-muted)',
                                    cursor: 'pointer',
                                    fontSize: '1.1rem',
                                    padding: '8px',
                                    borderRadius: 'var(--radius-sm)',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    transition: 'color 0.2s, background-color 0.2s'
                                  }}
                                  onMouseEnter={(e) => {
                                    e.currentTarget.style.color = 'var(--color-danger)';
                                    e.currentTarget.style.backgroundColor = '#FBEBEB';
                                  }}
                                  onMouseLeave={(e) => {
                                    e.currentTarget.style.color = 'var(--color-text-muted)';
                                    e.currentTarget.style.backgroundColor = 'transparent';
                                  }}
                                  title={lang === 'de' ? 'Lektion löschen' : 'Delete lecture'}
                                >
                                  🗑️
                                </button>
                              </div>
                            )}
                          </div>

                        </div>
                      );
                    })}
                  </div>
                )}

              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
