import { useMemo, useState } from 'react';
import { Button, Card, Space, Tag, Typography, Upload, message } from 'antd';
import { ClearOutlined, SearchOutlined, UploadOutlined } from '@ant-design/icons';
import type { RcFile, UploadProps } from 'antd/es/upload';
import mobileHttp from '../../api/mobileHttp';
import './MobileLiveDebugPage.css';

interface InspectResult {
  filename: string;
  ext: string;
  size: number;
  base_name: string;
  client_content_type: string;
  sniff_content_type: string;
  ftyp_brand: string;
  guess_type: string;
  live_role_candidate: string;
  can_split_to_live: boolean;
  split_hint: string;
  suggestion: string;
  header_sample_hex: string;
}

interface DiagnosticItem {
  key: string;
  file: File;
  name: string;
  ext: string;
  size: number;
  localMime: string;
  baseName: string;
  status: 'pending' | 'checking' | 'done' | 'error';
  result?: InspectResult;
  errorMessage?: string;
}

const { Text } = Typography;

function getFileExt(name: string): string {
  const dotIdx = name.lastIndexOf('.');
  if (dotIdx === -1 || dotIdx === name.length - 1) return '';
  return name.slice(dotIdx + 1).toLowerCase();
}

function normalizeBaseName(name: string): string {
  const dotIdx = name.lastIndexOf('.');
  let normalized = dotIdx > 0 ? name.slice(0, dotIdx) : name;
  normalized = normalized
    .trim()
    .toLowerCase()
    .replace(/（/g, '(')
    .replace(/）/g, ')')
    .replace(/^img[_-]?e(\d+)$/i, 'img_$1')
    .replace(/\s*\(\d+\)$/g, '')
    .replace(/\s+(copy|副本)$/g, '')
    .replace(/\s+\d+$/g, '')
    .replace(/\s+/g, ' ');
  return normalized;
}

function formatSize(bytes: number): string {
  if (bytes <= 0) return '0B';
  if (bytes >= 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024 / 1024).toFixed(2)}GB`;
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${bytes}B`;
}

function roleFromItem(item: DiagnosticItem): '' | 'image' | 'video' {
  const role = item.result?.live_role_candidate;
  if (role === 'image' || role === 'video') return role;
  if (item.ext === 'heic' || item.ext === 'heif') return 'image';
  if (item.ext === 'mov') return 'video';
  return '';
}

