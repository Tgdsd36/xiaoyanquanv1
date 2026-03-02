import { useState, useEffect, useCallback } from 'react';
import { Modal, Upload, Button, Spin, Empty, Pagination, message } from 'antd';
import { PlusOutlined, DeleteOutlined, UploadOutlined, FolderOutlined, FolderOpenOutlined } from '@ant-design/icons';
import http from '../api/http';

const API_BASE = 'http://localhost:8080';

interface Asset {
  id: number;
  url: string;
  original_name: string;
  file_type: string;
  file_size: number;
  folder: string;
  created_at: string;
}

interface FolderInfo {
  folder: string;
  count: number;
}

/** 共用分类侧栏 + 图片网格弹窗内容 */
function PickerModalContent({
  folder, setFolder, assets, total, page, setPage, loading, onSelect, onUpload,
  selectedCheck,
}: {
  folder: string | null;
  setFolder: (f: string | null) => void;
  assets: Asset[];
  total: number;
  page: number;
  setPage: (p: number) => void;
  loading: boolean;
  onSelect: (a: Asset) => void;
  onUpload: (file: File) => void;
  selectedCheck: (url: string) => boolean;
}) {
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [allTotal, setAllTotal] = useState(0);

  useEffect(() => {
    http.get('/assets/folders').then(({ data: resp }) => {
      if (resp.code === 0) {
        setFolders(resp.data.folders || []);
        setAllTotal(resp.data.total);
      }
    }).catch(() => {});
  }, []);

  return (
    <div style={{ display: 'flex', gap: 12 }}>
      {/* 左侧分类 */}
      <div style={{
        width: 140, minWidth: 140, background: '#fafafa', borderRadius: 6,
        border: '1px solid #f0f0f0', padding: '8px 0', overflowY: 'auto', maxHeight: 420,
      }}>
        <div
          onClick={() => { setFolder(null); setPage(1); }}
          style={{
            padding: '6px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 13,
            background: folder === null ? '#e6f4ff' : 'transparent',
            color: folder === null ? '#1677ff' : '#333',
          }}
        >
          <FolderOpenOutlined /> <span style={{ flex: 1 }}>全部</span>
          <span style={{ fontSize: 11, color: '#999' }}>{allTotal}</span>
        </div>
        {folders.map((f) => (
          <div
            key={f.folder || '__none'}
            onClick={() => { setFolder(f.folder); setPage(1); }}
            style={{
              padding: '6px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 13,
              background: folder === f.folder ? '#e6f4ff' : 'transparent',
              color: folder === f.folder ? '#1677ff' : '#333',
            }}
          >
            <FolderOutlined />
            <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {f.folder || '未分类'}
            </span>
            <span style={{ fontSize: 11, color: '#999' }}>{f.count}</span>
          </div>
        ))}
      </div>

      {/* 右侧内容 */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ marginBottom: 12 }}>
          <Upload
            showUploadList={false}
            accept="image/*"
            beforeUpload={(file) => { onUpload(file); return false; }}
          >
            <Button icon={<UploadOutlined />} type="primary" size="small">上传图片</Button>
          </Upload>
        </div>

        <Spin spinning={loading}>
          {assets.length === 0 ? (
            <Empty description="暂无图片" />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 8 }}>
              {assets.map((asset) => (
                <div
                  key={asset.id}
                  onClick={() => onSelect(asset)}
                  style={{
                    aspectRatio: '1',
                    border: selectedCheck(asset.url) ? '2px solid #1677ff' : '1px solid #e8e8e8',
                    borderRadius: 6, overflow: 'hidden', cursor: 'pointer', position: 'relative',
                  }}
                >
                  <img src={`${API_BASE}${asset.url}`} alt={asset.original_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  {selectedCheck(asset.url) && (
                    <div style={{
                      position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                      background: 'rgba(22,119,255,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                      color: '#1677ff', fontWeight: 'bold', fontSize: 20,
                    }}>✓</div>
                  )}
                </div>
              ))}
            </div>
          )}
          {total > 20 && (
            <div style={{ textAlign: 'center', marginTop: 12 }}>
              <Pagination current={page} total={total} pageSize={20} onChange={setPage} size="small" />
            </div>
          )}
        </Spin>
      </div>
    </div>
  );
}

interface AssetPickerProps {
  value?: string;
  onChange?: (url: string) => void;
}

/**
 * 单图选择器：点击显示缩略图/占位框，弹出素材库 Modal 选择或上传
 */
