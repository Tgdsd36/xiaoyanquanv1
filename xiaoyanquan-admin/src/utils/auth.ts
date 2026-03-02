export function getToken(): string | null {
  return localStorage.getItem('admin_token');
}

export function setToken(token: string) {
  localStorage.setItem('admin_token', token);
}

export function removeToken() {
  localStorage.removeItem('admin_token');
  localStorage.removeItem('admin_info');
}

export function getAdminInfo() {
  const raw = localStorage.getItem('admin_info');
  return raw ? JSON.parse(raw) : null;
}

export function setAdminInfo(info: { admin_id: number; username: string; role: string }) {
  localStorage.setItem('admin_info', JSON.stringify(info));
}

export function isAuthenticated(): boolean {
  return !!getToken();
}
