/* src/components/FeedbackBanner.jsx */

export function FeedbackBanner({ status, message }) {
  if (!status) return <div style={{ minHeight: '44px' }} />;

  const isCorrect = status === 'correct';

  return (
    <div 
      role="status" 
      aria-live="polite"
      class={`fb-banner ${isCorrect ? 'success' : 'error'}`}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '10px',
        padding: '12px 16px',
        borderRadius: 'var(--radius-md)',
        fontWeight: '600',
        fontSize: '0.95rem',
        margin: '0.75rem 0',
        border: '1px solid',
        backgroundColor: isCorrect ? 'var(--color-success-bg)' : 'var(--color-error-bg)',
        borderColor: isCorrect ? 'var(--color-success-border)' : 'var(--color-error-border)',
        color: isCorrect ? '#1E4D35' : '#7A3333'
      }}
    >
      <span style={{ fontSize: '1.2rem' }}>
        {isCorrect ? '🎉' : '💡'}
      </span>
      <span>{message}</span>
    </div>
  );
}
