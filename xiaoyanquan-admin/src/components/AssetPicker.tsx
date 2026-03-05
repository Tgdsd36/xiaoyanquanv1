import { useState, useEffect, useCallback } from 'react';
import { Modal, Upload, Button, Spin, Empty, Pagination, message, Alert, Input } from 'antd';
import {
  PlusOutlined,
  DeleteOutlined,
  UploadOutlined,
  FolderOutlined,
  FolderOpenOutlined,
  PictureOutlined,
  VideoCameraOutlined,
} from '@ant-design/icons';
import http from '../api/http';
import { toAbsoluteUrl } from '../utils/url';
const PICKER_PAGE_SIZE = 20;
const PICKER_FETCH_LIMIT = 1000;

interface Asset {
  id: number;
  url: string;
  preview_url?: string;
  original_name: string;
  file_type: string;
  file_size: number;
  folder: string;
  created_at: string;
}

type AssetFileType = 'image' | 'video' | 'all';
type AssetMediaType = 'image' | 'video';

interface FolderInfo {
  folder: string;
  count: number;
}

const videoExts = ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi'];

function toFullUrl(url: string) {
  return toAbsoluteUrl(url);
}

function getFileExt(url: string) {
  const parsedPath = (() => {
    try {
      return new URL(toFullUrl(url)).pathname;
    } catch {
      return url;
    }
  })();
  const dotIndex = parsedPath.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === parsedPath.length - 1) return '';
  return parsedPath.slice(dotIndex).toLowerCase();
}

function deriveHEICPreviewUrl(url: string) {
  const trimmed = url.trim();
  if (!trimmed) return '';
  const queryIndex = trimmed.indexOf('?');
  const base = queryIndex >= 0 ? trimmed.slice(0, queryIndex) : trimmed;
  const query = queryIndex >= 0 ? trimmed.slice(queryIndex) : '';
  if (!/\.hei[cf]$/i.test(base)) return '';
  return base.replace(/\.hei[cf]$/i, '_preview.jpg') + query;
}

function inferMediaType(url: string, fileType?: string): AssetMediaType {
  if (fileType?.toLowerCase() === 'video') return 'video';
  if (fileType?.toLowerCase() === 'image') return 'image';
  const ext = getFileExt(url);
  return videoExts.includes(ext) ? 'video' : 'image';
}

function isAssetMatchType(asset: Asset, fileType: AssetFileType) {
  if (fileType === 'all') return true;
  return inferMediaType(asset.url, asset.file_type) === fileType;
}

function getMediaLabel(fileType: AssetFileType) {
  if (fileType === 'video') return '视频';
  if (fileType === 'image') return '图片';
  return '素材';
}

function getAcceptType(fileType: AssetFileType) {
  if (fileType === 'video') return 'video/*,.mov,.mp4,.m4v,.avi,.mkv,.webm';
  if (fileType === 'image') return 'image/*,.heic,.heif,.jpg,.jpeg,.png,.gif,.webp,.bmp';
  return 'image/*,video/*,.heic,.heif,.mov,.mp4,.m4v,.avi,.mkv,.webm';
}

function isAssetMatchKeyword(asset: Asset, keyword: string) {
  const kw = keyword.trim().toLowerCase();
  if (!kw) return true;
  const name = (asset.original_name || '').toLowerCase();
  const url = (asset.url || '').toLowerCase();
  return name.includes(kw) || url.includes(kw);
}