export default function AssetPicker({ value, onChange }: AssetPickerProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [folder, setFolder] = useState<string | null>(null);

  const fetchAssets = useCallback(async () => {
    setLoading(true);
    try {
      const params: any = { page, page_size: 20, file_type: 'image' };
      if (folder !== null) params.folder = folder;
      const { data: resp } = await http.get('/assets', { params });
      if (resp.code === 0) {
        setAssets(resp.data.list || []);
        setTotal(resp.data.total);
      }
    } catch { /* ignore */ }
    setLoading(false);
  }, [page, folder]);

  useEffect(() => {
    if (modalOpen) fetchAssets();
  }, [modalOpen, fetchAssets]);

  const handleSelect = (asset: Asset) => {
    onChange?.(asset.url);
    setModalOpen(false);
  };

  const handleUpload = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    if (folder) formData.append('folder', folder);
    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        message.success('上传成功');
        onChange?.(resp.data.url);
        setModalOpen(false);
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleRemove = (e: React.MouseEvent) => {
    e.stopPropagation();
    onChange?.('');
  };

  const fullUrl = value ? (value.startsWith('http') ? value : `${API_BASE}${value}`) : '';

  return (
    <>
      <div
        onClick={() => setModalOpen(true)}
        style={{
          width: 104, height: 104, border: '1px dashed #d9d9d9', borderRadius: 8,
          cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative', overflow: 'hidden', background: '#fafafa',
        }}
      >
        {fullUrl ? (
          <>
            <img src={fullUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            <div
              onClick={handleRemove}
              style={{
                position: 'absolute', top: 2, right: 2,
                background: 'rgba(0,0,0,0.5)', borderRadius: '50%',
                width: 22, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
            >
              <DeleteOutlined style={{ color: '#fff', fontSize: 12 }} />
            </div>
          </>
        ) : (
          <div style={{ textAlign: 'center', color: '#999' }}>
            <PlusOutlined style={{ fontSize: 20 }} />
            <div style={{ fontSize: 12, marginTop: 4 }}>选择图片</div>
          </div>
        )}
      </div>

      <Modal
        title="素材库 - 选择图片"
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        footer={null}
        width={900}
        destroyOnClose
      >
        <PickerModalContent
          folder={folder} setFolder={setFolder}
          assets={assets} total={total} page={page} setPage={setPage}
          loading={loading} onSelect={handleSelect} onUpload={handleUpload}
          selectedCheck={(url) => url === value}
        />
      </Modal>
    </>
  );
}

/**
 * 多图选择器：支持选择多张图片，返回 URL 数组
 */
interface MultiAssetPickerProps {
  value?: string[];
  onChange?: (urls: string[]) => void;
  max?: number;
}

export function MultiAssetPicker({ value = [], onChange, max = 9 }: MultiAssetPickerProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [folder, setFolder] = useState<string | null>(null);

  const fetchAssets = useCallback(async () => {
    setLoading(true);
    try {
      const params: any = { page, page_size: 20, file_type: 'image' };
      if (folder !== null) params.folder = folder;
      const { data: resp } = await http.get('/assets', { params });
      if (resp.code === 0) {
        setAssets(resp.data.list || []);
        setTotal(resp.data.total);
      }
    } catch { /* ignore */ }
    setLoading(false);
  }, [page, folder]);

  useEffect(() => {
    if (modalOpen) fetchAssets();
  }, [modalOpen, fetchAssets]);

  const handleSelect = (asset: Asset) => {
    if (value.includes(asset.url)) {
      onChange?.(value.filter((u) => u !== asset.url));
    } else if (value.length < max) {
      onChange?.([...value, asset.url]);
    } else {
      message.warning(`最多选择 ${max} 张`);
    }
  };

  const handleUpload = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    if (folder) formData.append('folder', folder);
    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        message.success('上传成功');
        if (value.length < max) {
          onChange?.([...value, resp.data.url]);
        }
        fetchAssets();
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleRemove = (url: string, e: React.MouseEvent) => {
    e.stopPropagation();
    onChange?.(value.filter((u) => u !== url));
  };

  return (
    <>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {value.map((url) => {
          const fullUrl = url.startsWith('http') ? url : `${API_BASE}${url}`;
          return (
            <div
              key={url}
              style={{ width: 80, height: 80, border: '1px solid #e8e8e8', borderRadius: 6, overflow: 'hidden', position: 'relative' }}
            >
              <img src={fullUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              <div
                onClick={(e) => handleRemove(url, e)}
                style={{
                  position: 'absolute', top: 2, right: 2,
                  background: 'rgba(0,0,0,0.5)', borderRadius: '50%',
                  width: 20, height: 20, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  cursor: 'pointer',
                }}
              >
                <DeleteOutlined style={{ color: '#fff', fontSize: 10 }} />
              </div>
            </div>
          );
        })}
        {value.length < max && (
          <div
            onClick={() => setModalOpen(true)}
            style={{
              width: 80, height: 80, border: '1px dashed #d9d9d9', borderRadius: 6,
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: '#fafafa',
            }}
          >
            <PlusOutlined style={{ fontSize: 18, color: '#999' }} />
          </div>
        )}
      </div>

      <Modal
        title="素材库 - 选择图片"
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        footer={null}
        width={900}
        destroyOnClose
      >
        <PickerModalContent
          folder={folder} setFolder={setFolder}
          assets={assets} total={total} page={page} setPage={setPage}
          loading={loading} onSelect={handleSelect} onUpload={handleUpload}
          selectedCheck={(url) => value.includes(url)}
        />
      </Modal>
    </>
  );
}
