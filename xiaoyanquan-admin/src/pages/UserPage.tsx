import { useEffect, useState, useCallback } from 'react';
import { Table, Input, Select, Space, Tag, Button, Modal, Form, Switch, Popconfirm, Tooltip, message } from 'antd';
import { SearchOutlined, PlusOutlined } from '@ant-design/icons';
import http from '../api/http';
import { formatDateTime } from '../utils/time';

const memberLabels: Record<string, { text: string; color: string }> = {
  free: { text: '普通', color: 'default' },
  pro: { text: '标准版', color: 'blue' },
  flagship: { text: '专业版', color: 'gold' },
};

export default function UserPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [keyword, setKeyword] = useState('');
  const [memberType, setMemberType] = useState('');
  const [deviceBound, setDeviceBound] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (memberType) params.member_type = memberType;
    if (deviceBound) params.device_bound = deviceBound;
    const { data: resp } = await http.get('/users', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, keyword, memberType, deviceBound]);

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

  const handleAdminUnbindDevice = async (id: number) => {
    await http.post(`/users/${id}/device/unbind`);
    message.success('设备解绑成功');
    fetchData();
  };

  const shortDeviceId = (id?: string) => {
    if (!id) return '';
    if (id.length <= 14) return id;
    return `${id.slice(0, 8)}...${id.slice(-6)}`;
  };

  const handleCopyDeviceId = async (deviceId?: string) => {
    if (!deviceId) return;
    try {
      await navigator.clipboard.writeText(deviceId);
      message.success('设备ID已复制');
    } catch {
      message.error('复制失败');
    }
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '手机号', dataIndex: 'phone', width: 130 },
    { title: '昵称', dataIndex: 'nickname' },
    {
      title: '绑定设备',
      dataIndex: 'device_name',
      width: 230,
      render: (_: string, row: any) => {
        if (!row.device_bound) return <Tag>未绑定</Tag>;
        return (
          <div>
            <div>{row.device_name || '当前设备'}</div>
            <div style={{ color: '#8c8c8c', fontSize: 12, display: 'flex', alignItems: 'center', gap: 6 }}>
              <span>{shortDeviceId(row.device_id)}</span>
              <Tooltip title="复制设备ID">
                <Button
                  type="link"
                  size="small"
                  style={{ padding: 0, height: 'auto' }}
                  onClick={() => handleCopyDeviceId(row.device_id)}
                >
                  复制
                </Button>
              </Tooltip>
            </div>
          </div>
        );
      },
    },
    {
      title: '设备平台',
      dataIndex: 'device_platform',
      width: 90,
      render: (v: string, row: any) => {
        if (!row.device_bound) return <span style={{ color: '#bfbfbf' }}>-</span>;
        return <Tag color="geekblue">{(v || 'unknown').toUpperCase()}</Tag>;
      },
    },
    {
      title: '绑定时间',
      dataIndex: 'device_bound_at',
      width: 170,
      render: (v: string, row: any) => (row.device_bound ? formatDateTime(v) : '-'),
    },
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
    {
      title: '注册时间',
      dataIndex: 'created_at',
      width: 170,
      render: (v: string) => formatDateTime(v),
    },
    {
      title: '操作', width: 260,
      render: (_: any, row: any) => (
        <Space>
          <Switch
            checked={row.status === 'active'}
            checkedChildren="启用"
            unCheckedChildren="禁用"
            onChange={() => handleToggleStatus(row.id, row.status || 'active')}
          />
          <Popconfirm
            title="确认解绑该用户设备？"
            onConfirm={() => handleAdminUnbindDevice(row.id)}
            disabled={!row.device_bound}
          >
            <Button size="small" disabled={!row.device_bound}>解绑设备</Button>
          </Popconfirm>
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
          options={[{ value: 'free', label: '普通' }, { value: 'pro', label: '标准版' }, { value: 'flagship', label: '专业版' }]}
        />
        <Select
          placeholder="设备绑定"
          style={{ width: 120 }}
          value={deviceBound || undefined}
          onChange={(v) => { setDeviceBound(v || ''); setPage(1); }}
          allowClear
          options={[{ value: '1', label: '已绑定' }, { value: '0', label: '未绑定' }]}
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
        expandable={{
          rowExpandable: (record: any) => !!record.device_bound,
          expandedRowRender: (record: any) => (
            <div style={{ lineHeight: 1.9 }}>
              <div><strong>完整设备ID：</strong>{record.device_id || '-'}</div>
              <div><strong>设备名称：</strong>{record.device_name || '-'}</div>
              <div><strong>设备平台：</strong>{record.device_platform || '-'}</div>
              <div><strong>绑定时间：</strong>{formatDateTime(record.device_bound_at)}</div>
            </div>
          ),
        }}
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
