import { Routes, Route, Navigate } from 'react-router-dom';
import { isAuthenticated } from './utils/auth';
import { isMobileAuthenticated } from './utils/mobileAuth';
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
import MobileUploadPage from './pages/MobileUploadPage';
import MobileLoginPage from './pages/MobileLoginPage';
import MobileAdminLayout from './components/MobileAdminLayout';
import MobileDashboardPage from './pages/mobile/MobileDashboardPage';
import MobileAssetsPage from './pages/mobile/MobileAssetsPage';
import MobileMaterialsPage from './pages/mobile/MobileMaterialsPage';
import MobileQuestionsPage from './pages/mobile/MobileQuestionsPage';
import MobileLiveDebugPage from './pages/mobile/MobileLiveDebugPage';

function PrivateRoute({ children }: { children: React.ReactNode }) {
  return isAuthenticated() ? <>{children}</> : <Navigate to="/login" replace />;
}

function MobilePrivateRoute({ children }: { children: React.ReactNode }) {
  return isMobileAuthenticated() ? <>{children}</> : <Navigate to="/mobile-login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/mobile-login" element={<MobileLoginPage />} />
      <Route
        path="/mobile-upload"
        element={
          <MobilePrivateRoute>
            <Navigate to="/mobile/upload" replace />
          </MobilePrivateRoute>
        }
      />
      <Route
        path="/mobile/*"
        element={
          <MobilePrivateRoute>
            <MobileAdminLayout />
          </MobilePrivateRoute>
        }
      >
        <Route index element={<Navigate to="/mobile/dashboard" replace />} />
        <Route path="dashboard" element={<MobileDashboardPage />} />
        <Route path="upload" element={<MobileUploadPage />} />
        <Route path="assets" element={<MobileAssetsPage />} />
        <Route path="materials" element={<MobileMaterialsPage />} />
        <Route path="questions" element={<MobileQuestionsPage />} />
        <Route path="live-debug" element={<MobileLiveDebugPage />} />
      </Route>
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
