/* src/router.jsx */
import { useState, useEffect } from 'preact/hooks';

// Navigation helper
export function navigate(path) {
  window.location.hash = path.startsWith('/') ? path : '/' + path;
}

// Custom hook to listen to route changes
export function useRoute() {
  const [route, setRoute] = useState(window.location.hash.slice(1) || '/');

  useEffect(() => {
    const handleHashChange = () => {
      setRoute(window.location.hash.slice(1) || '/');
    };

    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, []);

  // Parse path and params
  // E.g. /topic/das-auge -> path: '/topic/:id', params: { id: 'das-auge' }
  const parseRoute = () => {
    const segments = route.split('/').filter(Boolean);
    
    if (segments.length === 0) {
      return { path: '/', params: {} };
    }
    
    if (segments[0] === 'topic' && segments[1]) {
      return { path: '/topic/:id', params: { id: segments[1] } };
    }
    
    if (segments[0] === 'print' && segments[1]) {
      return { path: '/print/:id', params: { id: segments[1] } };
    }
    
    return { path: '/' + segments.join('/'), params: {} };
  };

  return parseRoute();
}