export default function MobileLiveDebugPage() {
  const [items, setItems] = useState<DiagnosticItem[]>([]);
  const [running, setRunning] = useState(false);

  const beforePick: UploadProps['beforeUpload'] = (rawFile) => {
    if (running) {
      message.warning('诊断中，请稍后再添加文件');
      return Upload.LIST_IGNORE;
    }

    const file = rawFile as RcFile;
    const key = `${file.name}-${file.size}-${file.lastModified}`;

    setItems((prev) => {
      if (prev.some((item) => item.key === key)) {
        return prev;
      }
      return [
        ...prev,
        {
          key,
          file,
          name: file.name,
          ext: getFileExt(file.name),
          size: file.size,
          localMime: file.type || '',
          baseName: normalizeBaseName(file.name),
          status: 'pending',
        },
      ];
    });
    return false;
  };

  const diagnoseOne = async (item: DiagnosticItem): Promise<InspectResult> => {
    const formData = new FormData();
    formData.append('file', item.file);
    const { data: resp } = await mobileHttp.post('/assets/inspect', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    if (resp.code !== 0) {
      throw new Error(resp.message || '诊断失败');
    }
    return resp.data as InspectResult;
  };

  const runDiagnose = async () => {
    if (running) return;
    if (items.length === 0) {
      message.info('请先选择文件');
      return;
    }

    setRunning(true);
    const snapshot = [...items];

    for (let i = 0; i < snapshot.length; i += 1) {
      const current = snapshot[i];
      setItems((prev) => prev.map((it) => (it.key === current.key ? { ...it, status: 'checking', errorMessage: '' } : it)));
      try {
        const result = await diagnoseOne(current);
        setItems((prev) => prev.map((it) => (it.key === current.key ? { ...it, status: 'done', result } : it)));
      } catch (error) {
        const messageText = (error as { message?: string })?.message || '诊断失败';
        setItems((prev) => prev.map((it) => (it.key === current.key ? { ...it, status: 'error', errorMessage: messageText } : it)));
      }
    }

    setRunning(false);
    message.success('诊断完成');
  };

  const clearAll = () => {
    if (running) return;
    setItems([]);
  };

  const groupSummary = useMemo(() => {
    const grouped = new Map<string, { imageCount: number; videoCount: number; total: number }>();
    items.forEach((item) => {
      const key = item.baseName || item.name;
      const current = grouped.get(key) ?? { imageCount: 0, videoCount: 0, total: 0 };
      const role = roleFromItem(item);
      if (role === 'image') current.imageCount += 1;
      if (role === 'video') current.videoCount += 1;
      current.total += 1;
      grouped.set(key, current);
    });
    return Array.from(grouped.entries()).map(([name, stat]) => ({ name, ...stat }));
  }, [items]);

  const pendingCount = items.filter((item) => item.status === 'pending').length;
  const doneCount = items.filter((item) => item.status === 'done').length;
  const errorCount = items.filter((item) => item.status === 'error').length;

  return (
    <div className="mobile-live-debug-page">
      <Card className="mobile-upload-card" bordered={false}>
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <div className="mobile-section-head">
            <h3>Live 诊断工具</h3>
            <Tag color="blue">仅诊断不入库</Tag>
          </div>

          <Text className="mobile-upload-note">
            用手机选择文件后，这里会显示服务器实际收到的文件类型。若只收到静态图，服务端无法拆分出 MOV。
          </Text>

          <Upload
            multiple
            accept="image/*,video/*,.heic,.heif,.mov,.mp4,.m4v,.avi,.mkv,.webm"
            showUploadList={false}
            beforeUpload={beforePick}
            disabled={running}
          >
            <Button block type="primary" icon={<UploadOutlined />} size="large" disabled={running}>
              选择文件
            </Button>
          </Upload>

          <div className="mobile-live-debug-toolbar">
            <Button icon={<SearchOutlined />} type="primary" onClick={() => void runDiagnose()} disabled={running || items.length === 0}>
              开始诊断
            </Button>
            <Button icon={<ClearOutlined />} onClick={clearAll} disabled={running || items.length === 0}>
              清空
            </Button>
          </div>

          <div className="mobile-upload-metrics">
            <Tag color="default">文件 {items.length}</Tag>
            <Tag color="processing">待诊断 {pendingCount}</Tag>
            <Tag color="success">完成 {doneCount}</Tag>
            <Tag color="error">失败 {errorCount}</Tag>
          </div>
        </Space>
      </Card>

      <Card className="mobile-upload-card" title="配对预览" bordered={false}>
        {groupSummary.length === 0 ? (
          <div className="mobile-upload-empty">暂无文件</div>
        ) : (
          <div className="mobile-live-debug-group-list">
            {groupSummary.map((group) => {
              const complete = group.imageCount > 0 && group.videoCount > 0;
              return (
                <div key={group.name} className="mobile-live-debug-group-item">
                  <div className="mobile-live-debug-group-title">{group.name}</div>
                  <div className="mobile-live-debug-group-meta">
                    <Tag color={complete ? 'green' : 'gold'}>{complete ? '可组成 Live 套件' : '缺少配对文件'}</Tag>
                    <span>HEIC/HEIF: {group.imageCount}，MOV: {group.videoCount}，总文件: {group.total}</span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      <Card className="mobile-upload-card" title="文件诊断明细" bordered={false}>
        {items.length === 0 ? (
          <div className="mobile-upload-empty">请选择文件后开始诊断</div>
        ) : (
          <div className="mobile-live-debug-list">
            {items.map((item) => {
              const statusColor = item.status === 'done' ? 'green' : item.status === 'error' ? 'red' : item.status === 'checking' ? 'processing' : 'blue';
              const statusText = item.status === 'done' ? '完成' : item.status === 'error' ? '失败' : item.status === 'checking' ? '诊断中' : '待诊断';
              return (
                <div key={item.key} className="mobile-live-debug-item">
                  <div className="mobile-live-debug-item-head">
                    <div className="mobile-live-debug-item-name">{item.name}</div>
                    <Tag color={statusColor}>{statusText}</Tag>
                  </div>
                  <div className="mobile-live-debug-item-line">本地：.{item.ext || '-'} / {item.localMime || '-'} / {formatSize(item.size)}</div>
                  <div className="mobile-live-debug-item-line">归一化基名：{item.baseName || '-'}</div>
                  {item.result ? (
                    <>
                      <div className="mobile-live-debug-item-line">服务端识别：{item.result.guess_type || '-'}</div>
                      <div className="mobile-live-debug-item-line">候选角色：{item.result.live_role_candidate || '-'}</div>
                      <div className="mobile-live-debug-item-line">MIME：{item.result.client_content_type || '-'} / {item.result.sniff_content_type || '-'}</div>
                      <div className="mobile-live-debug-item-line">ftyp：{item.result.ftyp_brand || '-'}</div>
                      <div className="mobile-live-debug-item-line">建议：{item.result.suggestion || '-'}</div>
                    </>
                  ) : null}
                  {item.errorMessage ? <div className="mobile-live-debug-item-error">{item.errorMessage}</div> : null}
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
