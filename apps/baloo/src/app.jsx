/* src/app.jsx */
import { useEffect, useState } from 'preact/hooks';
import { useRoute } from './router';
import { TopBar } from './components/TopBar';
import { getLanguage, t } from './utils/i18n';

// Pages
import { LandingPage } from './pages/LandingPage';
import { HomePage } from './pages/HomePage';
import { TopicPage } from './pages/TopicPage';
import { RewardPage } from './pages/RewardPage';
import { UploadPage } from './pages/UploadPage';
import { LectureManagerPage } from './pages/LectureManagerPage';
import { ParentDashboard } from './pages/ParentDashboard';
import { PrintableWorksheetPage } from './pages/PrintableWorksheetPage';

export function App() {
  const { path, params } = useRoute();
  const [lang, setLang] = useState(getLanguage());

  // Listen for language toggles to force re-render t() strings
  useEffect(() => {
    const handleLangChange = () => {
      setLang(getLanguage());
    };
    window.addEventListener('languagechange', handleLangChange);
    return () => window.removeEventListener('languagechange', handleLangChange);
  }, []);

  // Helper page dispatcher
  const renderPage = () => {
    switch (path) {
      case '/':
        return <LandingPage />;
      case '/topics':
        return <HomePage />;
      case '/topic/:id':
        return <TopicPage />;
      case '/print/:id':
        return <PrintableWorksheetPage id={params.id} />;
      case '/rewards':
        return <RewardPage />;
      case '/upload':
        return <UploadPage />;
      case '/manager':
        return <LectureManagerPage />;
      case '/dashboard':
        return <ParentDashboard />;
      default:
        return (
          <div style={{ textAlign: 'center', padding: '2rem' }}>
            <h2>404 - Seite nicht gefunden</h2>
            <button type="button" class="btn btn-primary" onClick={() => window.location.hash = '#/'} style={{ marginTop: '1rem' }}>
              Zur Startseite
            </button>
          </div>
        );
    }
  };

  return (
    <div class="app-container">
      {/* Reusable Header bar */}
      <TopBar />

      {/* Dynamic routing page area */}
      <main class="main-content">
        {renderPage()}
      </main>
    </div>
  );
}
