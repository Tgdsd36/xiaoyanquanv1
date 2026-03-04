import { useEffect, useState, useCallback } from 'react';
import { Table, Button, Input, Select, Space, Tag, Modal, Form, message, Image, Popconfirm } from 'antd';
import { PlusOutlined, SearchOutlined } from '@ant-design/icons';
import http from '../api/http';
import AssetPicker, { MultiAssetPicker } from '../components/AssetPicker';

const API_BASE = 'http://localhost:8080';
const statusColors: Record<string, string> = { draft: 'default', published: 'green', offline: 'red' };
const statusLabels: Record<string, string> = { draft: '草稿', published: '已发布', offline: '已下线' };
const typeLabels: Record<string, string> = { image: '图片', video: '视频', live_photo: 'Live Photo' };

function toFullUrl(url?: string) {
  if (!url) return '';
  return url.startsWith('http') ? url : `${API_BASE}${url}`;
}

export default function MaterialPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [keyword, setKeyword] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editItem, setEditItem] = useState<any>(null);
  const [categories, setCategories] = useState<any[]>([]);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();

  useEffect(() => {
    http.get('/categories').then(({ data: resp }) => {
      if (resp.code === 0) setCategories(resp.data || []);
    });
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (statusFilter) params.status = statusFilter;
    const { data: resp } = await http.get('/materials', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, keyword, statusFilter]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSave = async () => {
    const values = await form.validateFields();
    if (editItem) {
      await http.put(`/materials/${editItem.id}`, values);
      message.success('更新成功');
    } else {
      await http.post('/materials', values);
      message.success('创建成功');
    }
    setModalOpen(false);
    form.resetFields();
    setEditItem(null);
    fetchData();
  };

  const handleDelete = async (id: number) => {
    await http.delete(`/materials/${id}`);
    message.success('已删除');
    fetchData();
  };

  const handleBatchStatus = async (status: string) => {
    if (!selectedRowKeys.length) { message.warning('请先选择素材'); return; }
    await http.post('/materials/batch-status', { ids: selectedRowKeys.map(Number), status });
    message.success('批量更新成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const handleBatchDelete = async () => {
    if (!selectedRowKeys.length) { message.warning('请先选择素材'); return; }
    await http.post('/materials/batch-delete', { ids: selectedRowKeys.map(Number) });
    message.success('批量删除成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    {
      title: '缩略图', dataIndex: 'thumbnail_url', width: 80,
      render: (url: string) => url ? <Image width={50} src={toFullUrl(url)} /> : '-',
    },
    { title: '标题', dataIndex: 'title', ellipsis: true },
    { title: '类型', dataIndex: 'type', width: 90, render: (t: string) => typeLabels[t] || t },
    { title: '分类', dataIndex: ['category', 'name'], width: 90 },
    { title: '性别', dataIndex: 'gender', width: 80, render: (v: string) => v === 'male' ? '男' : v === 'female' ? '女' : '不限' },
    {
      title: '状态', dataIndex: 'status', width: 80,
      render: (s: string) => <Tag color={statusColors[s]}>{statusLabels[s] || s}</Tag>,
    },
    { title: '下载', dataIndex: 'download_count', width: 60 },
    {
      title: '操作', width: 160,
      render: (_: any, row: any) => (
        <Space>
          <Button size="small" onClick={() => { setEditItem(row); form.setFieldsValue(row); setModalOpen(true); }}>编辑</Button>
          <Popconfirm title="确认删除？" onConfirm={() => handleDelete(row.id)}><Button size="small" danger>删除</Button></Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }} wrap>
        <Input placeholder="搜索标题" prefix={<SearchOutlined />} value={keyword} onChange={(e) => { setKeyword(e.target.value); setPage(1); }} allowClear />
        <Select placeholder="状态筛选" style={{ width: 120 }} value={statusFilter || undefined} onChange={(v) => { setStatusFilter(v || ''); setPage(1); }} allowClear
          options={[{ value: 'draft', label: '草稿' }, { value: 'published', label: '已发布' }, { value: 'offline', label: '已下线' }]}
        />
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={() => {
            setEditItem(null);
            form.resetFields();
            form.setFieldsValue({ status: 'published', gender: '' });
            setModalOpen(true);
          }}
        >
          新增素材
        </Button>
        {selectedRowKeys.length > 0 && (
          <>
            <span>已选 {selectedRowKeys.length} 项</span>
            <Button onClick={() => handleBatchStatus('published')}>批量发布</Button>
            <Button onClick={() => handleBatchStatus('offline')}>批量下线</Button>
            <Popconfirm title={`确认删除这 ${selectedRowKeys.length} 项？`} onConfirm={handleBatchDelete}>
              <Button danger>批量删除</Button>
            </Popconfirm>
          </>
        )}
      </Space>

      <Table rowKey="id" columns={columns} dataSource={data} loading={loading}
        rowSelection={{ selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) }}
        pagination={{ current: page, total, pageSize: 20, onChange: setPage }} scroll={{ x: 900 }}
      />

      <Modal title={editItem ? '编辑素材' : '新增素材'} open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)} width={640}>
        <Form form={form} layout="vertical" initialValues={{ status: 'published', gender: '' }}>
          <Form.Item name="title" label="标题" rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="description" label="描述"><Input.TextArea rows={2} /></Form.Item>
          <Space>
            <Form.Item name="type" label="类型" rules={[{ required: true }]}>
              <Select style={{ width: 120 }} options={[{ value: 'image', label: '图片' }, { value: 'video', label: '视频' }, { value: 'live_photo', label: 'Live Photo' }]} />
            </Form.Item>
            <Form.Item name="category_id" label="分类" rules={[{ required: true, message: '请选择分类' }]}>
              <Select style={{ width: 160 }} placeholder="选择分类" allowClear
                options={categories
                  .filter((c: any) => c.slug !== 'male' && c.slug !== 'female')
                  .map((c: any) => ({ value: c.id, label: c.name }))}
              />
            </Form.Item>
            <Form.Item name="gender" label="性别">
              <Select style={{ width: 120 }}
                options={[
                  { value: '', label: '不限' },
                  { value: 'male', label: '男' },
                  { value: 'female', label: '女' },
                ]}
              />
            </Form.Item>
            <Form.Item name="status" label="状态" rules={[{ required: true, message: '请选择状态' }]}>
              <Select style={{ width: 120 }} options={[{ value: 'draft', label: '草稿' }, { value: 'published', label: '已发布' }, { value: 'offline', label: '已下线' }]} />
            </Form.Item>
          </Space>
          <Form.Item name="thumbnail_url" label="缩略图">
            <AssetPicker />
          </Form.Item>
          <Form.Item name="original_urls" label="原图（最多9张）">
            <MultiAssetPicker max={9} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
