import { useCallback, useEffect, useState } from 'react';
import { Button, Card, Input, message, Modal, Select, Space, Tag } from 'antd';
import mobileHttp from '../../api/mobileHttp';
import { formatDateTime } from '../../utils/time';

export default function MobileQuestionsPage() {
  const [list, setList] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);

  const [replyOpen, setReplyOpen] = useState(false);
  const [current, setCurrent] = useState<any | null>(null);
  const [replyText, setReplyText] = useState('');

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (statusFilter) params.status = statusFilter;
    try {
      const { data: resp } = await mobileHttp.get('/questions', { params });
      if (resp.code === 0) {
        setList(resp.data.list || []);
        setHasMore(Boolean(resp.data.has_more));
      }
    } finally {
      setLoading(false);
    }
  }, [page, statusFilter]);

  useEffect(() => {
    void fetchData();
  }, [fetchData]);

  const submitReply = async () => {
    if (!current) return;
    if (!replyText.trim()) {
      message.warning('请输入回复内容');
      return;
    }
    await mobileHttp.put(`/questions/${current.id}/reply`, { reply_text: replyText.trim() });
    message.success('回复成功');
    setReplyOpen(false);
    setCurrent(null);
    setReplyText('');
    void fetchData();
  };

  return (
    <div>
      <Card size="small" style={{ marginBottom: 10 }}>
        <Select
          value={statusFilter || undefined}
          placeholder="按状态筛选"
          allowClear
          style={{ width: '100%' }}
          onChange={(v) => {
            setStatusFilter(v || '');
            setPage(1);
          }}
          options={[
            { value: 'pending', label: '待回复' },
            { value: 'replied', label: '已回复' },
          ]}
        />
      </Card>

      {list.map((item) => (
        <Card key={item.id} size="small" style={{ marginBottom: 10 }} loading={loading}>
          <div className="mobile-section-head">
            <h3>问题 #{item.id}</h3>
            <Tag color={item.status === 'replied' ? 'green' : 'orange'}>
              {item.status === 'replied' ? '已回复' : '待回复'}
            </Tag>
          </div>

          <div className="mobile-meta-row">用户：{item.user?.nickname || '-'}</div>
          <div className="mobile-meta-row">时间：{formatDateTime(item.created_at)}</div>
          <div className="mobile-question-block">{item.question_text || '-'}</div>
          {item.reply_text ? <div className="mobile-reply-block">已回复：{item.reply_text}</div> : null}

          <Button
            size="small"
            type="primary"
            style={{ marginTop: 8 }}
            onClick={() => {
              setCurrent(item);
              setReplyText(item.reply_text || '');
              setReplyOpen(true);
            }}
          >
            {item.status === 'replied' ? '修改回复' : '回复'}
          </Button>
        </Card>
      ))}

      <Card size="small">
        <Space style={{ width: '100%', justifyContent: 'space-between' }}>
          <Button disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>上一页</Button>
          <span style={{ color: '#7a8798', fontSize: 12 }}>第 {page} 页</span>
          <Button disabled={!hasMore} onClick={() => setPage((p) => p + 1)}>下一页</Button>
        </Space>
      </Card>

      <Modal
        title={current?.status === 'replied' ? '修改回复' : '回复提问'}
        open={replyOpen}
        onOk={() => void submitReply()}
        onCancel={() => setReplyOpen(false)}
        okText="提交"
        cancelText="取消"
      >
        <div style={{ marginBottom: 8, color: '#6e7c8b' }}>问题：{current?.question_text || '-'}</div>
        <Input.TextArea rows={5} value={replyText} onChange={(e) => setReplyText(e.target.value)} placeholder="输入回复内容" />
      </Modal>
    </div>
  );
}
