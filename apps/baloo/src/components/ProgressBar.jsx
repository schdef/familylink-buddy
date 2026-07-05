/* src/components/ProgressBar.jsx */

export function ProgressBar({ current, total }) {
  const chunks = Array.from({ length: total }, (_, i) => i);
  
  return (
    <div 
      class="chunked-progress" 
      aria-label={`Fortschritt: Schritt ${current} von ${total}`}
      style={{
        display: 'flex',
        gap: '6px',
        width: '100%',
        marginBottom: '1.25rem',
        marginTop: '0.25rem'
      }}
    >
      {chunks.map(index => (
        <div
          key={index}
          class={`progress-chunk ${index < current ? 'filled' : ''}`}
          style={{
            height: '6px',
            flex: '1',
            borderRadius: 'var(--radius-full)',
            backgroundColor: index < current ? 'var(--color-success)' : 'var(--color-bg-tertiary)',
            transition: 'background-color 0.25s ease-out'
          }}
        />
      ))}
    </div>
  );
}
