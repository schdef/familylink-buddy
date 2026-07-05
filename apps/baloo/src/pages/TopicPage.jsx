/* src/pages/TopicPage.jsx */
import { useState, useEffect } from 'preact/hooks';
import { getTopicById } from '../engine/ContentLoader';
import { useRoute, navigate } from '../router';
import { t, getLanguage } from '../utils/i18n';

// Import specific game modes
import { VocabGame } from '../games/VocabGame';
import { QuizGame } from '../games/QuizGame';
import { MemoryGame } from '../games/MemoryGame';
import { SpellingGame } from '../games/SpellingGame';
import { PuzzleGame } from '../games/PuzzleGame';

export function TopicPage() {
  const { params } = useRoute();
  const [topic, setTopic] = useState(null);
  const [activeTab, setActiveTab] = useState('vocab'); // default tab is vocab cards
  const [lang, setLang] = useState(getLanguage());

  // Load topic details dynamically
  useEffect(() => {
    if (params.id) {
      const data = getTopicById(params.id);
      if (data) {
        setTopic(data);
        setActiveTab('vocab');
      } else {
        navigate('/topics'); // Redirect if not found
      }
    }
  }, [params.id]);

  // Handle translation reload
  useEffect(() => {
    const handleLangChange = () => {
      setLang(getLanguage());
    };
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  const getTranslated = (obj, field) => {
    if (!obj || !obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  if (!topic) return null;

  // Track completed tabs locally
  const markTabCompleted = (mode) => {
    const key = `baloo_progress_${topic.id}_${mode}`;
    localStorage.setItem(key, 'completed');
    
    // Check if ALL tabs completed to mark topic overall completed
    const modes = ['vocab', 'quiz', 'memory', 'spelling', 'puzzle'];
    const allDone = modes.every(m => m === mode || localStorage.getItem(`baloo_progress_${topic.id}_${m}`) === 'completed');
    if (allDone) {
      localStorage.setItem(`baloo_progress_${topic.id}`, 'completed');
    }
  };

  const renderGameContent = () => {
    switch (activeTab) {
      case 'vocab':
        return (
          <VocabGame 
            cards={topic.cards} 
            onComplete={() => markTabCompleted('vocab')} 
          />
        );
      case 'quiz':
        return (
          <QuizGame 
            cards={topic.cards} 
            onComplete={() => markTabCompleted('quiz')} 
          />
        );
      case 'memory':
        return (
          <MemoryGame 
            cards={topic.cards} 
            onComplete={() => markTabCompleted('memory')} 
          />
        );
      case 'spelling':
        return (
          <SpellingGame 
            cards={topic.cards} 
            onComplete={() => markTabCompleted('spelling')} 
          />
        );
      case 'puzzle':
        return (
          <PuzzleGame 
            topicId={topic.id}
            puzzlePieces={topic.puzzlePieces || []} 
            onComplete={() => markTabCompleted('puzzle')} 
          />
        );
      default:
        return null;
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem', padding: '0.5rem 0' }}>
      
      {/* Header back navigation and Title */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', textAlign: 'left' }}>
        <button type="button" class="btn-ghost" onClick={() => navigate('/topics')} style={{
          padding: '4px 0',
          fontSize: '0.85rem',
          display: 'inline-flex',
          justifyContent: 'flex-start',
          width: 'max-content'
        }}>
          {t('app.back_to_topics')}
        </button>
        <h1 style={{ fontSize: '1.5rem', marginTop: '4px' }}>
          {getTranslated(topic, 'title')}
        </h1>
      </div>

      {/* Tab Buttons bar */}
      <div class="tab-nav">
        <button
          type="button"
          class={`tab-btn ${activeTab === 'vocab' ? 'active' : ''}`}
          onClick={() => setActiveTab('vocab')}
        >
          {t('game.tab.vocab')}
        </button>
        <button
          type="button"
          class={`tab-btn ${activeTab === 'quiz' ? 'active' : ''}`}
          onClick={() => setActiveTab('quiz')}
        >
          {t('game.tab.quiz')}
        </button>
        <button
          type="button"
          class={`tab-btn ${activeTab === 'memory' ? 'active' : ''}`}
          onClick={() => setActiveTab('memory')}
        >
          {t('game.tab.memory')}
        </button>
        <button
          type="button"
          class={`tab-btn ${activeTab === 'spelling' ? 'active' : ''}`}
          onClick={() => setActiveTab('spelling')}
        >
          {t('game.tab.spelling')}
        </button>
        {topic.puzzlePieces && topic.puzzlePieces.length > 0 && (
          <button
            type="button"
            class={`tab-btn ${activeTab === 'puzzle' ? 'active' : ''}`}
            onClick={() => setActiveTab('puzzle')}
          >
            {t('game.tab.puzzle')}
          </button>
        )}
      </div>

      {/* Embedded active game container */}
      <main class="main-content" style={{ marginTop: '0.25rem' }}>
        {renderGameContent()}
      </main>

    </div>
  );
}
