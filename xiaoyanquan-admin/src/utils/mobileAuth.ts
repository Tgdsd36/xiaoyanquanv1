const MOBILE_TOKEN_KEY = 'mobile_admin_token';
const MOBILE_INFO_KEY = 'mobile_admin_info';

export function getMobileToken(): string | null {
  return localStorage.getItem(MOBILE_TOKEN_KEY);
}

export function setMobileToken(token: string) {
  localStorage.setItem(MOBILE_TOKEN_KEY, token);
}

export function removeMobileToken() {
  localStorage.removeItem(MOBILE_TOKEN_KEY);
  localStorage.removeItem(MOBILE_INFO_KEY);
}

export function setMobileAdminInfo(info: { admin_id: number; username: string; role: string }) {
  localStorage.setItem(MOBILE_INFO_KEY, JSON.stringify(info));
}

export function getMobileAdminInfo() {
  const raw = localStorage.getItem(MOBILE_INFO_KEY);
  return raw ? JSON.parse(raw) : null;
}

export function isMobileAuthenticated(): boolean {
  return !!getMobileToken();
}

