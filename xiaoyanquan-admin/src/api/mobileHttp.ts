import axios from 'axios';
import { removeMobileToken, getMobileToken } from '../utils/mobileAuth';

const mobileHttp = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080/api/admin',
  timeout: 15000,
});

mobileHttp.interceptors.request.use((config) => {
  const token = getMobileToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

mobileHttp.interceptors.response.use(
  (resp) => resp,
  (error) => {
    if (error.response?.status === 401) {
      removeMobileToken();
      window.location.href = '/mobile-login';
    }
    return Promise.reject(error);
  },
);

export default mobileHttp;

