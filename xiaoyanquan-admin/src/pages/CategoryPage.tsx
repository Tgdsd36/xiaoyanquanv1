import { useEffect, useState } from 'react';
import { Table, Button, Modal, Form, Input, InputNumber, Switch, Space, Select, Tag, message, Popconfirm } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import http from '../api/http';

interface CategoryItem {
  id: number;
  parent_id: number | null;
  name: string;
  slug: string;
  sort_order: number;
  is_visible: boolean;
  children?: CategoryItem[];
}

export default function CategoryPage() {
  const [data, setData] = useState<CategoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editItem, setEditItem] = useState<CategoryItem | null>(null);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();

  const fetchData = async () => {
    setLoading(true);
    const { data: resp } = await http.get('/categories');
    if (resp.code === 0) setData(resp.data || []);
    setLoading(false);
  };

  useEffect(() => { fetchData(); }, []);

  // 获取所有一级分类（用于下拉选择）
  const parentOptions = data.map(cat => ({ label: cat.name, value: cat.id }));

  const handleSave = async () => {
    const values = await form.validateFields();
    // parent_id 为 0 或 undefined 时设为 null
    if (!values.parent_id) values.parent_id = null;
    if (editItem) {
      await http.put(`/categories/${editItem.id}`, values);
      message.success('更新成功');
    } else {
      await http.post('/categories', values);
      message.success('创建成功');
    }
    setModalOpen(false);
    fetchData();
  };

  const handleDelete = async (id: number) => {
    try {
      const { data: resp } = await http.delete(`/categories/${id}`);
      if (resp.code === 0) {
        message.success('已删除');
        fetchData();
      } else {
        message.error(resp.message || '删除失败');
      }
    } catch {
      message.error('删除失败');
    }
  };

  const handleBatchDelete = async () => {
    if (!selectedRowKeys.length) return;
    try {
      const { data: resp } = await http.post('/categories/batch-delete', { ids: selectedRowKeys.map(Number) });
      if (resp.code === 0) {
        message.success('批量删除成功');
        setSelectedRowKeys([]);
        fetchData();
      } else {
        message.error(resp.message || '批量删除失败');
      }
    } catch {
      message.error('批量删除失败');
    }
  };

  // 快捷添加子分类
  const handleAddChild = (parentId: number) => {
    setEditItem(null);
    form.resetFields();
    form.setFieldsValue({ parent_id: parentId, is_visible: true, sort_order: 0 });
    setModalOpen(true);
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '名称', dataIndex: 'name' },
    { title: '层级', width: 80, render: (_: any, row: CategoryItem) => (
      row.parent_id ? <Tag color="blue">二级</Tag> : <Tag color="green">一级</Tag>
    )},
    { title: '排序', dataIndex: 'sort_order', width: 80 },
    { title: '可见', dataIndex: 'is_visible', width: 60, render: (v: boolean) => v ? '是' : '否' },
    {
      title: '操作', width: 240,
      render: (_: any, row: CategoryItem) => (
        <Space>
          {!row.parent_id && (
            <Button size="small" type="link" onClick={() => handleAddChild(row.id)}>+ 子分类</Button>
          )}
          <Button size="small" onClick={() => {
            setEditItem(row);
            form.setFieldsValue({ ...row, parent_id: row.parent_id || undefined });
            setModalOpen(true);
          }}>编辑</Button>
          <Popconfirm title="确认删除？" onConfirm={() => handleDelete(row.id)}>
            <Button size="small" danger>删除</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }} wrap>
        <Button type="primary" icon={<PlusOutlined />} onClick={() => {
          setEditItem(null);
          form.resetFields();
          form.setFieldsValue({ is_visible: true, sort_order: 0 });
          setModalOpen(true);
        }}>
          新增一级分类
        </Button>
        {selectedRowKeys.length > 0 && (
          <>
            <span>已选 {selectedRowKeys.length} 项</span>
            <Popconfirm title={`确认删除这 ${selectedRowKeys.length} 项分类？子分类也会被删除`} onConfirm={handleBatchDelete}>
              <Button danger>批量删除</Button>
            </Popconfirm>
          </>
        )}
      </Space>

      <Table
        rowKey="id"
        columns={columns}
        dataSource={data}
        loading={loading}
        pagination={false}
        rowSelection={{
          selectedRowKeys,
          onChange: (keys) => setSelectedRowKeys(keys),
        }}
        expandable={{
          childrenColumnName: 'children',
          defaultExpandAllRows: true,
        }}
      />

      <Modal
        title={editItem ? '编辑分类' : '新增分类'}
        open={modalOpen}
        onOk={handleSave}
        onCancel={() => setModalOpen(false)}
      >
        <Form form={form} layout="vertical" initialValues={{ is_visible: true, sort_order: 0 }}>
          <Form.Item name="parent_id" label="归属一级分类（留空则创建一级分类）">
            <Select
              allowClear
              placeholder="无（创建一级分类）"
              options={parentOptions}
            />
          </Form.Item>
          <Form.Item name="name" label="名称" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="sort_order" label="排序">
            <InputNumber min={0} />
          </Form.Item>
          <Form.Item name="is_visible" label="是否可见" valuePropName="checked">
            <Switch />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
