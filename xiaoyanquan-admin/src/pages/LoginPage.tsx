import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Form, Input, Button, message } from 'antd';
import {
  UserOutlined,
  LockOutlined,
  SafetyCertificateOutlined,
} from '@ant-design/icons';
import http from '../api/http';
import { setToken, setAdminInfo } from '../utils/auth';
import './LoginPage.css';

export default function LoginPage() {
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const onFinish = async (values: { username: string; password: string }) => {
    setLoading(true);
    try {
      const { data } = await http.post('/login', values);
      if (data.code === 0) {
        setToken(data.data.token);
        setAdminInfo({
          admin_id: data.data.admin_id,
          username: data.data.username,
          role: data.data.role,
        });
        message.success('登录成功');
        navigate('/', { replace: true });
      } else {
        message.error(data.message || '登录失败');
      }
    } catch {
      message.error('登录失败');
    }
    setLoading(false);
  };

  return (
    <div className="admin-login admin-login--minimal">
      <div className="admin-login__minimal-grid" />
      <section className="admin-login__minimal-card">
        <div className="admin-login__minimal-brand">小颜圈 · Admin</div>
        <h1>管理后台登录</h1>
        <p>请输入管理员账号与密码，继续进入运营控制台。</p>

        <Form
          onFinish={onFinish}
          size="large"
          layout="vertical"
          requiredMark={false}
          autoComplete="off"
        >
          <Form.Item
            label="账号"
            name="username"
            rules={[{ required: true, message: '请输入用户名' }]}
          >
            <Input
              prefix={<UserOutlined />}
              placeholder="请输入管理员账号"
            />
          </Form.Item>
          <Form.Item
            label="密码"
            name="password"
            rules={[{ required: true, message: '请输入密码' }]}
          >
            <Input.Password
              prefix={<LockOutlined />}
              placeholder="请输入登录密码"
            />
          </Form.Item>
          <Form.Item style={{ marginBottom: 8 }}>
            <Button type="primary" htmlType="submit" loading={loading} block>
              登录后台
            </Button>
          </Form.Item>
        </Form>

        <div className="admin-login__minimal-footer">
          <SafetyCertificateOutlined />
          <span>企业级安全校验已启用</span>
        </div>
      </section>
      <div className="admin-login__copyright">© {new Date().getFullYear()} 小颜圈管理系统</div>
    </div>
  );
}
