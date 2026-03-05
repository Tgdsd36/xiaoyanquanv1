import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Button, Empty, Input, Modal, Pagination, Select, Spin, Tag, Upload, message } from 'antd';
import { DeleteOutlined, PlusOutlined, UploadOutlined } from '@ant-design/icons';
import http from '../api/http';
import { toAbsoluteUrl } from '../utils/url';

interface LivePack {
  id: number;
  folder: string;
  base_name: string;
  status: 'complete' | 'incomplete';
  missing: string[];
  image_asset_id?: number;
  image_url?: string;
  image_preview_url?: string;
  image_name?: string;
  video_asset_id?: number;
  video_url?: string;
  video_name?: string;
  created_at: string;
}

interface FolderInfo {
  folder: string;
  count: number;
}

interface LivePackPickerValue {
  packId: number;
  imageUrl: string;
  videoUrl: string;
  status: 'complete' | 'incomplete';
}

interface LivePackPickerProps {
  valueImageUrl?: string;
  valueVideoUrl?: string;
  onChange?: (value: LivePackPickerValue | null) => void;
}

const PAGE_SIZE = 20;

function deriveHEICPreviewUrl(url?: string) {
  const raw = (url || '').trim();
  if (!raw) return '';
  const queryIndex = raw.indexOf('?');
  const base = queryIndex >= 0 ? raw.slice(0, queryIndex) : raw;
  const query = queryIndex >= 0 ? raw.slice(queryIndex) : '';
  if (!/\.hei[cf]$/i.test(base)) return '';
  return base.replace(/\.hei[cf]$/i, '_preview.jpg') + query;
}

function buildImageCandidates(imageUrl?: string, imagePreviewUrl?: string): string[] {
  const list = [
    (imagePreviewUrl || '').trim(),
    deriveHEICPreviewUrl(imageUrl),
    (imageUrl || '').trim(),
  ];
  const dedup = new Set<string>();
  return list.filter((item) => {
    if (!item || dedup.has(item)) return false;
    dedup.add(item);
    return true;
  });
}

function ImageThumb({
  candidates,
  alt,
  emptyText,
  fallbackVideoUrl = '',
}: {
  candidates: string[];
  alt: string;
  emptyText: string;
  fallbackVideoUrl?: string;
}) {
  const [idx, setIdx] = useState(0);
  const [videoFailed, setVideoFailed] = useState(false);
  const key = candidates.join('|');

  useEffect(() => {
    setIdx(0);
    setVideoFailed(false);
  }, [key, fallbackVideoUrl]);

  const current = candidates[idx] || '';
  if (!current && fallbackVideoUrl && !videoFailed) {
    return (
      <video
        src={toAbsoluteUrl(fallbackVideoUrl)}
        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
        muted
        playsInline
        preload="metadata"
        onError={() => setVideoFailed(true)}
      />
    );
  }

  if (!current) {
    return (
      <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#999', fontSize: 12 }}>
        {emptyText}
      </div>
    );
  }

  return (
    <img
      src={toAbsoluteUrl(current)}
      alt={alt}
      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
      onError={() => setIdx((prev) => prev + 1)}
    />
  );
}

function VideoThumb({
  videoUrl,
  emptyText,
}: {
  videoUrl?: string;
  emptyText: string;
}) {
  const [videoError, setVideoError] = useState(false);
  const resolvedVideoUrl = (videoUrl || '').trim();

  useEffect(() => {
    setVideoError(false);
  }, [resolvedVideoUrl]);

  if (!resolvedVideoUrl || videoError) {
    return (
      <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#999', fontSize: 12 }}>
        {emptyText}
      </div>
    );
  }

  return (
    <video
      src={toAbsoluteUrl(resolvedVideoUrl)}
      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
      muted
      playsInline
      preload="metadata"
      onError={() => setVideoError(true)}
    />
  );
}