function AssetPreview({
  url,
  previewUrl,
  originalName,
  fileType,
}: {
  url: string;
  previewUrl?: string;
  originalName?: string;
  fileType?: string;
}) {
  const [loadFailed, setLoadFailed] = useState(false);
  const mediaType = inferMediaType(url, fileType);
  const ext = getFileExt(url);
  const heicPreview = deriveHEICPreviewUrl(url);
  const fullUrl = toFullUrl(previewUrl || heicPreview || url);

  if (!loadFailed) {
    if (mediaType === 'video') {
      return (
        <video
          src={fullUrl}
          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
          muted
          playsInline
          preload="metadata"
          onError={() => setLoadFailed(true)}
        />
      );
    }
    return (
      <img
        src={fullUrl}
        alt={originalName || ''}
        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
        onError={() => setLoadFailed(true)}
      />
    );
  }

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#f5f7fa',
        color: '#7f8ea3',
        padding: 8,
        textAlign: 'center',
      }}
      title={originalName || '预览失败'}
    >
      {mediaType === 'video' ? (
        <VideoCameraOutlined style={{ fontSize: 24, marginBottom: 6 }} />
      ) : (
        <PictureOutlined style={{ fontSize: 24, marginBottom: 6 }} />
      )}
      <div style={{ fontSize: 12, lineHeight: '16px' }}>
        {mediaType === 'video' ? '视频文件' : '图片文件'}
      </div>
      {ext && <div style={{ fontSize: 11, marginTop: 2 }}>{ext.slice(1).toUpperCase()}</div>}
    </div>
  );
}

