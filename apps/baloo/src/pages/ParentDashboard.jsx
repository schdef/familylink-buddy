/* src/pages/ParentDashboard.jsx
 * Parent Dashboard page. Protected by a parent-defined 4-digit PIN.
 * Shows high-level learning statistics, detailed exercise progress (e.g. Memory, Quiz), and parent settings.
 */
import { useEffect, useState } from 'preact/hooks';
import { getTopicsList } from '../engine/ContentLoader';
import { getLectures } from '../engine/LectureStore';
import { t, getLanguage } from '../utils/i18n';
import { sendRewardToFamilyLink } from '../engine/familyLinkSync';

const PIN_STORAGE_KEY = 'baloo_parent_pin';
const SESSION_UNLOCK_KEY = 'baloo_dashboard_unlocked';

export function ParentDashboard() {
  const lang = getLanguage();
  
  // PIN lock states
  const [hasPin, setHasPin] = useState(!!localStorage.getItem(PIN_STORAGE_KEY));
  const [pinInput, setPinInput] = useState('');
  const [isUnlocked, setIsUnlocked] = useState(sessionStorage.getItem(SESSION_UNLOCK_KEY) === 'true');
  const [pinError, setPinError] = useState(false);
  const [newPin, setNewPin] = useState('');
  const [newPinConfirm, setNewPinConfirm] = useState('');
  const [settingsMessage, setSettingsMessage] = useState('');

  // FamilyLink Buddy Integration states
  const [flEnabled, setFlEnabled] = useState(localStorage.getItem('baloo_familylink_enabled') === 'true');
  const [flMode, setFlMode] = useState(localStorage.getItem('baloo_familylink_mode') || 'emulator');
  const [flToken, setFlToken] = useState(localStorage.getItem('baloo_familylink_token') || '');
  const [flRate, setFlRate] = useState(parseInt(localStorage.getItem('baloo_familylink_rate') || '2', 10));
  const [flTestMessage, setFlTestMessage] = useState('');
  const [isFlTesting, setIsFlTesting] = useState(false);
  
  // Data states
  const [stats, setStats] = useState({
    totalStars: 0,
    totalSpent: 0,
    totalLectures: 0,
    completedLectures: 0,
    lectureDetails: []
  });

  const getTranslated = (obj) => {
    if (!obj) return '';
    return obj[lang] || obj.de || '';
  };

  useEffect(() => {
    if (isUnlocked) {
      loadStats();
    }
  }, [isUnlocked]);

  const loadStats = () => {
    // 1. Get stars count
    const starsEarned = parseInt(localStorage.getItem('baloo_stars_earned') || '0', 10);
    const starsSpent = parseInt(localStorage.getItem('baloo_stars_spent') || '0', 10);
    const starBalance = parseInt(localStorage.getItem('baloo_stars') || '0', 10);

    // 2. Get all lectures (built-in + custom)
    const list = getTopicsList();
    
    // 3. Gather detail progress
    let completedCount = 0;
    const details = list.map(topic => {
      const gameModes = ['vocab', 'quiz', 'memory', 'spelling', 'puzzle'];
      const progressDetails = {};
      
      let modesCompleted = 0;
      gameModes.forEach(mode => {
        const isDone = localStorage.getItem(`baloo_done_${topic.id}_${mode}`) === 'true';
        if (isDone) modesCompleted++;
        
        let scoreStr = '';
        if (mode === 'quiz' || mode === 'spelling') {
          const correct = localStorage.getItem(`baloo_score_${topic.id}_${mode}_correct`) || '0';
          const total = localStorage.getItem(`baloo_score_${topic.id}_${mode}_total`) || '0';
          scoreStr = isDone ? `${correct}/${total}` : '-';
        } else {
          scoreStr = isDone ? '✓' : '-';
        }
        
        progressDetails[mode] = { completed: isDone, scoreText: scoreStr };
      });

      const isTopicCompleted = localStorage.getItem(`baloo_progress_${topic.id}`) === 'completed' || modesCompleted === 5;
      if (isTopicCompleted) {
        completedCount++;
      }

      return {
        id: topic.id,
        title: getTranslated(topic.title),
        category: topic.category || 'Biologie',
        isCustom: topic.isCustom || false,
        modesCompleted,
        isCompleted: isTopicCompleted,
        progress: progressDetails
      };
    });

    setStats({
      totalStars: starsEarned,
      totalSpent: starsSpent,
      totalLectures: list.length,
      completedLectures: completedCount,
      lectureDetails: details
    });
  };

  // Lock keypad handlers
  const handleKeypadPress = (num) => {
    setPinError(false);
    if (pinInput.length < 4) {
      const nextInput = pinInput + num;
      setPinInput(nextInput);
      
      // Auto-submit when 4 digits are entered
      if (nextInput.length === 4) {
        checkPin(nextInput);
      }
    }
  };

  const checkPin = (input) => {
    const savedPin = localStorage.getItem(PIN_STORAGE_KEY);
    if (input === savedPin) {
      setIsUnlocked(true);
      sessionStorage.setItem(SESSION_UNLOCK_KEY, 'true');
      setPinInput('');
    } else {
      setPinError(true);
      setPinInput('');
      // Vibrate if supported
      if (navigator.vibrate) navigator.vibrate(200);
    }
  };

  const handleCreatePin = (e) => {
    e.preventDefault();
    if (newPin.length !== 4 || !/^\d+$/.test(newPin)) {
      setSettingsMessage(lang === 'de' ? 'Der PIN muss genau 4 Zahlen enthalten.' : 'PIN must be exactly 4 digits.');
      return;
    }
    if (newPin !== newPinConfirm) {
      setSettingsMessage(lang === 'de' ? 'PINs stimmen nicht überein.' : 'PINs do not match.');
      return;
    }
    
    localStorage.setItem(PIN_STORAGE_KEY, newPin);
    setHasPin(true);
    setIsUnlocked(true);
    sessionStorage.setItem(SESSION_UNLOCK_KEY, 'true');
    setNewPin('');
    setNewPinConfirm('');
    setSettingsMessage('');
  };

  const handleClearPinInput = () => {
    setPinInput('');
    setPinError(false);
  };

  const handleLock = () => {
    setIsUnlocked(false);
    sessionStorage.removeItem(SESSION_UNLOCK_KEY);
  };

  // Change PIN settings form
  const handlePinChangeSubmit = (e) => {
    e.preventDefault();
    if (newPin.length !== 4 || !/^\d+$/.test(newPin)) {
      setSettingsMessage(lang === 'de' ? 'Der neue PIN muss aus 4 Zahlen bestehen.' : 'New PIN must be 4 digits.');
      return;
    }
    localStorage.setItem(PIN_STORAGE_KEY, newPin);
    setNewPin('');
    setSettingsMessage(lang === 'de' ? 'PIN erfolgreich geändert!' : 'PIN successfully updated!');
    setTimeout(() => setSettingsMessage(''), 3000);
  };

  // Reset progress settings
  const handleResetAllProgress = () => {
    const confirmMsg = lang === 'de'
      ? 'Möchtest du wirklich den gesamten Spielfortschritt, gelöste Aufgaben und Sterne löschen? Die Lektionen bleiben erhalten.'
      : 'Are you sure you want to reset all game progress, scores, and stars? Lectures will not be deleted.';
    
    if (window.confirm(confirmMsg)) {
      // Keep lectures, but clear progress keys
      const keysToRemove = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (
          key.startsWith('baloo_progress_') || 
          key.startsWith('baloo_done_') || 
          key.startsWith('baloo_score_')
        ) {
          keysToRemove.push(key);
        }
      }
      keysToRemove.forEach(k => localStorage.removeItem(k));
      
      // Reset stars
      localStorage.setItem('baloo_stars', '0');
      localStorage.setItem('baloo_stars_earned', '0');
      localStorage.setItem('baloo_stars_spent', '0');

      loadStats();
      setSettingsMessage(lang === 'de' ? 'Fortschritt erfolgreich zurückgesetzt!' : 'Progress successfully reset!');
      setTimeout(() => setSettingsMessage(''), 3000);
    }
  };

  // Render PIN Setup Screen
  if (!hasPin) {
    return (
      <div style={{ maxWidth: '400px', margin: '2rem auto', padding: '1rem' }}>
        <form onSubmit={handleCreatePin} class="card" style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1.25rem', textAlign: 'left' }}>
          <div style={{ textAlign: 'center', marginBottom: '0.5rem' }}>
            <span style={{ fontSize: '3rem' }}>🔒</span>
            <h2 style={{ marginTop: '0.5rem' }}>{lang === 'de' ? 'Eltern-Bereich einrichten' : 'Set Up Parents Area'}</h2>
            <p style={{ fontSize: '0.85rem', color: 'var(--color-text-secondary)', marginTop: '4px' }}>
              {lang === 'de'
                ? 'Erstelle einen 4-stelligen PIN, um den Elternbereich und die Lektionsverwaltung zu schützen.'
                : 'Create a 4-digit PIN to protect the parents dashboard and content uploads.'}
            </p>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.9rem', fontWeight: '600' }}>PIN festlegen (4 Zahlen)</label>
            <input
              type="password"
              inputMode="numeric"
              pattern="[0-9]*"
              maxLength={4}
              placeholder="z. B. 1234"
              value={newPin}
              onInput={(e) => setNewPin(e.target.value.replace(/\D/g, ''))}
              style={{
                padding: '12px',
                fontSize: '1.2rem',
                textAlign: 'center',
                letterSpacing: '10px',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--color-border-primary)',
                outline: 'none'
              }}
              required
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.9rem', fontWeight: '600' }}>PIN bestätigen</label>
            <input
              type="password"
              inputMode="numeric"
              pattern="[0-9]*"
              maxLength={4}
              placeholder="z. B. 1234"
              value={newPinConfirm}
              onInput={(e) => setNewPinConfirm(e.target.value.replace(/\D/g, ''))}
              style={{
                padding: '12px',
                fontSize: '1.2rem',
                textAlign: 'center',
                letterSpacing: '10px',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--color-border-primary)',
                outline: 'none'
              }}
              required
            />
          </div>

          {settingsMessage && (
            <div style={{ color: 'var(--color-danger)', fontSize: '0.85rem', textAlign: 'center' }}>
              {settingsMessage}
            </div>
          )}

          <button type="submit" class="btn btn-primary" style={{ padding: '12px', fontWeight: 'bold' }}>
            💾 PIN speichern
          </button>
        </form>
      </div>
    );
  }

  // Render PIN Unlock Keypad
  if (!isUnlocked) {
    return (
      <div style={{ maxWidth: '320px', margin: '2rem auto', padding: '1rem' }}>
        <div class="card" style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1.25rem' }}>
          
          <div style={{ textAlign: 'center' }}>
            <span style={{ fontSize: '2.5rem' }}>🔒</span>
            <h3 style={{ marginTop: '0.5rem' }}>{t('parent.pin_required')}</h3>
            
            {/* PIN Display Bubbles */}
            <div style={{ display: 'flex', gap: '12px', justifyContent: 'center', margin: '1rem 0 0.5rem' }}>
              {[0, 1, 2, 3].map(i => (
                <div
                  key={i}
                  style={{
                    width: '16px',
                    height: '16px',
                    borderRadius: '50%',
                    border: '2px solid var(--color-primary)',
                    backgroundColor: pinInput.length > i ? 'var(--color-primary)' : 'transparent',
                    transition: 'all 0.1s'
                  }}
                />
              ))}
            </div>

            {pinError && (
              <span style={{ color: 'var(--color-danger)', fontSize: '0.8rem', fontWeight: '600' }}>
                ❌ {t('parent.pin_error')}
              </span>
            )}
          </div>

          {/* Keypad Buttons */}
          <div style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(3, 1fr)',
            gap: '12px',
            width: '100%',
            maxWidth: '240px'
          }}>
            {[1, 2, 3, 4, 5, 6, 7, 8, 9].map(num => (
              <button
                key={num}
                type="button"
                onClick={() => handleKeypadPress(num.toString())}
                style={{
                  height: '52px',
                  borderRadius: '50%',
                  border: '1px solid var(--color-border-primary)',
                  backgroundColor: '#FFF',
                  fontSize: '1.3rem',
                  fontWeight: '600',
                  color: 'var(--color-text-primary)',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  boxShadow: '0 1px 2px rgba(0,0,0,0.05)',
                  transition: 'background-color 0.1s'
                }}
                onMouseDown={(e) => e.currentTarget.style.backgroundColor = 'var(--color-bg-secondary)'}
                onMouseUp={(e) => e.currentTarget.style.backgroundColor = '#FFF'}
              >
                {num}
              </button>
            ))}
            
            {/* Clear */}
            <button
              type="button"
              onClick={handleClearPinInput}
              style={{
                height: '52px',
                borderRadius: 'var(--radius-full)',
                border: 'none',
                backgroundColor: 'transparent',
                fontSize: '0.85rem',
                fontWeight: '600',
                color: 'var(--color-text-secondary)',
                cursor: 'pointer'
              }}
            >
              Clear
            </button>

            {/* 0 */}
            <button
              type="button"
              onClick={() => handleKeypadPress('0')}
              style={{
                height: '52px',
                borderRadius: '50%',
                border: '1px solid var(--color-border-primary)',
                backgroundColor: '#FFF',
                fontSize: '1.3rem',
                fontWeight: '600',
                color: 'var(--color-text-primary)',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 1px 2px rgba(0,0,0,0.05)'
              }}
            >
              0
            </button>

            <div />
          </div>

        </div>
      </div>
    );
  }

  // Render Dashboard Contents
  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', padding: '1rem 0' }}>
      
      {/* Top row controls */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div style={{ textAlign: 'left' }}>
          <h1 style={{ marginBottom: '4px' }}>👨‍👩‍👧 {t('parent.dashboard_title')}</h1>
          <p style={{ fontSize: '0.95rem', color: 'var(--color-text-secondary)' }}>
            Lernstatistiken und Systemsteuerung für Eltern.
          </p>
        </div>
        <button
          type="button"
          class="btn btn-secondary"
          onClick={handleLock}
          style={{ padding: '8px 14px', fontSize: '0.85rem', fontWeight: 'bold' }}
        >
          🔒 Dashboard sperren
        </button>
      </div>

      {/* Grid Stats Cards */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
        gap: '16px',
        marginBottom: '1.5rem'
      }}>
        <div class="card" style={{ padding: '1.25rem', textAlign: 'left' }}>
          <div style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)', fontWeight: 'bold', textTransform: 'uppercase' }}>
            {t('parent.lectures_count')}
          </div>
          <div style={{ fontSize: '2.2rem', fontWeight: 'bold', color: 'var(--color-primary)', marginTop: '4px' }}>
            {stats.totalLectures}
          </div>
          <div style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginTop: '4px' }}>
            {stats.completedLectures} vollständig erledigt
          </div>
        </div>

        <div class="card" style={{ padding: '1.25rem', textAlign: 'left' }}>
          <div style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)', fontWeight: 'bold', textTransform: 'uppercase' }}>
            Gesammelte Sterne
          </div>
          <div style={{ fontSize: '2.2rem', fontWeight: 'bold', color: '#D89E0B', marginTop: '4px' }}>
            ⭐ {stats.totalStars}
          </div>
          <div style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginTop: '4px' }}>
            {stats.totalSpent} Sterne für Spiele ausgegeben
          </div>
        </div>
      </div>

      {/* Granular Progress List */}
      <div class="card" style={{ padding: '1.5rem', textAlign: 'left', marginBottom: '1.5rem' }}>
        <h3 style={{ marginBottom: '1rem' }}>📋 {t('parent.lecture_status')}</h3>
        
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.9rem' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid var(--color-border-primary)', color: 'var(--color-text-secondary)' }}>
                <th style={{ padding: '10px 8px', textAlign: 'left' }}>Thema</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Bilder</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Quiz</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Memory</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Spelling</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Puzzle</th>
                <th style={{ padding: '10px 8px', textAlign: 'center' }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {stats.lectureDetails.map(lec => (
                <tr key={lec.id} style={{ borderBottom: '1px solid var(--color-border-primary)' }}>
                  <td style={{ padding: '12px 8px', fontWeight: '600' }}>
                    <div style={{ display: 'flex', flexDirection: 'column' }}>
                      <span>{lec.title}</span>
                      <span style={{ fontSize: '0.7rem', color: 'var(--color-text-muted)', fontWeight: 'normal' }}>
                        {lec.category} {lec.isCustom ? '(KI Lektion)' : ''}
                      </span>
                    </div>
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center', color: lec.progress.vocab.completed ? 'var(--color-success)' : 'inherit' }}>
                    {lec.progress.vocab.scoreText}
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center', color: lec.progress.quiz.completed ? 'var(--color-success)' : 'inherit', fontWeight: lec.progress.quiz.completed ? '600' : 'normal' }}>
                    {lec.progress.quiz.scoreText}
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center', color: lec.progress.memory.completed ? 'var(--color-success)' : 'inherit' }}>
                    {lec.progress.memory.scoreText}
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center', color: lec.progress.spelling.completed ? 'var(--color-success)' : 'inherit', fontWeight: lec.progress.spelling.completed ? '600' : 'normal' }}>
                    {lec.progress.spelling.scoreText}
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center', color: lec.progress.puzzle.completed ? 'var(--color-success)' : 'inherit' }}>
                    {lec.progress.puzzle.scoreText}
                  </td>
                  <td style={{ padding: '12px 8px', textAlign: 'center' }}>
                    <span style={{
                      fontSize: '0.75rem',
                      fontWeight: 'bold',
                      padding: '2px 8px',
                      borderRadius: 'var(--radius-full)',
                      backgroundColor: lec.isCompleted ? '#E6F5EE' : (lec.modesCompleted > 0 ? '#FFF4E6' : 'var(--color-bg-secondary)'),
                      color: lec.isCompleted ? 'var(--color-success)' : (lec.modesCompleted > 0 ? '#D87A0B' : 'var(--color-text-secondary)')
                    }}>
                      {lec.isCompleted ? 'Erledigt' : (lec.modesCompleted > 0 ? `${lec.modesCompleted}/5` : 'Neu')}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Settings Row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '16px' }}>
        
        {/* Change PIN */}
        <div class="card" style={{ padding: '1.5rem', textAlign: 'left' }}>
          <h3 style={{ marginBottom: '8px' }}>🔐 Eltern-PIN ändern</h3>
          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginBottom: '1rem' }}>
            Ersetze den aktuellen PIN durch einen neuen 4-stelligen Code.
          </p>
          
          <form onSubmit={handlePinChangeSubmit} style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <input
              type="password"
              inputMode="numeric"
              pattern="[0-9]*"
              maxLength={4}
              placeholder="Neuer PIN"
              value={newPin}
              onInput={(e) => setNewPin(e.target.value.replace(/\D/g, ''))}
              style={{
                padding: '8px 12px',
                fontSize: '1rem',
                borderRadius: 'var(--radius-sm)',
                border: '1px solid var(--color-border-primary)',
                width: '120px',
                outline: 'none',
                textAlign: 'center'
              }}
              required
            />
            <button type="submit" class="btn btn-secondary" style={{ padding: '8px 14px' }}>
              Speichern
            </button>
          </form>
          
          {settingsMessage && (
            <div style={{ fontSize: '0.8rem', color: settingsMessage.includes('erfolgreich') ? 'var(--color-success)' : 'var(--color-danger)', marginTop: '8px', fontWeight: '500' }}>
              {settingsMessage}
            </div>
          )}
        </div>

        {/* FamilyLink Buddy Integration */}
        <div class="card" style={{ padding: '1.5rem', textAlign: 'left' }}>
          <h3 style={{ marginBottom: '8px' }}>🟢 FamilyLink Buddy</h3>
          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginBottom: '1rem' }}>
            Belohne dein Kind mit Bildschirmzeit, wenn es Lektionen lernt.
          </p>
          
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '0.9rem' }}>
              <input
                type="checkbox"
                checked={flEnabled}
                onChange={(e) => {
                  const val = e.target.checked;
                  setFlEnabled(val);
                  localStorage.setItem('baloo_familylink_enabled', val ? 'true' : 'false');
                }}
              />
              <span>Integration aktivieren</span>
            </label>
            
            {flEnabled && (
              <>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                  <span style={{ fontSize: '0.8rem', fontWeight: '500', color: 'var(--color-text-secondary)' }}>Verbindungstyp:</span>
                  <div style={{ display: 'flex', gap: '16px' }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.85rem', cursor: 'pointer' }}>
                      <input
                        type="radio"
                        name="flMode"
                        value="emulator"
                        checked={flMode === 'emulator'}
                        onChange={() => {
                          setFlMode('emulator');
                          localStorage.setItem('baloo_familylink_mode', 'emulator');
                        }}
                      />
                      Local Emulator
                    </label>
                    <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.85rem', cursor: 'pointer' }}>
                      <input
                        type="radio"
                        name="flMode"
                        value="production"
                        checked={flMode === 'production'}
                        onChange={() => {
                          setFlMode('production');
                          localStorage.setItem('baloo_familylink_mode', 'production');
                        }}
                      />
                      Production Cloud
                    </label>
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                  <label for="flToken" style={{ fontSize: '0.8rem', fontWeight: '500', color: 'var(--color-text-secondary)' }}>Kinder-Token (Pairing-Token):</label>
                  <input
                    id="flToken"
                    type="text"
                    value={flToken}
                    onInput={(e) => {
                      setFlToken(e.target.value);
                      localStorage.setItem('baloo_familylink_token', e.target.value);
                    }}
                    placeholder="z.B. device_pairing_token"
                    style={{
                      padding: '8px 12px',
                      fontSize: '0.9rem',
                      borderRadius: 'var(--radius-sm)',
                      border: '1px solid var(--color-border-primary)',
                      outline: 'none'
                    }}
                  />
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                  <label for="flRate" style={{ fontSize: '0.8rem', fontWeight: '500', color: 'var(--color-text-secondary)' }}>Wechselkurs (Minuten pro Stern):</label>
                  <input
                    id="flRate"
                    type="number"
                    min={1}
                    max={60}
                    value={flRate}
                    onChange={(e) => {
                      const val = parseInt(e.target.value, 10) || 2;
                      setFlRate(val);
                      localStorage.setItem('baloo_familylink_rate', val.toString());
                    }}
                    style={{
                      padding: '8px 12px',
                      fontSize: '0.9rem',
                      borderRadius: 'var(--radius-sm)',
                      border: '1px solid var(--color-border-primary)',
                      outline: 'none',
                      width: '80px'
                    }}
                  />
                </div>

                <div style={{ display: 'flex', gap: '8px', alignItems: 'center', marginTop: '4px' }}>
                  <button
                    type="button"
                    class="btn btn-secondary"
                    onClick={async () => {
                      if (!flToken) {
                        setFlTestMessage('Fehler: Bitte gib einen Kinder-Token ein.');
                        return;
                      }
                      setIsFlTesting(true);
                      setFlTestMessage('');
                      try {
                        const newRemaining = await sendRewardToFamilyLink(flToken, flMode, 1);
                        setFlTestMessage(`Erfolgreich! +1 Testminute gesendet (Jetzt: ${newRemaining} Min.)`);
                      } catch (err) {
                        setFlTestMessage(`Verbindungsfehler: ${err.message}`);
                      } finally {
                        setIsFlTesting(false);
                      }
                    }}
                    disabled={isFlTesting}
                    style={{ padding: '8px 14px', fontSize: '0.85rem' }}
                  >
                    {isFlTesting ? 'Verbinde...' : '🔌 Testminute senden'}
                  </button>
                </div>
                
                {flTestMessage && (
                  <div style={{
                    fontSize: '0.8rem',
                    color: flTestMessage.includes('Erfolgreich') ? 'var(--color-success)' : 'var(--color-danger)',
                    marginTop: '4px',
                    fontWeight: '500'
                  }}>
                    {flTestMessage}
                  </div>
                )}
              </>
            )}
          </div>
        </div>

        {/* Danger zone / Reset stats */}
        <div class="card" style={{ padding: '1.5rem', textAlign: 'left', border: '1px solid #FBEBEB' }}>
          <h3 style={{ marginBottom: '8px', color: 'var(--color-danger)' }}>⚠️ Daten zurücksetzen</h3>
          <p style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', marginBottom: '1.25rem' }}>
            Setze alle gelösten Lektionen, Sterne und Spielrunden zurück. Die erstellten Lektionen bleiben erhalten.
          </p>
          
          <button
            type="button"
            class="btn btn-secondary"
            onClick={handleResetAllProgress}
            style={{
              padding: '8px 14px',
              color: 'var(--color-danger)',
              borderColor: 'var(--color-danger)',
              backgroundColor: 'transparent'
            }}
            onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#FBEBEB'}
            onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
          >
            Alle Spieldaten löschen
          </button>
        </div>

      </div>

    </div>
  );
}