export default function LivePackPicker({
  valueImageUrl = '',
  valueVideoUrl = '',
  onChange,
}: LivePackPickerProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [packs, setPacks] = useState<LivePack[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [folder, setFolder] = useState<string>('');
  const [status, setStatus] = useState<string>('');
  const [keyword, setKeyword] = useState('');
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [selected, setSelected] = useState<LivePack | null>(null);

  const selectedImageCandidates = useMemo(
    () => buildImageCandidates(valueImageUrl, ''),
    [valueImageUrl],
  );

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

  const fetchPacks = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string | number> = {
        page,
        page_size: PAGE_SIZE,
      };
      if (folder) params.folder = folder;
      if (status) params.status = status;
      if (keyword.trim()) params.keyword = keyword.trim();

      const { data: resp } = await http.get('/assets/live-packs', { params });
      if (resp.code === 0) {
        const list: LivePack[] = resp.data.list || [];
        setPacks(list);
        setTotal(resp.data.total || 0);
      } else {
        setPacks([]);
        setTotal(0);
      }
    } catch {
      setPacks([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, folder, status, keyword]);

  useEffect(() => {
    if (!modalOpen) return;
    fetchFolders();
  }, [modalOpen, fetchFolders]);

  useEffect(() => {
    if (!modalOpen) return;
    fetchPacks();
  }, [modalOpen, fetchPacks]);

  useEffect(() => {
    if (!modalOpen) return;
    if (!valueImageUrl || !valueVideoUrl) return;
    const matched = packs.find(
      (pack) => pack.image_url === valueImageUrl && pack.video_url === valueVideoUrl,
    );
    if (matched) {
      setSelected(matched);
    }
  }, [modalOpen, packs, valueImageUrl, valueVideoUrl]);

  const handleUpload = async (file: File, liveRole: 'image' | 'video') => {
    const formData = new FormData();
    formData.append('file', file);
    if (folder) formData.append('folder', folder);
    formData.append('live_role', liveRole);

    setUploading(true);
    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        message.success(liveRole === 'image' ? 'Live 静态图上传成功' : 'Live 动态视频上传成功');
        await Promise.all([fetchPacks(), fetchFolders()]);
      } else {
        message.error(resp.message || '上传失败');
      }
    } catch {
      message.error('上传失败');
    } finally {
      setUploading(false);
    }
  };

  const handleConfirm = () => {
    if (!selected) {
      message.warning('请先选择 Live 套件');
      return;
    }
    if (selected.status !== 'complete' || !selected.image_url || !selected.video_url) {
      const missing = (selected.missing || []).join(' + ') || '静态图/MOV视频';
      message.warning(`该套件不完整，缺少：${missing}`);
      return;
    }
    onChange?.({
      packId: selected.id,
      imageUrl: selected.image_url,
      videoUrl: selected.video_url,
      status: selected.status,
    });
    setModalOpen(false);
  };

  const renderPackCard = (pack: LivePack) => {
    const imageCandidates = buildImageCandidates(pack.image_url, pack.image_preview_url);
    const selectedState = selected?.id === pack.id;
    const incomplete = pack.status !== 'complete';
    return (
      <div
        key={pack.id}
        onClick={() => setSelected(pack)}
        style={{
          border: selectedState ? '2px solid #1677ff' : '1px solid #e8e8e8',
          borderRadius: 8,
          overflow: 'hidden',
          cursor: 'pointer',
          opacity: incomplete ? 0.72 : 1,
          background: '#fff',
        }}
      >
        <div style={{ position: 'relative', height: 146, background: '#f5f7fa', display: 'grid', gridTemplateColumns: '1fr 1fr' }}>
          <div style={{ borderRight: '1px solid #f0f0f0', position: 'relative' }}>
            <ImageThumb
              candidates={imageCandidates}
              alt={`${pack.base_name}-image`}
              emptyText="无HEIC缩略图"
              fallbackVideoUrl={pack.video_url || ''}
            />
            <Tag style={{ position: 'absolute', left: 6, bottom: 6, marginRight: 0 }} color="blue">
              HEIC
            </Tag>
          </div>
          <div style={{ position: 'relative' }}>
            <VideoThumb
              videoUrl={pack.video_url}
              emptyText="无MOV缩略图"
            />
            <Tag style={{ position: 'absolute', left: 6, bottom: 6, marginRight: 0 }} color="purple">
              MOV
            </Tag>
          </div>
          <div style={{ position: 'absolute', top: 8, right: 8 }}>
            {incomplete ? <Tag color="warning">半成品</Tag> : <Tag color="success">完整</Tag>}
          </div>
        </div>
        <div style={{ padding: 10 }}>
          <div style={{ fontWeight: 600, marginBottom: 6, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={pack.base_name}>
            {pack.base_name}
          </div>
          <div style={{ color: '#666', fontSize: 12, marginBottom: 4 }}>
            分类：{pack.folder || '未分类'}
          </div>
          <div style={{ color: '#666', fontSize: 12, marginBottom: 4 }}>
            创建：{pack.created_at}
          </div>
          {incomplete && (
            <div style={{ color: '#fa8c16', fontSize: 12 }}>
              缺少：{(pack.missing || []).join(' + ') || '静态图/MOV视频'}
            </div>
          )}
        </div>
      </div>
    );
  };

  return (
    <>
      <div
        onClick={() => setModalOpen(true)}
        style={{
          width: 180,
          height: 110,
          border: '1px dashed #d9d9d9',
          borderRadius: 8,
          background: '#fafafa',
          position: 'relative',
          overflow: 'hidden',
          cursor: 'pointer',
        }}
      >
        {valueImageUrl || valueVideoUrl ? (
          <>
            <div style={{ width: '100%', height: '100%', display: 'grid', gridTemplateColumns: valueVideoUrl ? '1fr 1fr' : '1fr' }}>
              <ImageThumb
                candidates={selectedImageCandidates}
                alt="Live 静态图预览"
                emptyText="HEIC"
                fallbackVideoUrl={valueVideoUrl || ''}
              />
              {valueVideoUrl ? (
                <VideoThumb
                  videoUrl={valueVideoUrl}
                  emptyText="MOV"
                />
              ) : null}
            </div>
            <Tag color={valueImageUrl && valueVideoUrl ? 'success' : 'warning'} style={{ position: 'absolute', top: 8, left: 8 }}>
              {valueImageUrl && valueVideoUrl ? 'Live完整' : 'Live半成品'}
            </Tag>
            <div
              onClick={(e) => {
                e.stopPropagation();
                onChange?.(null);
              }}
              style={{
                position: 'absolute',
                right: 8,
                top: 8,
                width: 22,
                height: 22,
                borderRadius: '50%',
                background: 'rgba(0,0,0,0.5)',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <DeleteOutlined />
            </div>
          </>
        ) : (
          <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: '#999' }}>
            <PlusOutlined style={{ fontSize: 18 }} />
            <div style={{ marginTop: 6, fontSize: 12 }}>选择 Live 套件</div>
          </div>
        )}
      </div>

      <Modal
        title="素材库 - 选择 Live 套件"
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        width={1120}
        destroyOnClose
        styles={{ body: { height: 620, paddingTop: 12 } }}
        footer={[
          <Button key="cancel" onClick={() => setModalOpen(false)}>
            取消
          </Button>,
          <Button key="confirm" type="primary" onClick={handleConfirm}>
            确认选择
          </Button>,
        ]}
      >
        <div style={{ display: 'flex', gap: 8, marginBottom: 10, flexWrap: 'wrap' }}>
          <Upload
            showUploadList={false}
            accept="image/*,.heic,.heif"
            beforeUpload={(file) => {
              handleUpload(file, 'image');
              return false;
            }}
            disabled={uploading}
          >
            <Button icon={<UploadOutlined />} loading={uploading}>
              上传 Live 静态图
            </Button>
          </Upload>
          <Upload
            showUploadList={false}
            accept="video/*,.mov"
            beforeUpload={(file) => {
              handleUpload(file, 'video');
              return false;
            }}
            disabled={uploading}
          >
            <Button icon={<UploadOutlined />} loading={uploading}>
              上传 Live 动态视频（MOV）
            </Button>
          </Upload>
          <Select
            placeholder="分类"
            allowClear
            value={folder || undefined}
            style={{ width: 180 }}
            onChange={(v) => {
              setFolder(v || '');
              setPage(1);
            }}
            options={folders.map((f) => ({
              value: f.folder,
              label: f.folder || '未分类',
            }))}
          />
          <Select
            placeholder="状态"
            allowClear
            value={status || undefined}
            style={{ width: 140 }}
            onChange={(v) => {
              setStatus(v || '');
              setPage(1);
            }}
            options={[
              { value: 'complete', label: '仅完整' },
              { value: 'incomplete', label: '仅半成品' },
            ]}
          />
          <Input.Search
            placeholder="搜索 base_name"
            allowClear
            style={{ width: 240 }}
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            onSearch={() => setPage(1)}
          />
        </div>

        <Alert
          type="info"
          showIcon
          style={{ marginBottom: 10 }}
          message="同文件夹下同 base_name 支持多版本；半成品会灰态展示并提示缺少项。"
        />

        <Spin spinning={loading || uploading}>
          {packs.length === 0 ? (
            <Empty description="暂无 Live 套件" style={{ marginTop: 80 }} />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 10 }}>
              {packs.map(renderPackCard)}
            </div>
          )}
          {total > PAGE_SIZE && (
            <div style={{ textAlign: 'center', marginTop: 14 }}>
              <Pagination
                current={page}
                total={total}
                pageSize={PAGE_SIZE}
                onChange={(p) => setPage(p)}
                size="small"
              />
            </div>
          )}
        </Spin>
      </Modal>
    </>
  );
}
