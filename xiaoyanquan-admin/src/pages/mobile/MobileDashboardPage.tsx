import { useEffect, useState } from 'react';
import { Card, Spin, Tag } from 'antd';
import mobileHttp from '../../api/mobileHttp';

interface Stats {
  user_count: number;
  material_count: number;
  order_count: number;
  member_count: number;
  question_count: number;
  today_new_users: number;
  today_downloads: number;
}

function metric(title: string, value: number, suffix = '') {
  return (
    <div className="mobile-metric-item">
      <span>{title}</span>
      <strong>{value}{suffix}</strong>
    </div>
  );
}

export default function MobileDashboardPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    mobileHttp.get('/dashboard').then(({ data }) => {
      if (data.code === 0) setStats(data.data);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div style={{ paddingTop: 60, textAlign: 'center' }}>
        <Spin />
      </div>
    );
  }

  if (!stats) return null;

  return (
    <div>
      <Card size="small" style={{ marginBottom: 10 }}>
        <div className="mobile-section-head">
          <h3>核心指标</h3>
          <Tag color="blue">实时</Tag>
        </div>
        <div className="mobile-metric-grid">
          {metric('总用户', stats.user_count)}
          {metric('素材总数', stats.material_count)}
          {metric('已付订单', stats.order_count)}
          {metric('活跃会员', stats.member_count)}
        </div>
      </Card>

      <Card size="small" style={{ marginBottom: 10 }}>
        <div className="mobile-section-head">
          <h3>今日运营</h3>
          <Tag color={stats.question_count > 30 ? 'red' : 'green'}>
            {stats.question_count > 30 ? '待处理偏高' : '正常'}
          </Tag>
        </div>
        <div className="mobile-metric-grid">
          {metric('今日新增', stats.today_new_users)}
          {metric('今日下载', stats.today_downloads)}
          {metric('待回复提问', stats.question_count)}
          {metric('会员占比', stats.user_count > 0 ? Number(((stats.member_count / stats.user_count) * 100).toFixed(1)) : 0, '%')}
        </div>
      </Card>
    </div>
  );
}
