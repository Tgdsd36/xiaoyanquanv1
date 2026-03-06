import { useState } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { Layout, Menu, Button, theme, Modal, Form, Input, message } from 'antd';
import {
  DashboardOutlined,
  PictureOutlined,
  AppstoreOutlined,
  QuestionCircleOutlined,
  UserOutlined,
  ShoppingOutlined,
  LogoutOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  CloudUploadOutlined,
  LockOutlined,
  MobileOutlined,
} from '@ant-design/icons';
import { removeToken, getAdminInfo } from '../utils/auth';
import http from '../api/http';

const { Header, Sider, Content } = Layout;

const menuItems = [
  { key: '/', icon: <DashboardOutlined />, label: '数据看板' },
  { key: '/assets', icon: <CloudUploadOutlined />, label: '素材库' },
  { key: '/materials', icon: <PictureOutlined />, label: '素材管理' },
  { key: '/categories', icon: <AppstoreOutlined />, label: '分类管理' },
  { key: '/questions', icon: <QuestionCircleOutlined />, label: '提问管理' },
  { key: '/users', icon: <UserOutlined />, label: '用户管理' },
  { key: '/orders', icon: <ShoppingOutlined />, label: '订单管理' },
];

export default function AdminLayout() {
  const [collapsed, setCollapsed] = useState(false);
  const [passwordModalOpen, setPasswordModalOpen] = useState(false);
  const [passwordSubmitting, setPasswordSubmitting] = useState(false);
  const [passwordForm] = Form.useForm();
  const navigate = useNavigate();
  const location = useLocation();
  const { token: { colorBgContainer, borderRadiusLG } } = theme.useToken();
  const adminInfo = getAdminInfo();

  const handleLogout = () => {
    removeToken();
    navigate('/login');
  };

  const openPasswordModal = () => {
    passwordForm.resetFields();
    setPasswordModalOpen(true);
  };

  const handleChangePassword = async () => {
    try {
      const values = await passwordForm.validateFields();
      setPasswordSubmitting(true);
      const { data: resp } = await http.put('/password', {
        old_password: values.old_password,
        new_password: values.new_password,
      });
      if (resp.code === 0) {
        message.success('密码修改成功，请重新登录');
        setPasswordModalOpen(false);
        passwordForm.resetFields();
        handleLogout();
        return;
      }
      message.error(resp.message || '密码修改失败');
    } catch (error: any) {
      if (error?.errorFields) return;
      message.error(error?.response?.data?.message || '密码修改失败');
    } finally {
      setPasswordSubmitting(false);
    }
  };

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider trigger={null} collapsible collapsed={collapsed}>
        <div style={{ height: 48, margin: 16, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color: '#fff', fontSize: collapsed ? 14 : 18, fontWeight: 'bold', whiteSpace: 'nowrap' }}>
            {collapsed ? '小颜' : '小颜圈后台管理系统'}
          </span>
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[location.pathname]}
          items={menuItems}
          onClick={({ key }) => navigate(key)}
        />
      </Sider>
      <Layout>
        <Header style={{ padding: '0 24px', background: colorBgContainer, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Button
            type="text"
            icon={collapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
            onClick={() => setCollapsed(!collapsed)}
          />
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <span>{adminInfo?.username ?? '管理员'}</span>
            <Button type="text" icon={<MobileOutlined />} onClick={() => navigate('/mobile-upload')}>
              手机上传
            </Button>
            <Button type="text" icon={<LockOutlined />} onClick={openPasswordModal}>
              修改密码
            </Button>
            <Button type="text" icon={<LogoutOutlined />} onClick={handleLogout}>
              退出
            </Button>
          </div>
        </Header>
        <Content style={{ margin: 24, padding: 24, background: colorBgContainer, borderRadius: borderRadiusLG, overflow: 'auto' }}>
          <Outlet />
        </Content>
      </Layout>
      <Modal
        title="修改管理员密码"
        open={passwordModalOpen}
        onCancel={() => setPasswordModalOpen(false)}
        onOk={handleChangePassword}
        confirmLoading={passwordSubmitting}
        okText="确认修改"
        cancelText="取消"
        destroyOnClose
      >
        <Form form={passwordForm} layout="vertical">
          <Form.Item
            label="旧密码"
            name="old_password"
            rules={[{ required: true, message: '请输入旧密码' }, { min: 6, message: '密码至少6位' }]}
          >
            <Input.Password placeholder="请输入当前密码" />
          </Form.Item>
          <Form.Item
            label="新密码"
            name="new_password"
            rules={[{ required: true, message: '请输入新密码' }, { min: 6, message: '密码至少6位' }]}
          >
            <Input.Password placeholder="请输入新密码" />
          </Form.Item>
          <Form.Item
            label="确认新密码"
            name="confirm_password"
            dependencies={['new_password']}
            rules={[
              { required: true, message: '请再次输入新密码' },
              ({ getFieldValue }) => ({
                validator(_, value) {
                  if (!value || getFieldValue('new_password') === value) {
                    return Promise.resolve();
                  }
                  return Promise.reject(new Error('两次输入的新密码不一致'));
                },
              }),
            ]}
          >
            <Input.Password placeholder="请再次输入新密码" />
          </Form.Item>
        </Form>
      </Modal>
    </Layout>
  );
}
