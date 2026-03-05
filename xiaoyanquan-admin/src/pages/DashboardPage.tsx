import { useEffect, useMemo, useState } from 'react';
import { Card, Progress, Spin, Tag } from 'antd';
import {
  UserOutlined,
  PictureOutlined,
  ShoppingOutlined,
  CrownOutlined,
  QuestionCircleOutlined,
  UserAddOutlined,
  DownloadOutlined,
  RiseOutlined,
  WarningOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons';
import http from '../api/http';
import './DashboardPage.css';

interface Stats {
  user_count: number;
  material_count: number;
  order_count: number;
  member_count: number;
  question_count: number;
  today_new_users: number;
  today_downloads: number;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    http.get('/dashboard').then(({ data }) => {
      if (data.code === 0) setStats(data.data);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  const nowLabel = useMemo(
    () => new Date().toLocaleString('zh-CN', { hour12: false }),
    [],
  );

  if (loading) {
    return (
      <div className="dashboard-loading">
        <Spin size="large" />
      </div>
    );
  }

  if (!stats) return null;

  const formatNumber = (value: number) => new Intl.NumberFormat('zh-CN').format(value);

  const memberRate = stats.user_count > 0
    ? Math.min(100, (stats.member_count / stats.user_count) * 100)
    : 0;
  const qaPressure = stats.user_count > 0
    ? Math.min(100, (stats.question_count / stats.user_count) * 100)
    : 0;

  const kpiCards = [
    { title: '总用户数', value: stats.user_count, icon: <UserOutlined />, tone: 'blue', delta: `今日 +${formatNumber(stats.today_new_users)}` },
    { title: '素材总数', value: stats.material_count, icon: <PictureOutlined />, tone: 'cyan', delta: `今日下载 ${formatNumber(stats.today_downloads)}` },
    { title: '活跃会员', value: stats.member_count, icon: <CrownOutlined />, tone: 'amber', delta: `渗透率 ${memberRate.toFixed(1)}%` },
    { title: '已付订单', value: stats.order_count, icon: <ShoppingOutlined />, tone: 'violet', delta: '近30天持续增长' },
  ] as const;

  const supportCards = [
    { title: '待回复提问', value: stats.question_count, icon: <QuestionCircleOutlined />, tone: stats.question_count > 30 ? 'danger' : 'blue' },
    { title: '今日新增用户', value: stats.today_new_users, icon: <UserAddOutlined />, tone: 'cyan' },
    { title: '今日下载次数', value: stats.today_downloads, icon: <DownloadOutlined />, tone: 'amber' },
  ] as const;

  const riskLevel = stats.question_count > 50 ? 'high' : stats.question_count > 20 ? 'mid' : 'low';

  return (
    <div className="dashboard-page">
      <div className="dashboard-hero">
        <div>
          <h2>数据看板</h2>
          <p>实时掌握素材运营、用户增长与问答处理状态</p>
        </div>
        <div className="dashboard-hero__meta">
          <Tag color="blue" icon={<RiseOutlined />}>运营总览</Tag>
          <span>{nowLabel}</span>
        </div>
      </div>

      <div className="dashboard-kpis">
        {kpiCards.map((item) => (
          <Card key={item.title} className={`dashboard-kpi dashboard-kpi--${item.tone}`} bordered={false}>
            <div className="dashboard-kpi__head">
              <span>{item.title}</span>
              <i>{item.icon}</i>
            </div>
            <div className="dashboard-kpi__value">{formatNumber(item.value)}</div>
            <div className="dashboard-kpi__delta">{item.delta}</div>
          </Card>
        ))}
      </div>

      <div className="dashboard-grid">
        <Card className="dashboard-panel" title="运营健康度" bordered={false}>
          <div className="dashboard-progress">
            <div className="dashboard-progress__row">
              <span>会员渗透率</span>
              <strong>{memberRate.toFixed(1)}%</strong>
            </div>
            <Progress percent={Number(memberRate.toFixed(1))} strokeColor="#2563EB" showInfo={false} />
          </div>
          <div className="dashboard-progress">
            <div className="dashboard-progress__row">
              <span>提问压力指数</span>
              <strong>{qaPressure.toFixed(1)}%</strong>
            </div>
            <Progress
              percent={Number(qaPressure.toFixed(1))}
              strokeColor={riskLevel === 'high' ? '#ef4444' : riskLevel === 'mid' ? '#f59e0b' : '#22c55e'}
              showInfo={false}
            />
          </div>
        </Card>

        <Card className="dashboard-panel" title="风险与提醒" bordered={false}>
          <div className="dashboard-alerts">
            <div className={`dashboard-alert dashboard-alert--${riskLevel}`}>
              {riskLevel === 'high' ? <WarningOutlined /> : <CheckCircleOutlined />}
              <div>
                <h4>{riskLevel === 'high' ? '问答处理压力偏高' : '问答处理状态正常'}</h4>
                <p>当前待回复提问 {formatNumber(stats.question_count)} 条，建议优先处理高频问题。</p>
              </div>
            </div>
            <div className="dashboard-alert dashboard-alert--neutral">
              <RiseOutlined />
              <div>
                <h4>用户增长趋势</h4>
                <p>今日新增用户 {formatNumber(stats.today_new_users)}，可继续投放高转化素材专题。</p>
              </div>
            </div>
          </div>
        </Card>
      </div>

      <div className="dashboard-support">
        {supportCards.map((item) => (
          <Card key={item.title} className={`dashboard-support__card dashboard-support__card--${item.tone}`} bordered={false}>
            <div className="dashboard-support__icon">{item.icon}</div>
            <div>
              <small>{item.title}</small>
              <h3>{formatNumber(item.value)}</h3>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}
