import { Routes, Route, Navigate } from 'react-router-dom';
import { isAuthenticated } from './utils/auth';
import AdminLayout from './components/AdminLayout';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import MaterialPage from './pages/MaterialPage';
import CategoryPage from './pages/CategoryPage';
import QuestionPage from './pages/QuestionPage';
import UserPage from './pages/UserPage';
import OrderPage from './pages/OrderPage';
import ConfigPage from './pages/ConfigPage';
import AssetPage from './pages/AssetPage';

function PrivateRoute({ children }: { children: React.ReactNode }) {
  return isAuthenticated() ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/*"
        element={
          <PrivateRoute>
            <AdminLayout />
          </PrivateRoute>
        }
      >
        <Route index element={<DashboardPage />} />
        <Route path="assets" element={<AssetPage />} />
        <Route path="materials" element={<MaterialPage />} />
        <Route path="categories" element={<CategoryPage />} />
        <Route path="questions" element={<QuestionPage />} />
        <Route path="users" element={<UserPage />} />
        <Route path="orders" element={<OrderPage />} />
        <Route path="configs" element={<ConfigPage />} />
      </Route>
    </Routes>
  );
}
