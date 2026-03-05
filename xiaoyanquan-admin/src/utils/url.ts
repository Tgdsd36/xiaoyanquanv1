const defaultApiBaseURL = 'http://localhost:8080/api/admin';

export const apiBaseURL = import.meta.env.VITE_API_BASE_URL || defaultApiBaseURL;

export const apiOrigin = (() => {
  try {
    const baseOrigin = typeof window !== 'undefined' ? window.location.origin : 'http://localhost';
    return new URL(apiBaseURL, baseOrigin).origin;
  } catch {
    return typeof window !== 'undefined' ? window.location.origin : 'http://localhost';
  }
})();

export function toAbsoluteUrl(path: string): string {
  const raw = (path || '').trim();
  if (!raw) return '';
  if (/^https?:\/\//i.test(raw)) return raw;
  return `${apiOrigin}${raw.startsWith('/') ? '' : '/'}${raw}`;
}
