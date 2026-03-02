import { useEffect, useState } from 'react';
import { Card, InputNumber, Button, Spin, message } from 'antd';
import { SaveOutlined } from '@ant-design/icons';
import http from '../api/http';

// 配置分组定义
const CONFIG_GROUPS = [
  {
    title: '📦 会员配置',
    items: [
      { key: 'pro_monthly_price', label: '专业版月费（元）' },
      { key: 'flagship_monthly_price', label: '旗舰版月费（元）' },
      { key: 'pro_monthly_download_limit', label: '专业版每月下载次数' },
      { key: 'flagship_monthly_download_limit', label: '旗舰版每月下载次数' },
    ],
  },
  {
    title: '📱 短信配置',
    items: [
      { key: 'sms_daily_limit', label: '每日单号码短信上限' },
      { key: 'sms_code_ttl_minutes', label: '验证码有效期（分钟）' },
    ],
  },
];

export default function ConfigPage() {
  const [configs, setConfigs] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState<string | null>(null);

  const fetchData = async () => {
    setLoading(true);
    const { data: resp } = await http.get('/configs');
    if (resp.code === 0) {
      const map: Record<string, string> = {};
      (resp.data || []).forEach((c: any) => { map[c.key] = c.value; });
      setConfigs(map);
    }
    setLoading(false);
  };

  useEffect(() => { fetchData(); }, []);

  const handleChange = (key: string, value: number | null) => {
    setConfigs((prev) => ({ ...prev, [key]: String(value ?? '') }));
  };

  const handleSaveGroup = async (groupTitle: string, keys: string[]) => {
    setSaving(groupTitle);
    try {
      for (const key of keys) {
        await http.put('/configs', { key, value: configs[key] || '' });
      }
      message.success(`${groupTitle} 保存成功`);
    } catch {
      message.error('保存失败');
    }
    setSaving(null);
  };

  return (
    <Spin spinning={loading}>
      <div style={{ maxWidth: 600, display: 'flex', flexDirection: 'column', gap: 20 }}>
        {CONFIG_GROUPS.map((group) => (
          <Card
            key={group.title}
            title={group.title}
            size="small"
            extra={
              <Button
                type="primary"
                size="small"
                icon={<SaveOutlined />}
                loading={saving === group.title}
                onClick={() => handleSaveGroup(group.title, group.items.map((i) => i.key))}
              >
                保存
              </Button>
            }
          >
            {group.items.map((item) => (
              <div key={item.key} style={{ display: 'flex', alignItems: 'center', marginBottom: 12 }}>
                <span style={{ width: 180, flexShrink: 0, color: '#333' }}>{item.label}</span>
                <InputNumber
                  style={{ width: 160 }}
                  value={configs[item.key] ? Number(configs[item.key]) : undefined}
                  onChange={(v) => handleChange(item.key, v)}
                  min={0}
                />
              </div>
            ))}
          </Card>
        ))}
      </div>
    </Spin>
  );
}