/** 共用分类侧栏 + 弹窗内容 */
function PickerModalContent({
  folder,
  setFolder,
  assets,
  total,
  page,
  setPage,
  loading,
  onSelect,
  onUpload,
  selectedCheck,
  fileType,
  keyword,
  setKeyword,
  emptyHint,
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
  fileType: AssetFileType;
  keyword: string;
  setKeyword: (v: string) => void;
  emptyHint?: string;
}) {
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [allTotal, setAllTotal] = useState(0);
  const mediaLabel = getMediaLabel(fileType);

  useEffect(() => {
    http
      .get('/assets/folders')
      .then(({ data: resp }) => {
        if (resp.code === 0) {
          setFolders(resp.data.folders || []);
          setAllTotal(resp.data.total);
        }
      })
      .catch(() => {});
  }, []);

  return (
    <div style={{ display: 'flex', gap: 12, height: '100%' }}>
      <div
        style={{
          width: 140,
          minWidth: 140,
          background: '#fafafa',
          borderRadius: 6,
          border: '1px solid #f0f0f0',
          padding: '8px 0',
          overflowY: 'auto',
          height: '100%',
        }}
      >
        <div
          onClick={() => {
            setFolder(null);
            setPage(1);
          }}
          style={{
            padding: '6px 10px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            fontSize: 13,
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
            onClick={() => {
              setFolder(f.folder);
              setPage(1);
            }}
            style={{
              padding: '6px 10px',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              fontSize: 13,
              background: folder === f.folder ? '#e6f4ff' : 'transparent',
              color: folder === f.folder ? '#1677ff' : '#333',
            }}
          >
            <FolderOutlined />
            <span
              style={{
                flex: 1,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
              }}
            >
              {f.folder || '未分类'}
            </span>
            <span style={{ fontSize: 11, color: '#999' }}>{f.count}</span>
          </div>
        ))}
      </div>

      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', height: '100%' }}>
        <div style={{ marginBottom: 12, display: 'flex', gap: 8, alignItems: 'center' }}>
          <Upload
            showUploadList={false}
            accept={getAcceptType(fileType)}
            beforeUpload={(file) => {
              onUpload(file);
              return false;
            }}
          >
            <Button icon={<UploadOutlined />} type="primary" size="small">
              上传{mediaLabel}
            </Button>
          </Upload>
          <Input.Search
            placeholder="按文件名搜索（例：IMG_7459）"
            allowClear
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            onSearch={(v) => {
              setPage(1);
              setKeyword(v.trim());
            }}
            style={{ width: 260 }}
            size="small"
          />
        </div>

        {fileType === 'all' && (
          <Alert
            type="info"
            showIcon
            style={{ marginBottom: 8 }}
            message="当前展示全部素材（含图片和视频）。HEIC 归类为图片，MOV 归类为视频。"
          />
        )}
        {fileType === 'image' && (
          <Alert
            type="info"
            showIcon
            style={{ marginBottom: 8 }}
            message="当前为图片选择器，仅显示图片素材（含 HEIC/HEIF）。"
          />
        )}
        {fileType === 'video' && (
          <Alert
            type="info"
            showIcon
            style={{ marginBottom: 8 }}
            message="当前为视频选择器，仅显示视频素材（含 MOV/MP4）。"
          />
        )}
        {emptyHint && (
          <Alert
            type="warning"
            showIcon
            style={{ marginBottom: 8 }}
            message={emptyHint}
          />
        )}

        <Spin spinning={loading}>
          <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', paddingRight: 2 }}>
            {assets.length === 0 ? (
              <Empty description={`暂无${mediaLabel}`} style={{ marginTop: 48 }} />
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 8 }}>
                {assets.map((asset) => (
                  <div
                    key={asset.id}
                    onClick={() => onSelect(asset)}
                    style={{
                      aspectRatio: '1',
                      border: selectedCheck(asset.url) ? '2px solid #1677ff' : '1px solid #e8e8e8',
                      borderRadius: 6,
                      overflow: 'hidden',
                      cursor: 'pointer',
                      position: 'relative',
                    }}
                  >
                    <AssetPreview
                      url={asset.url}
                      previewUrl={asset.preview_url}
                      originalName={asset.original_name}
                      fileType={asset.file_type}
                    />
                    {selectedCheck(asset.url) && (
                      <div
                        style={{
                          position: 'absolute',
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          background: 'rgba(22,119,255,0.15)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#1677ff',
                          fontWeight: 'bold',
                          fontSize: 20,
                        }}
                      >
                        ✓
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
          {total > PICKER_PAGE_SIZE && (
            <div style={{ textAlign: 'center', marginTop: 12 }}>
              <Pagination current={page} total={total} pageSize={PICKER_PAGE_SIZE} onChange={setPage} size="small" />
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
  fileType?: AssetFileType;
}

export default function AssetPicker({ value, onChange, fileType = 'image' }: AssetPickerProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [folder, setFolder] = useState<string | null>(null);
  const [keyword, setKeyword] = useState('');
  const [draftValue, setDraftValue] = useState('');
  const [emptyHint, setEmptyHint] = useState('');

  const mediaLabel = getMediaLabel(fileType);

  const fetchAssets = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string | number> = { page: 1, page_size: PICKER_FETCH_LIMIT };
      if (folder !== null) params.folder = folder;

      const { data: resp } = await http.get('/assets', { params });
      if (resp.code === 0) {
        const allList: Asset[] = resp.data.list || [];
        const keywordMatchedList = allList.filter((a: Asset) => isAssetMatchKeyword(a, keyword));
        const filteredList = keywordMatchedList.filter((a: Asset) => isAssetMatchType(a, fileType));
        const start = (page - 1) * PICKER_PAGE_SIZE;
        if (filteredList.length > 0 && start >= filteredList.length && page > 1) {
          setPage(1);
          setAssets(filteredList.slice(0, PICKER_PAGE_SIZE));
        } else {
          setAssets(filteredList.slice(start, start + PICKER_PAGE_SIZE));
        }
        setTotal(filteredList.length);
        if (keyword.trim() && filteredList.length === 0) {
          const peerTypeCount = keywordMatchedList.filter((a: Asset) =>
            isAssetMatchType(a, fileType === 'image' ? 'video' : 'image'),
          ).length;
          if (peerTypeCount > 0) {
            if (fileType === 'image') {
              setEmptyHint(`只找到 ${peerTypeCount} 个同名视频文件，未找到 HEIC/JPG/PNG 静态图。请先上传同名静态图。`);
            } else if (fileType === 'video') {
              setEmptyHint(`只找到 ${peerTypeCount} 个同名图片文件，未找到 MOV/MP4 视频。`);
            } else {
              setEmptyHint('');
            }
          } else {
            setEmptyHint('未找到匹配素材，请检查文件名关键字后重试。');
          }
        } else {
          setEmptyHint('');
        }
      }
    } catch {
      // ignore
      setEmptyHint('');
    }
    setLoading(false);
  }, [page, folder, fileType, keyword]);

  useEffect(() => {
    if (modalOpen) {
      setDraftValue(value || '');
      fetchAssets();
    }
  }, [modalOpen, fetchAssets, value]);

  const handleSelect = (asset: Asset) => {
    setDraftValue(asset.url);
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
        message.success(`上传${mediaLabel}成功`);
        setDraftValue(resp.data.url || '');
        fetchAssets();
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleConfirm = () => {
    if (!draftValue) {
      message.warning(`请先选择${mediaLabel}`);
      return;
    }
    onChange?.(draftValue);
    message.success(`已选择${mediaLabel}`);
    setModalOpen(false);
  };

  const handleRemove = (e: React.MouseEvent) => {
    e.stopPropagation();
    onChange?.('');
    message.success(`已删除${mediaLabel}`);
  };

  return (
    <>
      <div
        onClick={() => setModalOpen(true)}
        style={{
          width: 104,
          height: 104,
          border: '1px dashed #d9d9d9',
          borderRadius: 8,
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          position: 'relative',
          overflow: 'hidden',
          background: '#fafafa',
        }}
      >
        {value ? (
          <>
            <AssetPreview url={value} fileType={fileType} />
            <div
              onClick={handleRemove}
              style={{
                position: 'absolute',
                top: 2,
                right: 2,
                background: 'rgba(0,0,0,0.5)',
                borderRadius: '50%',
                width: 22,
                height: 22,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <DeleteOutlined style={{ color: '#fff', fontSize: 12 }} />
            </div>
          </>
        ) : (
          <div style={{ textAlign: 'center', color: '#999' }}>
            <PlusOutlined style={{ fontSize: 20 }} />
            <div style={{ fontSize: 12, marginTop: 4 }}>选择{mediaLabel}</div>
          </div>
        )}
      </div>

      <Modal
        title={`素材库 - 选择${mediaLabel}`}
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        width={1100}
        destroyOnClose
        styles={{ body: { paddingTop: 12, height: 620 } }}
        footer={[
          <Button key="cancel" onClick={() => setModalOpen(false)}>
            取消
          </Button>,
          <Button key="confirm" type="primary" onClick={handleConfirm} disabled={!draftValue}>
            确认选择
          </Button>,
        ]}
      >
        <PickerModalContent
          folder={folder}
          setFolder={setFolder}
          assets={assets}
          total={total}
          page={page}
          setPage={setPage}
          loading={loading}
          onSelect={handleSelect}
          onUpload={handleUpload}
          selectedCheck={(url) => url === draftValue}
          fileType={fileType}
          keyword={keyword}
          setKeyword={setKeyword}
          emptyHint={emptyHint}
        />
      </Modal>
    </>
  );
}

interface MultiAssetPickerProps {
  value?: string[];
  onChange?: (urls: string[]) => void;
  max?: number;
  fileType?: AssetFileType;
}

const EMPTY_URLS: string[] = [];

export function MultiAssetPicker({ value, onChange, max = 9, fileType = 'image' }: MultiAssetPickerProps) {
  const selectedValues = value ?? EMPTY_URLS;
  const [modalOpen, setModalOpen] = useState(false);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [folder, setFolder] = useState<string | null>(null);
  const [keyword, setKeyword] = useState('');
  const [draftValues, setDraftValues] = useState<string[]>([]);
  const [emptyHint, setEmptyHint] = useState('');

  const mediaLabel = getMediaLabel(fileType);

  const fetchAssets = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string | number> = { page: 1, page_size: PICKER_FETCH_LIMIT };
      if (folder !== null) params.folder = folder;

      const { data: resp } = await http.get('/assets', { params });
      if (resp.code === 0) {
        const allList: Asset[] = resp.data.list || [];
        const keywordMatchedList = allList.filter((a: Asset) => isAssetMatchKeyword(a, keyword));
        const filteredList = keywordMatchedList.filter((a: Asset) => isAssetMatchType(a, fileType));
        const start = (page - 1) * PICKER_PAGE_SIZE;
        if (filteredList.length > 0 && start >= filteredList.length && page > 1) {
          setPage(1);
          setAssets(filteredList.slice(0, PICKER_PAGE_SIZE));
        } else {
          setAssets(filteredList.slice(start, start + PICKER_PAGE_SIZE));
        }
        setTotal(filteredList.length);
        if (keyword.trim() && filteredList.length === 0) {
          const peerTypeCount = keywordMatchedList.filter((a: Asset) =>
            isAssetMatchType(a, fileType === 'image' ? 'video' : 'image'),
          ).length;
          if (peerTypeCount > 0) {
            if (fileType === 'image') {
              setEmptyHint(`只找到 ${peerTypeCount} 个同名视频文件，未找到 HEIC/JPG/PNG 静态图。请先上传同名静态图。`);
            } else if (fileType === 'video') {
              setEmptyHint(`只找到 ${peerTypeCount} 个同名图片文件，未找到 MOV/MP4 视频。`);
            } else {
              setEmptyHint('');
            }
          } else {
            setEmptyHint('未找到匹配素材，请检查文件名关键字后重试。');
          }
        } else {
          setEmptyHint('');
        }
      }
    } catch {
      // ignore
      setEmptyHint('');
    }
    setLoading(false);
  }, [page, folder, fileType, keyword]);

  useEffect(() => {
    if (modalOpen) {
      fetchAssets();
    }
  }, [modalOpen, fetchAssets]);

  useEffect(() => {
    if (modalOpen) {
      setDraftValues([...selectedValues]);
    }
  }, [modalOpen, selectedValues]);

  const handleSelect = (asset: Asset) => {
    const exists = draftValues.includes(asset.url);
    if (exists) {
      setDraftValues(draftValues.filter((u) => u !== asset.url));
      return;
    }
    if (draftValues.length >= max) {
      message.warning(`最多选择 ${max} 个`);
      return;
    }
    setDraftValues([...draftValues, asset.url]);
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
        message.success(`上传${mediaLabel}成功`);
        const uploadedUrl = resp.data.url || '';
        if (uploadedUrl && !draftValues.includes(uploadedUrl) && draftValues.length < max) {
          setDraftValues([...draftValues, uploadedUrl]);
        }
        fetchAssets();
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleConfirm = () => {
    onChange?.(draftValues);
    message.success(`已选择 ${draftValues.length} 个${mediaLabel}`);
    setModalOpen(false);
  };

  const handleRemove = (url: string, e: React.MouseEvent) => {
    e.stopPropagation();
    onChange?.(selectedValues.filter((u) => u !== url));
    message.success(`已删除${mediaLabel}`);
  };

  return (
    <>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {selectedValues.map((url) => (
          <div
            key={url}
            style={{
              width: 80,
              height: 80,
              border: '1px solid #e8e8e8',
              borderRadius: 6,
              overflow: 'hidden',
              position: 'relative',
            }}
          >
            <AssetPreview url={url} fileType={fileType} />
            <div
              onClick={(e) => handleRemove(url, e)}
              style={{
                position: 'absolute',
                top: 2,
                right: 2,
                background: 'rgba(0,0,0,0.5)',
                borderRadius: '50%',
                width: 20,
                height: 20,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
              }}
            >
              <DeleteOutlined style={{ color: '#fff', fontSize: 10 }} />
            </div>
          </div>
        ))}
        {selectedValues.length < max && (
          <div
            onClick={() => setModalOpen(true)}
            style={{
              width: 80,
              height: 80,
              border: '1px dashed #d9d9d9',
              borderRadius: 6,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: '#fafafa',
            }}
          >
            <PlusOutlined style={{ fontSize: 18, color: '#999' }} />
          </div>
        )}
      </div>

      <Modal
        title={`素材库 - 选择${mediaLabel}`}
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        width={1100}
        destroyOnClose
        styles={{ body: { paddingTop: 12, height: 620 } }}
        footer={[
          <Button key="cancel" onClick={() => setModalOpen(false)}>
            取消
          </Button>,
          <Button key="confirm" type="primary" onClick={handleConfirm}>
            确认选择（{draftValues.length}/{max}）
          </Button>,
        ]}
      >
        <PickerModalContent
          folder={folder}
          setFolder={setFolder}
          assets={assets}
          total={total}
          page={page}
          setPage={setPage}
          loading={loading}
          onSelect={handleSelect}
          onUpload={handleUpload}
          selectedCheck={(url) => draftValues.includes(url)}
          fileType={fileType}
          keyword={keyword}
          setKeyword={setKeyword}
          emptyHint={emptyHint}
        />
      </Modal>
    </>
  );
}
