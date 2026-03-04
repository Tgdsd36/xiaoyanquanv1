import { useEffect, useState } from 'react';
import { Card, Col, Row, Statistic } from 'antd';
import {
  UserOutlined,
  PictureOutlined,
  ShoppingOutlined,
  CrownOutlined,
  QuestionCircleOutlined,
  UserAddOutlined,
  DownloadOutlined,
} from '@ant-design/icons';
import http from '../api/http';

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

  useEffect(() => {
    http.get('/dashboard').then(({ data }) => {
      if (data.code === 0) setStats(data.data);
    });
  }, []);

  if (!stats) return null;

  const cards = [
    { title: '总用户数', value: stats.user_count, icon: <UserOutlined />, color: '#1890ff' },
    { title: '素材总数', value: stats.material_count, icon: <PictureOutlined />, color: '#52c41a' },
    { title: '活跃会员', value: stats.member_count, icon: <CrownOutlined />, color: '#faad14' },
    { title: '已付订单', value: stats.order_count, icon: <ShoppingOutlined />, color: '#722ed1' },
    { title: '待回复提问', value: stats.question_count, icon: <QuestionCircleOutlined />, color: '#eb2f96' },
    { title: '今日新增用户', value: stats.today_new_users, icon: <UserAddOutlined />, color: '#1890ff' },
    { title: '今日下载次数', value: stats.today_downloads, icon: <DownloadOutlined />, color: '#52c41a' },
  ];

  return (
    <>
      <h2>数据看板</h2>
      <Row gutter={[16, 16]}>
        {cards.map((c) => (
          <Col xs={24} sm={12} lg={6} key={c.title}>
            <Card>
              <Statistic title={c.title} value={c.value} prefix={c.icon} valueStyle={{ color: c.color }} />
            </Card>
          </Col>
        ))}
      </Row>
    </>
  );
}
