import { LogoutOutlined } from '@ant-design/icons';
import { Button } from 'antd';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { removeMobileToken } from '../utils/mobileAuth';
import './MobileAdminLayout.css';

const tabs: Array<{ key: string; label: string; path: string }> = [
  { key: 'dashboard', label: '看板', path: '/mobile/dashboard' },
  { key: 'upload', label: '上传', path: '/mobile/upload' },
  { key: 'assets', label: '素材库', path: '/mobile/assets' },
  { key: 'materials', label: '素材', path: '/mobile/materials' },
  { key: 'questions', label: '提问', path: '/mobile/questions' },
];

export default function MobileAdminLayout() {
  const navigate = useNavigate();
  const location = useLocation();

  const activeKey = tabs.find((tab) => location.pathname.startsWith(tab.path))?.key;

  return (
    <div className="mobile-admin-layout">
      <header className="mobile-admin-layout__header">
        <div>
          <h1>小颜圈手机后台</h1>
          <p>运营快捷入口</p>
        </div>
        <Button
          type="text"
          icon={<LogoutOutlined />}
          onClick={() => {
            removeMobileToken();
            navigate('/mobile-login', { replace: true });
          }}
        >
          退出
        </Button>
      </header>

      <main className="mobile-admin-layout__content">
        <Outlet />
      </main>

      <nav className="mobile-admin-layout__tabbar">
        {tabs.map((tab) => (
          <button
            key={tab.key}
            className={`mobile-admin-layout__tab ${activeKey === tab.key ? 'is-active' : ''}`}
            onClick={() => navigate(tab.path)}
            type="button"
          >
            {tab.label}
          </button>
        ))}
      </nav>
    </div>
  );
}
