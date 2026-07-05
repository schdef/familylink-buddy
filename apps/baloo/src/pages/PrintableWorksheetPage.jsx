/* src/pages/PrintableWorksheetPage.jsx
 * Renders a clean, high-contrast, print-optimized worksheet for a specific lecture.
 * Hides navigation UI and provides learning overview and exercises.
 */
import { useState, useEffect } from 'preact/hooks';
import { getTopicById } from '../engine/ContentLoader';
import { getLanguage, t } from '../utils/i18n';
import { stripSvgLabels } from '../utils/svgUtils';
import { navigate } from '../router';

export function PrintableWorksheetPage({ id }) {
  const lang = getLanguage();
  const [topic, setTopic] = useState(null);

  useEffect(() => {
    if (id) {
      setTopic(getTopicById(id));
    }
  }, [id]);

  if (!topic) {
    return <div style={{ padding: '2rem', textAlign: 'center' }}>Lade Arbeitsblatt...</div>;
  }

  const title = topic.title[lang] || topic.title.de;
  const description = topic.description?.[lang] || topic.description?.de;

  const handlePrint = () => {
    window.print();
  };

  return (
    <div class="print-page-wrapper">
      {/* Non-printable controls */}
      <div class="no-print" style={{ 
        padding: '1rem', 
        backgroundColor: 'var(--color-bg-secondary)', 
        display: 'flex', 
        justifyContent: 'space-between',
        alignItems: 'center',
        borderBottom: '1px solid var(--color-border-primary)',
        marginBottom: '2rem'
      }}>
        <button class="btn btn-secondary" onClick={() => navigate('/manager')}>
          ← {lang === 'de' ? 'Zurück' : 'Back'}
        </button>
        <button class="btn btn-primary" onClick={handlePrint} style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          🖨️ {lang === 'de' ? 'Arbeitsblatt drucken' : 'Print Worksheet'}
        </button>
      </div>

      {/* Printable Area */}
      <div class="printable-area" style={{ maxWidth: '800px', margin: '0 auto', padding: '0 2rem' }}>
        
        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
          <h1 style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>{title}</h1>
          <p style={{ fontSize: '1.2rem', color: '#555' }}>{description}</p>
          <div style={{ 
            marginTop: '2rem', 
            display: 'flex', 
            justifyContent: 'flex-end', 
            gap: '10px',
            fontSize: '1rem'
          }}>
            <span>Name: _______________________</span>
            <span style={{ marginLeft: '2rem' }}>Datum: ____________</span>
          </div>
        </div>

        {/* Part 1: Learning Overview */}
        <div style={{ pageBreakAfter: 'always' }}>
          <h2 style={{ borderBottom: '2px solid #000', paddingBottom: '0.5rem', marginBottom: '2rem' }}>
            {lang === 'de' ? 'Teil 1: Lernübersicht' : 'Part 1: Learning Overview'}
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '2rem' }}>
            {topic.cards.map((card, idx) => (
              <div key={idx} style={{ 
                border: '1px solid #ccc', 
                borderRadius: '8px', 
                padding: '1rem',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                textAlign: 'center'
              }}>
                <div style={{ 
                  width: '100%', 
                  maxWidth: '200px', 
                  aspectRatio: '16/9',
                  marginBottom: '1rem'
                }} dangerouslySetInnerHTML={{ __html: card.svg }} />
                <h3 style={{ margin: '0 0 0.5rem 0', fontSize: '1.4rem' }}>
                  {card.term[lang] || card.term.de}
                </h3>
                <p style={{ margin: 0, fontSize: '1rem', color: '#333' }}>
                  {card.def[lang] || card.def.de}
                </p>
              </div>
            ))}
          </div>
        </div>

        {/* Part 2: Exercise */}
        <div>
          <h2 style={{ borderBottom: '2px solid #000', paddingBottom: '0.5rem', marginBottom: '2rem' }}>
            {lang === 'de' ? 'Teil 2: Übung - Wie heißen die Bilder?' : 'Part 2: Exercise - Name the pictures'}
          </h2>
          <p style={{ marginBottom: '2rem', fontSize: '1.1rem' }}>
            {lang === 'de' 
              ? 'Schreibe den passenden Begriff unter jedes Bild.' 
              : 'Write the correct term under each picture.'}
          </p>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '3rem' }}>
            {/* Shuffle cards for the test to make it fun */}
            {[...topic.cards].sort(() => Math.random() - 0.5).map((card, idx) => (
              <div key={idx} style={{ 
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                textAlign: 'center'
              }}>
                <div style={{ 
                  width: '100%', 
                  maxWidth: '220px', 
                  aspectRatio: '16/9',
                  marginBottom: '1.5rem',
                  border: '1px solid #eee',
                  padding: '0.5rem'
                }} dangerouslySetInnerHTML={{ __html: stripSvgLabels(card.svg) }} />
                
                {/* Writing line */}
                <div style={{ 
                  width: '80%', 
                  borderBottom: '2px dashed #999', 
                  height: '2rem' 
                }}></div>
              </div>
            ))}
          </div>
        </div>

      </div>

      <style>{`
        @media print {
          body * {
            visibility: hidden;
          }
          .printable-area, .printable-area * {
            visibility: visible;
          }
          .printable-area {
            position: absolute;
            left: 0;
            top: 0;
            width: 100%;
          }
          .no-print {
            display: none !important;
          }
          
          /* Force colors and background colors for printing */
          * {
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
          }
        }
      `}</style>
    </div>
  );
}
