import { useEffect, useState, useCallback } from 'react';
import { Table, Button, Select, Space, Tag, Modal, Input, message } from 'antd';
import http from '../api/http';

export default function QuestionPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [replyModal, setReplyModal] = useState(false);
  const [currentQ, setCurrentQ] = useState<any>(null);
  const [replyText, setReplyText] = useState('');

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (statusFilter) params.status = statusFilter;
    const { data: resp } = await http.get('/questions', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, statusFilter]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleReply = async () => {
    if (!replyText.trim()) { message.warning('请输入回复内容'); return; }
    await http.put(`/questions/${currentQ.id}/reply`, { reply_text: replyText });
    message.success('回复成功');
    setReplyModal(false);
    setReplyText('');
    fetchData();
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '用户', dataIndex: ['user', 'nickname'], width: 100, render: (v: string) => v || '-' },
    { title: '类型', dataIndex: 'target_type', width: 80 },
    { title: '目标ID', dataIndex: 'target_id', width: 70 },
    { title: '提问内容', dataIndex: 'question_text', ellipsis: true },
    { title: '回复', dataIndex: 'reply_text', ellipsis: true },
    {
      title: '状态', dataIndex: 'status', width: 80,
      render: (s: string) => <Tag color={s === 'replied' ? 'green' : 'orange'}>{s === 'replied' ? '已回复' : '待回复'}</Tag>,
    },
    { title: '时间', dataIndex: 'created_at', width: 170 },
    {
      title: '操作', width: 80,
      render: (_: any, row: any) => (
        <Button size="small" type="primary" onClick={() => { setCurrentQ(row); setReplyText(row.reply_text || ''); setReplyModal(true); }}>
          {row.status === 'replied' ? '修改' : '回复'}
        </Button>
      ),
    },
  ];

  return (
    <>
      <Space style={{ marginBottom: 16 }}>
        <Select placeholder="状态" style={{ width: 120 }} value={statusFilter || undefined} onChange={(v) => { setStatusFilter(v || ''); setPage(1); }} allowClear
          options={[{ value: 'pending', label: '待回复' }, { value: 'replied', label: '已回复' }]}
        />
      </Space>
      <Table rowKey="id" columns={columns} dataSource={data} loading={loading}
        rowSelection={{ selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) }}
        pagination={{ current: page, total, pageSize: 20, onChange: setPage }} scroll={{ x: 1000 }}
      />

      <Modal title="回复提问" open={replyModal} onOk={handleReply} onCancel={() => setReplyModal(false)}>
        {currentQ && <div style={{ marginBottom: 12, color: '#666' }}>问题：{currentQ.question_text}</div>}
        <Input.TextArea rows={4} value={replyText} onChange={(e) => setReplyText(e.target.value)} placeholder="输入回复内容" />
      </Modal>
    </>
  );
}
