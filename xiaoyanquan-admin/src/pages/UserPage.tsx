import { useEffect, useState, useCallback } from 'react';
import { Table, Input, Select, Space, Tag, Button, Modal, Form, Switch, Popconfirm, message } from 'antd';
import { SearchOutlined, PlusOutlined } from '@ant-design/icons';
import http from '../api/http';

const memberLabels: Record<string, { text: string; color: string }> = {
  free: { text: '普通', color: 'default' },
  pro: { text: '专业版', color: 'blue' },
  flagship: { text: '旗舰版', color: 'gold' },
};

export default function UserPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [keyword, setKeyword] = useState('');
  const [memberType, setMemberType] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (memberType) params.member_type = memberType;
    const { data: resp } = await http.get('/users', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, keyword, memberType]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleCreate = async () => {
    const values = await form.validateFields();
    try {
      const { data: resp } = await http.post('/users', values);
      if (resp.code === 0) {
        message.success('创建成功');
        setModalOpen(false);
        form.resetFields();
        fetchData();
      } else {
        message.error(resp.message || '创建失败');
      }
    } catch {
      message.error('创建失败');
    }
  };

  const handleToggleStatus = async (id: number, currentStatus: string) => {
    const newStatus = currentStatus === 'active' ? 'disabled' : 'active';
    await http.put(`/users/${id}/status`, { status: newStatus });
    message.success(newStatus === 'active' ? '已启用' : '已禁用');
    fetchData();
  };

  const handleDelete = async (id: number) => {
    await http.delete(`/users/${id}`);
    message.success('已删除');
    fetchData();
  };

  const handleBatchDelete = async () => {
    if (!selectedRowKeys.length) return;
    await http.post('/users/batch-delete', { ids: selectedRowKeys.map(Number) });
    message.success('批量删除成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const handleBatchStatus = async (status: string) => {
    if (!selectedRowKeys.length) return;
    await http.post('/users/batch-status', { ids: selectedRowKeys.map(Number), status });
    message.success('批量更新成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '手机号', dataIndex: 'phone', width: 130 },
    { title: '昵称', dataIndex: 'nickname' },
    {
      title: '会员类型', dataIndex: 'member_type', width: 100,
      render: (t: string) => {
        const m = memberLabels[t] || memberLabels.free;
        return <Tag color={m.color}>{m.text}</Tag>;
      },
    },
    {
      title: '状态', dataIndex: 'status', width: 80,
      render: (s: string) => (
        <Tag color={s === 'active' ? 'green' : 'red'}>{s === 'active' ? '正常' : '已禁用'}</Tag>
      ),
    },
    { title: '注册时间', dataIndex: 'created_at', width: 170 },
    {
      title: '操作', width: 180,
      render: (_: any, row: any) => (
        <Space>
          <Switch
            checked={row.status === 'active'}
            checkedChildren="启用"
            unCheckedChildren="禁用"
            onChange={() => handleToggleStatus(row.id, row.status || 'active')}
          />
          <Popconfirm title="确认删除该用户？此操作不可恢复" onConfirm={() => handleDelete(row.id)}>
            <Button size="small" danger>删除</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }} wrap>
        <Input placeholder="搜索手机/昵称" prefix={<SearchOutlined />} value={keyword} onChange={(e) => { setKeyword(e.target.value); setPage(1); }} allowClear />
        <Select placeholder="会员类型" style={{ width: 120 }} value={memberType || undefined} onChange={(v) => { setMemberType(v || ''); setPage(1); }} allowClear
          options={[{ value: 'free', label: '普通' }, { value: 'pro', label: '专业版' }, { value: 'flagship', label: '旗舰版' }]}
        />
        <Button type="primary" icon={<PlusOutlined />} onClick={() => { form.resetFields(); setModalOpen(true); }}>添加用户</Button>
        {selectedRowKeys.length > 0 && (
          <>
            <span>已选 {selectedRowKeys.length} 项</span>
            <Button onClick={() => handleBatchStatus('disabled')}>批量禁用</Button>
            <Button onClick={() => handleBatchStatus('active')}>批量启用</Button>
            <Popconfirm title={`确认删除这 ${selectedRowKeys.length} 个用户？`} onConfirm={handleBatchDelete}>
              <Button danger>批量删除</Button>
            </Popconfirm>
          </>
        )}
      </Space>
      <Table rowKey="id" columns={columns} dataSource={data} loading={loading}
        rowSelection={{ selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) }}
        pagination={{ current: page, total, pageSize: 20, onChange: setPage }}
      />

      <Modal title="添加用户" open={modalOpen} onOk={handleCreate} onCancel={() => setModalOpen(false)}>
        <Form form={form} layout="vertical">
          <Form.Item name="phone" label="手机号" rules={[{ required: true, message: '请输入手机号' }]}>
            <Input maxLength={11} placeholder="请输入手机号" />
          </Form.Item>
          <Form.Item name="nickname" label="昵称">
            <Input placeholder="请输入昵称" />
          </Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: '请输入密码' }]}>
            <Input.Password placeholder="请输入密码" />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
