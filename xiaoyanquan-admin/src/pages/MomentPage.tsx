import { useEffect, useState, useCallback } from 'react';
import { Table, Button, Modal, Form, Input, Select, Space, Tag, message, Popconfirm } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import http from '../api/http';
import { MultiAssetPicker } from '../components/AssetPicker';

const statusColors: Record<string, string> = { draft: 'default', published: 'green' };

export default function MomentPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editItem, setEditItem] = useState<any>(null);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: resp } = await http.get('/moments', { params: { page, page_size: 20 } });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSave = async () => {
    const values = await form.validateFields();
    // media_urls 已经是数组（来自 MultiAssetPicker）
    if (editItem) {
      await http.put(`/moments/${editItem.id}`, values);
      message.success('更新成功');
    } else {
      await http.post('/moments', values);
      message.success('创建成功');
    }
    setModalOpen(false);
    fetchData();
  };

  const handleDelete = async (id: number) => {
    await http.delete(`/moments/${id}`);
    message.success('已删除');
    fetchData();
  };

  const handleBatchDelete = async () => {
    if (!selectedRowKeys.length) return;
    await http.post('/moments/batch-delete', { ids: selectedRowKeys.map(Number) });
    message.success('批量删除成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const handleBatchStatus = async (status: string) => {
    if (!selectedRowKeys.length) return;
    await http.post('/moments/batch-status', { ids: selectedRowKeys.map(Number), status });
    message.success('批量更新成功');
    setSelectedRowKeys([]);
    fetchData();
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '内容', dataIndex: 'content_text', ellipsis: true },
    { title: '媒体类型', dataIndex: 'media_type', width: 90 },
    { title: '提问数', dataIndex: 'question_count', width: 80 },
    { title: '状态', dataIndex: 'status', width: 80, render: (s: string) => <Tag color={statusColors[s]}>{s}</Tag> },
    { title: '创建时间', dataIndex: 'created_at', width: 170 },
    {
      title: '操作', width: 160,
      render: (_: any, row: any) => (
        <Space>
          <Button size="small" onClick={() => {
            setEditItem(row);
            form.setFieldsValue({ ...row, media_urls: row.media_urls || [] });
            setModalOpen(true);
          }}>编辑</Button>
          <Popconfirm title="确认删除？" onConfirm={() => handleDelete(row.id)}><Button size="small" danger>删除</Button></Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }} wrap>
        <Button type="primary" icon={<PlusOutlined />} onClick={() => { setEditItem(null); form.resetFields(); setModalOpen(true); }}>发布动态</Button>
        {selectedRowKeys.length > 0 && (
          <>
            <span>已选 {selectedRowKeys.length} 项</span>
            <Button onClick={() => handleBatchStatus('published')}>批量发布</Button>
            <Popconfirm title={`确认删除这 ${selectedRowKeys.length} 项？`} onConfirm={handleBatchDelete}>
              <Button danger>批量删除</Button>
            </Popconfirm>
          </>
        )}
      </Space>
      <Table rowKey="id" columns={columns} dataSource={data} loading={loading}
        rowSelection={{ selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) }}
        pagination={{ current: page, total, pageSize: 20, onChange: setPage }}
      />

      <Modal title={editItem ? '编辑动态' : '发布动态'} open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)} width={600}>
        <Form form={form} layout="vertical">
          <Form.Item name="content_text" label="内容"><Input.TextArea rows={4} /></Form.Item>
          <Space>
            <Form.Item name="media_type" label="媒体类型">
              <Select style={{ width: 120 }} options={[{ value: 'image', label: '图片' }, { value: 'video', label: '视频' }]} />
            </Form.Item>
            <Form.Item name="status" label="状态">
              <Select style={{ width: 120 }} options={[{ value: 'draft', label: '草稿' }, { value: 'published', label: '发布' }]} />
            </Form.Item>
          </Space>
          <Form.Item name="media_urls" label="媒体图片">
            <MultiAssetPicker max={9} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
