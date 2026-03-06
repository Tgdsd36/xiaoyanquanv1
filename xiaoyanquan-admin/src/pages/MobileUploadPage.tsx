import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Card, message, Select, Space, Tag, Upload } from 'antd';
import { ArrowLeftOutlined, UploadOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import type { UploadFile } from 'antd/es/upload/interface';
import http from '../api/http';
import './MobileUploadPage.css';

type UploadMode = 'normal' | 'live_image' | 'live_video';
type UploadStatus = 'uploading' | 'success' | 'error';

interface FolderInfo {
  folder: string;
  count: number;
}

interface UploadItem {
  uid: string;
  name: string;
  status: UploadStatus;
  tip: string;
}

const modeOptions: Array<{ value: UploadMode; label: string }> = [
  { value: 'normal', label: '上传图片/视频' },
  { value: 'live_image', label: '上传 Live 静态图(HEIC)' },
  { value: 'live_video', label: '上传 Live 动态视频(MOV)' },
];

export default function MobileUploadPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<UploadMode>('normal');
  const [folder, setFolder] = useState<string>('');
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [uploading, setUploading] = useState(false);
  const [records, setRecords] = useState<UploadItem[]>([]);

  const accept = useMemo(() => {
    if (mode === 'live_image') return 'image/*,.heic,.heif';
    if (mode === 'live_video') return 'video/*,.mov,.mp4';
    return 'image/*,video/*,.heic,.heif,.mov,.mp4,.m4v,.avi,.mkv,.webm';
  }, [mode]);

  const uploadTips = useMemo(() => {
    if (mode === 'live_image') return '当前模式：只上传 Live 静态图（HEIC/HEIF）';
    if (mode === 'live_video') return '当前模式：只上传 Live 动态视频（MOV/MP4）';
    return '当前模式：上传普通图片或视频素材';
  }, [mode]);

  const fetchFolders = useCallback(async () => {
    try {
      const { data: resp } = await http.get('/assets/folders');
      if (resp.code === 0) {
        setFolders(resp.data.folders || []);
      }
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    fetchFolders();
  }, [fetchFolders]);

  const setRecord = (next: UploadItem) => {
    setRecords((prev) => {
      const idx = prev.findIndex((item) => item.uid === next.uid);
      if (idx === -1) return [next, ...prev].slice(0, 20);
      const cloned = [...prev];
      cloned[idx] = next;
      return cloned;
    });
  };

  const uploadSingleFile = async (file: UploadFile) => {
    if (!file.originFileObj) return;
    setUploading(true);
    setRecord({
      uid: file.uid,
      name: file.name,
      status: 'uploading',
      tip: '上传中...',
    });

    const formData = new FormData();
    formData.append('file', file.originFileObj as File);
    if (folder) formData.append('folder', folder);
    if (mode === 'live_image') formData.append('live_role', 'image');
    if (mode === 'live_video') formData.append('live_role', 'video');

    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        setRecord({
          uid: file.uid,
          name: file.name,
          status: 'success',
          tip: '上传成功',
        });
        message.success(`${file.name} 上传成功`);
        fetchFolders();
      } else {
        setRecord({
          uid: file.uid,
          name: file.name,
          status: 'error',
          tip: resp.message || '上传失败',
        });
        message.error(resp.message || `${file.name} 上传失败`);
      }
    } catch (error: any) {
      const msg = error?.response?.data?.message || '上传失败';
      setRecord({
        uid: file.uid,
        name: file.name,
        status: 'error',
        tip: msg,
      });
      message.error(`${file.name} ${msg}`);
    } finally {
      setUploading(false);
    }
  };

  const folderOptions = useMemo(
    () => [
      { value: '', label: '未分类' },
      ...folders
        .filter((item) => item.folder)
        .map((item) => ({ value: item.folder, label: item.folder })),
    ],
    [folders],
  );

  return (
    <div className="mobile-upload-page">
      <div className="mobile-upload-header">
        <Button
          type="text"
          icon={<ArrowLeftOutlined />}
          onClick={() => navigate('/assets')}
        >
          返回后台
        </Button>
        <span className="mobile-upload-title">手机素材上传</span>
        <span className="mobile-upload-placeholder" />
      </div>

      <Card className="mobile-upload-card" bordered={false}>
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <div>
            <div className="mobile-upload-label">上传模式</div>
            <Select
              value={mode}
              onChange={(value) => setMode(value)}
              options={modeOptions}
              style={{ width: '100%' }}
            />
          </div>

          <div>
            <div className="mobile-upload-label">素材分类</div>
            <Select
              value={folder}
              onChange={(value) => setFolder(value)}
              options={folderOptions}
              style={{ width: '100%' }}
            />
          </div>

          <Tag color="blue" className="mobile-upload-tip">{uploadTips}</Tag>

          <Upload
            multiple
            accept={accept}
            showUploadList={false}
            beforeUpload={(file) => {
              void uploadSingleFile(file as unknown as UploadFile);
              return false;
            }}
          >
            <Button
              block
              type="primary"
              icon={<UploadOutlined />}
              loading={uploading}
              size="large"
            >
              选择文件并上传
            </Button>
          </Upload>

          <div className="mobile-upload-note">
            手机端建议：Live 图请分别上传 HEIC 与 MOV（同名文件会自动配对成套件）。
          </div>
        </Space>
      </Card>

      <Card className="mobile-upload-card" title="最近上传结果" bordered={false}>
        <div className="mobile-upload-records">
          {records.length === 0 ? (
            <div className="mobile-upload-empty">暂无上传记录</div>
          ) : (
            records.map((item) => (
              <div key={item.uid} className="mobile-upload-record">
                <div className="mobile-upload-record-name">{item.name}</div>
                <Tag
                  color={item.status === 'success' ? 'green' : item.status === 'error' ? 'red' : 'processing'}
                >
                  {item.tip}
                </Tag>
              </div>
            ))
          )}
        </div>
      </Card>
    </div>
  );
}

