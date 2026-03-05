import { useEffect, useState, useCallback } from 'react';
import { Table, Select, Space, Tag } from 'antd';
import http from '../api/http';
import { formatDateTime } from '../utils/time';

const statusLabels: Record<string, { text: string; color: string }> = {
  pending: { text: '待支付', color: 'default' },
  paid: { text: '已支付', color: 'green' },
  failed: { text: '失败', color: 'red' },
  refunded: { text: '已退款', color: 'orange' },
};

const planLabels: Record<string, string> = {
  pro_monthly: '标准版月卡',
  flagship_monthly: '专业版月卡',
};

export default function OrderPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (statusFilter) params.status = statusFilter;
    const { data: resp } = await http.get('/orders', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, statusFilter]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '用户ID', dataIndex: 'user_id', width: 80 },
    { title: '套餐', dataIndex: 'plan_type', width: 120, render: (t: string) => planLabels[t] || t },
    { title: '金额', dataIndex: 'amount', width: 80, render: (v: number) => `¥${v}` },
    { title: '支付渠道', dataIndex: 'payment_channel', width: 100 },
    { title: '交易号', dataIndex: 'transaction_id', ellipsis: true },
    {
      title: '状态', dataIndex: 'status', width: 90,
      render: (s: string) => { const m = statusLabels[s] || statusLabels.pending; return <Tag color={m.color}>{m.text}</Tag>; },
    },
    { title: '创建时间', dataIndex: 'created_at', width: 170, render: (v: string) => formatDateTime(v) },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }}>
        <Select placeholder="状态" style={{ width: 120 }} value={statusFilter || undefined} onChange={(v) => { setStatusFilter(v || ''); setPage(1); }} allowClear
          options={[{ value: 'pending', label: '待支付' }, { value: 'paid', label: '已支付' }, { value: 'failed', label: '失败' }, { value: 'refunded', label: '已退款' }]}
        />
      </Space>
      <Table rowKey="id" columns={columns} dataSource={data} loading={loading} pagination={{ current: page, total, pageSize: 20, onChange: setPage }} />
    </>
  );
}
