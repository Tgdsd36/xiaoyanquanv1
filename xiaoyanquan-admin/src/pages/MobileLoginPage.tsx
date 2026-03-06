import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Button, Form, Input, message } from 'antd';
import { LockOutlined, SafetyCertificateOutlined, UserOutlined } from '@ant-design/icons';
import mobileHttp from '../api/mobileHttp';
import {
  isMobileAuthenticated,
  setMobileAdminInfo,
  setMobileToken,
} from '../utils/mobileAuth';
import './MobileLoginPage.css';

export default function MobileLoginPage() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);

  if (isMobileAuthenticated()) {
    return <Navigate to="/mobile/dashboard" replace />;
  }

  const handleFinish = async (values: { username: string; password: string }) => {
    setLoading(true);
    try {
      const { data } = await mobileHttp.post('/login', values);
      if (data.code === 0) {
        setMobileToken(data.data.token);
        setMobileAdminInfo({
          admin_id: data.data.admin_id,
          username: data.data.username,
          role: data.data.role,
        });
        message.success('登录成功');
        navigate('/mobile/dashboard', { replace: true });
      } else {
        message.error(data.message || '登录失败');
      }
    } catch {
      message.error('登录失败');
    }
    setLoading(false);
  };

  return (
    <div className="mobile-admin-login">
      <section className="mobile-admin-login__card">
        <div className="mobile-admin-login__brand">小颜圈手机后台</div>
        <h1>登录后上传素材</h1>
        <p>手机端上传入口仅供管理员使用，请先登录。</p>

        <Form layout="vertical" requiredMark={false} onFinish={handleFinish} autoComplete="off">
          <Form.Item
            label="账号"
            name="username"
            rules={[{ required: true, message: '请输入管理员账号' }]}
          >
            <Input prefix={<UserOutlined />} placeholder="请输入管理员账号" size="large" />
          </Form.Item>
          <Form.Item
            label="密码"
            name="password"
            rules={[{ required: true, message: '请输入登录密码' }]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder="请输入登录密码" size="large" />
          </Form.Item>
          <Button type="primary" htmlType="submit" block size="large" loading={loading}>
            登录手机后台
          </Button>
        </Form>

        <div className="mobile-admin-login__hint">
          <SafetyCertificateOutlined />
          <span>后台接口校验已启用</span>
        </div>
      </section>
    </div>
  );
}
