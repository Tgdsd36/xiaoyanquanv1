import { useEffect, useState, useCallback } from 'react';
import { Upload, Button, Input, Select, Space, Spin, Empty, Pagination, Popconfirm, Modal, message, Checkbox } from 'antd';
import {
  UploadOutlined,
  DeleteOutlined,
  FolderOutlined,
  FolderOpenOutlined,
  PlusOutlined,
  EditOutlined,
  DeleteFilled,
  PictureOutlined,
  VideoCameraOutlined,
} from '@ant-design/icons';
import http from '../api/http';
import { toAbsoluteUrl } from '../utils/url';

interface Asset {
  id: number;
  filename: string;
  original_name: string;
  url: string;
  preview_url?: string;
  file_type: string;
  file_size: number;
  folder: string;
  created_at: string;
}

interface FolderInfo {
  folder: string;
  count: number;
}

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

function formatSize(bytes: number) {
  if (bytes >= 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return bytes + ' B';
}

function getAssetExt(url: string) {
  const dotIndex = url.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === url.length - 1) return '';
  return url.slice(dotIndex + 1).toUpperCase();
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

function LivePackImagePreview({ pack }: { pack: LivePack }) {
  const candidates = [
    (pack.image_preview_url || '').trim(),
    deriveHEICPreviewUrl(pack.image_url || ''),
    (pack.image_url || '').trim(),
  ].filter((v) => !!v);
  const [idx, setIdx] = useState(0);
  const [videoFailed, setVideoFailed] = useState(false);
  const current = candidates[idx] || '';

  useEffect(() => {
    setIdx(0);
    setVideoFailed(false);
  }, [pack.id, pack.image_url, pack.image_preview_url, pack.video_url]);

  if (!current && pack.video_url && !videoFailed) {
    return (
      <video
        src={toAbsoluteUrl(pack.video_url)}
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
      <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#7f8ea3', fontSize: 12 }}>
        无静态图
      </div>
    );
  }

  return (
    <img
      src={toAbsoluteUrl(current)}
      alt={pack.base_name}
      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
      onError={() => setIdx((prev) => prev + 1)}
    />
  );
}

function LivePackVideoPreview({ pack }: { pack: LivePack }) {
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setFailed(false);
  }, [pack.id, pack.video_url]);

  if (!pack.video_url || failed) {
    return (
      <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#7f8ea3', fontSize: 12 }}>
        无MOV视频
      </div>
    );
  }

  return (
    <video
      src={toAbsoluteUrl(pack.video_url)}
      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
      muted
      playsInline
      preload="metadata"
      onError={() => setFailed(true)}
    />
  );
}

function AssetPreview({ asset }: { asset: Asset }) {
  const [loadFailed, setLoadFailed] = useState(false);
  const ext = getAssetExt(asset.url);
  const previewSource =
    asset.preview_url || deriveHEICPreviewUrl(asset.url) || asset.url;
  const fullUrl = toAbsoluteUrl(previewSource);

  if (asset.file_type === 'video' && !loadFailed) {
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

  if (asset.file_type === 'image' && !loadFailed) {
    return (
      <img
        src={fullUrl}
        alt={asset.original_name}
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
        color: '#7f8ea3',
        background: '#f5f7fa',
        fontSize: 12,
      }}
      title={asset.original_name}
    >
      {asset.file_type === 'video' ? (
        <VideoCameraOutlined style={{ fontSize: 22, marginBottom: 4 }} />
      ) : (
        <PictureOutlined style={{ fontSize: 22, marginBottom: 4 }} />
      )}
      <span>{asset.file_type === 'video' ? '视频文件' : '图片文件'}</span>
      {ext && <span style={{ fontSize: 11 }}>{ext}</span>}
    </div>
  );
}

export default function AssetPage() {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [livePacks, setLivePacks] = useState<LivePack[]>([]);
  const [total, setTotal] = useState(0);
  const [allTotal, setAllTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [fileType, setFileType] = useState('');
  const [keyword, setKeyword] = useState('');
  const [currentFolder, setCurrentFolder] = useState<string | null>(null); // null = 全部
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [newFolderName, setNewFolderName] = useState('');
  const [newFolderOpen, setNewFolderOpen] = useState(false);
  const [selectedAssetIds, setSelectedAssetIds] = useState<number[]>([]);
  const [selectedLivePackIds, setSelectedLivePackIds] = useState<number[]>([]);
  const [targetFolder, setTargetFolder] = useState<string>('');
  const isLiveMode = fileType === 'live_photo';
  const selectedCount = isLiveMode ? selectedLivePackIds.length : selectedAssetIds.length;

  const fetchFolders = useCallback(async () => {
    try {
      const { data: resp } = await http.get('/assets/folders');
      if (resp.code === 0) {
        setFolders(resp.data.folders || []);
        setAllTotal(resp.data.total);
      }
    } catch { /* ignore */ }
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 40 };
    if (currentFolder !== null) params.folder = currentFolder;
    if (keyword) params.keyword = keyword;
    try {
      if (isLiveMode) {
        const { data: resp } = await http.get('/assets/live-packs', { params });
        if (resp.code === 0) {
          setLivePacks(resp.data.list || []);
          setAssets([]);
          setTotal(resp.data.total || 0);
        }
      } else {
        if (fileType) params.file_type = fileType;
        const { data: resp } = await http.get('/assets', { params });
        if (resp.code === 0) {
          setAssets(resp.data.list || []);
          setLivePacks([]);
          setTotal(resp.data.total || 0);
        }
      }
    } catch { /* ignore */ }
    setLoading(false);
  }, [page, fileType, currentFolder, keyword, isLiveMode]);

  useEffect(() => { fetchFolders(); }, [fetchFolders]);
  useEffect(() => { fetchData(); }, [fetchData]);
  useEffect(() => {
    setSelectedAssetIds([]);
    setSelectedLivePackIds([]);
  }, [fileType, page, currentFolder, keyword]);

  const handleUpload = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    if (currentFolder) formData.append('folder', currentFolder);
    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        message.success('上传成功');
        fetchData();
        fetchFolders();
      } else {
        message.error(resp.message || '上传失败');
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleLiveUpload = async (file: File, liveRole: 'image' | 'video') => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('live_role', liveRole);
    if (currentFolder) formData.append('folder', currentFolder);
    try {
      const { data: resp } = await http.post('/assets/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      if (resp.code === 0) {
        message.success(liveRole === 'image' ? 'Live 静态图上传成功' : 'Live 动态视频上传成功');
        fetchData();
        fetchFolders();
      } else {
        message.error(resp.message || '上传失败');
      }
    } catch {
      message.error('上传失败');
    }
  };

  const handleDelete = async (id: number) => {
    await http.delete(`/assets/${id}`);
    message.success('已删除');
    fetchData();
    fetchFolders();
  };

  const handleDeleteLivePack = async (pack: LivePack) => {
    const ids = Array.from(
      new Set([pack.image_asset_id, pack.video_asset_id].filter((v): v is number => typeof v === 'number')),
    );
    if (ids.length === 0) {
      message.warning('该套件没有可删除的素材');
      return;
    }
    try {
      await Promise.all(ids.map((id) => http.delete(`/assets/${id}`)));
      message.success('Live 套件已删除');
      fetchData();
      fetchFolders();
    } catch {
      message.error('删除 Live 套件失败');
    }
  };

  const toggleAssetSelect = (id: number, checked: boolean) => {
    setSelectedAssetIds((prev) => {
      if (checked) return Array.from(new Set([...prev, id]));
      return prev.filter((item) => item !== id);
    });
  };

  const toggleLivePackSelect = (id: number, checked: boolean) => {
    setSelectedLivePackIds((prev) => {
      if (checked) return Array.from(new Set([...prev, id]));
      return prev.filter((item) => item !== id);
    });
  };

  const handleSelectAllCurrentPage = () => {
    if (isLiveMode) {
      setSelectedLivePackIds(livePacks.map((item) => item.id));
      return;
    }
    setSelectedAssetIds(assets.map((item) => item.id));
  };

  const handleClearSelection = () => {
    setSelectedAssetIds([]);
    setSelectedLivePackIds([]);
  };

  const handleBatchMoveFolder = async () => {
    if (selectedCount === 0) {
      message.warning('请先选择素材');
      return;
    }
    try {
      const folderValue = targetFolder === '__uncategorized__' ? '' : targetFolder;
      const { data: resp } = await http.post('/assets/folders/batch-update', {
        asset_ids: isLiveMode ? [] : selectedAssetIds,
        live_pack_ids: isLiveMode ? selectedLivePackIds : [],
        folder: folderValue,
      });
      if (resp.code === 0) {
        message.success('批量修改分类成功');
        handleClearSelection();
        fetchData();
        fetchFolders();
      } else {
        message.error(resp.message || '批量修改分类失败');
      }
    } catch {
      message.error('批量修改分类失败');
    }
  };

  const handleBatchDelete = async () => {
    if (selectedCount === 0) {
      message.warning('请先选择素材');
      return;
    }
    try {
      const { data: resp } = await http.post('/assets/batch-delete', {
        asset_ids: isLiveMode ? [] : selectedAssetIds,
        live_pack_ids: isLiveMode ? selectedLivePackIds : [],
      });
      if (resp.code === 0) {
        message.success('批量删除成功');
        handleClearSelection();
        fetchData();
        fetchFolders();
      } else {
        message.error(resp.message || '批量删除失败');
      }
    } catch {
      message.error('批量删除失败');
    }
  };

  const handleCreateFolder = async () => {
    const name = newFolderName.trim();
    if (!name) return;
    try {
      const { data: resp } = await http.post('/assets/folders/create', { name });
      if (resp.code !== 0) {
        message.error(resp.message || '创建分类失败');
        return;
      }
      message.success('分类创建成功');
      setNewFolderOpen(false);
      setCurrentFolder(name);
      setNewFolderName('');
      setPage(1);
      fetchFolders();
      fetchData();
    } catch {
      message.error('创建分类失败');
    }
  };

  const handleRenameFolder = async (oldName: string) => {
    const name = prompt('输入新分类名', oldName);
    if (!name || name === oldName) return;
    await http.put('/assets/folders/rename', { old_name: oldName, new_name: name });
    message.success('重命名成功');
    if (currentFolder === oldName) setCurrentFolder(name);
    fetchFolders();
  };

  const handleDeleteFolder = async (folder: string) => {
    await http.post('/assets/folders/delete', { folder });
    message.success('分类已删除，文件已移到未分类');
    if (currentFolder === folder) setCurrentFolder(null);
    fetchFolders();
    fetchData();
  };

  const selectFolder = (folder: string | null) => {
    setCurrentFolder(folder);
    setPage(1);
  };

  return (
    <div style={{ display: 'flex', gap: 16, height: 'calc(100vh - 160px)' }}>
      {/* 左侧分类栏 */}
      <div style={{
        width: 200, minWidth: 200, background: '#fafafa', borderRadius: 8,
        border: '1px solid #f0f0f0', padding: '12px 0', overflowY: 'auto',
      }}>
        <div style={{ padding: '0 12px 8px', fontWeight: 600, fontSize: 14, color: '#333' }}>分类</div>

        {/* 全部 */}
        <div
          onClick={() => selectFolder(null)}
          style={{
            padding: '8px 12px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
            background: currentFolder === null ? '#e6f4ff' : 'transparent',
            color: currentFolder === null ? '#1677ff' : '#333',
          }}
        >
          <FolderOpenOutlined /> <span style={{ flex: 1 }}>全部</span>
          <span style={{ fontSize: 12, color: '#999' }}>{allTotal}</span>
        </div>

        {/* 分类列表 */}
        {folders.map((f) => (
          <div
            key={f.folder || '__uncategorized'}
            onClick={() => selectFolder(f.folder)}
            style={{
              padding: '8px 12px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
              background: currentFolder === f.folder ? '#e6f4ff' : 'transparent',
              color: currentFolder === f.folder ? '#1677ff' : '#333',
            }}
          >
            <FolderOutlined />
            <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {f.folder || '未分类'}
            </span>
            <span style={{ fontSize: 12, color: '#999' }}>{f.count}</span>
            {f.folder && (
              <span onClick={(e) => e.stopPropagation()} style={{ display: 'flex', gap: 2 }}>
                <EditOutlined style={{ fontSize: 12, color: '#999' }} onClick={() => handleRenameFolder(f.folder)} />
                <Popconfirm title="删除分类？文件将移到未分类" onConfirm={() => handleDeleteFolder(f.folder)}>
                  <DeleteFilled style={{ fontSize: 12, color: '#999' }} />
                </Popconfirm>
              </span>
            )}
          </div>
        ))}

        {/* 新建分类 */}
        <div
          onClick={() => setNewFolderOpen(true)}
          style={{ padding: '8px 12px', cursor: 'pointer', color: '#1677ff', display: 'flex', alignItems: 'center', gap: 8 }}
        >
          <PlusOutlined /> 新建分类
        </div>
      </div>

      {/* 右侧内容区 */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* 工具栏 */}
        <Space style={{ marginBottom: 12 }} wrap>
          {isLiveMode ? (
            <>
              <Upload
                showUploadList={false}
                accept="image/*,.heic,.heif"
                beforeUpload={(file) => { handleLiveUpload(file, 'image'); return false; }}
              >
                <Button type="primary" icon={<UploadOutlined />}>上传 Live 静态图</Button>
              </Upload>
              <Upload
                showUploadList={false}
                accept="video/*,.mov"
                beforeUpload={(file) => { handleLiveUpload(file, 'video'); return false; }}
              >
                <Button icon={<UploadOutlined />}>上传 Live 动态视频(MOV)</Button>
              </Upload>
            </>
          ) : (
            <Upload
              showUploadList={false}
              accept="image/*,video/*,.heic,.heif,.mov,.mp4,.m4v,.avi,.mkv,.webm"
              multiple
              beforeUpload={(file) => { handleUpload(file); return false; }}
            >
              <Button type="primary" icon={<UploadOutlined />}>上传文件</Button>
            </Upload>
          )}
          <Input.Search
            placeholder={isLiveMode ? '搜索套件 base_name' : '搜索文件名'}
            style={{ width: 200 }}
            allowClear
            onSearch={(v) => { setKeyword(v); setPage(1); }}
          />
          <Select
            placeholder="文件类型"
            style={{ width: 120 }}
            value={fileType || undefined}
            onChange={(v) => { setFileType(v || ''); setPage(1); }}
            allowClear
            options={[
              { value: 'image', label: '图片' },
              { value: 'video', label: '视频' },
              { value: 'live_photo', label: 'Live套件' },
            ]}
          />
          <span style={{ color: '#999', fontSize: 13 }}>
            共 {total} 个{isLiveMode ? '套件' : '文件'}
          </span>
          <Button onClick={handleSelectAllCurrentPage} disabled={isLiveMode ? livePacks.length === 0 : assets.length === 0}>
            全选当前页
          </Button>
          <Button onClick={handleClearSelection} disabled={selectedCount === 0}>
            取消选择
          </Button>
          <Select
            style={{ width: 180 }}
            value={targetFolder || undefined}
            placeholder="选择目标分类"
            onChange={(v) => setTargetFolder(v || '')}
            options={[
              { value: '__uncategorized__', label: '未分类' },
              ...folders
                .filter((f) => f.folder)
                .map((f) => ({ value: f.folder, label: f.folder })),
            ]}
          />
          <Popconfirm
            title={`确认将已选 ${selectedCount} 个${isLiveMode ? '套件' : '文件'}移动到目标分类？`}
            onConfirm={handleBatchMoveFolder}
            disabled={selectedCount === 0 || !targetFolder}
          >
            <Button type="primary" disabled={selectedCount === 0 || !targetFolder}>
              批量修改分类
            </Button>
          </Popconfirm>
          <Popconfirm
            title={`确认删除已选的 ${selectedCount} 个${isLiveMode ? '套件' : '文件'}？此操作不可撤销。`}
            onConfirm={handleBatchDelete}
            disabled={selectedCount === 0}
            okText="删除"
            okButtonProps={{ danger: true }}
          >
            <Button danger disabled={selectedCount === 0} icon={<DeleteOutlined />}>
              批量删除
            </Button>
          </Popconfirm>
        </Space>

        {/* 文件网格 */}
        <div style={{ flex: 1, overflowY: 'auto' }}>
          <Spin spinning={loading}>
            {(isLiveMode ? livePacks.length === 0 : assets.length === 0) ? (
              <Empty description={isLiveMode ? '暂无 Live 套件' : '暂无文件'} style={{ marginTop: 60 }} />
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 10 }}>
                {isLiveMode
                  ? livePacks.map((pack) => (
                  <div
                    key={pack.id}
                    style={{
                      border: '1px solid #e8e8e8',
                      borderRadius: 8,
                      overflow: 'hidden',
                      background: '#fafafa',
                      opacity: pack.status === 'complete' ? 1 : 0.8,
                      position: 'relative',
                    }}
                  >
                    <div style={{ position: 'absolute', left: 6, top: 6, zIndex: 3, background: 'rgba(255,255,255,0.82)', borderRadius: 4, padding: '0 2px' }}>
                      <Checkbox
                        checked={selectedLivePackIds.includes(pack.id)}
                        onChange={(e) => toggleLivePackSelect(pack.id, e.target.checked)}
                      />
                    </div>
                    <div style={{ aspectRatio: '1', overflow: 'hidden', background: '#f0f0f0', display: 'grid', gridTemplateColumns: '1fr 1fr' }}>
                      <div style={{ borderRight: '1px solid #ececec', position: 'relative' }}>
                        <LivePackImagePreview pack={pack} />
                        <span style={{ position: 'absolute', left: 6, bottom: 6, background: 'rgba(0,0,0,0.45)', color: '#fff', fontSize: 10, padding: '1px 6px', borderRadius: 10 }}>
                          HEIC
                        </span>
                      </div>
                      <div style={{ position: 'relative' }}>
                        <LivePackVideoPreview pack={pack} />
                        <span style={{ position: 'absolute', left: 6, bottom: 6, background: 'rgba(0,0,0,0.45)', color: '#fff', fontSize: 10, padding: '1px 6px', borderRadius: 10 }}>
                          MOV
                        </span>
                      </div>
                    </div>
                    <div style={{ padding: '4px 6px' }}>
                      <div style={{ fontSize: 11, fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={pack.base_name}>
                        {pack.base_name}
                      </div>
                      <div style={{ fontSize: 10, color: '#999', marginTop: 2 }}>
                        分类：{pack.folder || '未分类'}
                      </div>
                      {pack.status !== 'complete' && (
                        <div style={{ fontSize: 10, color: '#fa8c16', marginTop: 2 }}>
                          缺少：{(pack.missing || []).join(' + ') || '静态图/MOV视频'}
                        </div>
                      )}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 2 }}>
                        <span style={{ fontSize: 10, color: '#999' }}>
                          {pack.status === 'complete' ? '完整套件' : '半成品'}
                        </span>
                        <Popconfirm title="确认删除整个套件？" onConfirm={() => handleDeleteLivePack(pack)}>
                          <Button type="text" size="small" danger icon={<DeleteOutlined />} style={{ padding: 0, height: 'auto' }} />
                        </Popconfirm>
                      </div>
                    </div>
                  </div>
                ))
                  : assets.map((asset) => (
                  <div
                    key={asset.id}
                    style={{ border: '1px solid #e8e8e8', borderRadius: 8, overflow: 'hidden', background: '#fafafa', position: 'relative' }}
                  >
                    <div style={{ position: 'absolute', left: 6, top: 6, zIndex: 3, background: 'rgba(255,255,255,0.82)', borderRadius: 4, padding: '0 2px' }}>
                      <Checkbox
                        checked={selectedAssetIds.includes(asset.id)}
                        onChange={(e) => toggleAssetSelect(asset.id, e.target.checked)}
                      />
                    </div>
                    <div style={{ aspectRatio: '1', overflow: 'hidden', background: '#f0f0f0' }}>
                      <AssetPreview asset={asset} />
                    </div>
                    <div style={{ padding: '4px 6px' }}>
                      <div style={{ fontSize: 11, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={asset.original_name}>
                        {asset.original_name}
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 2 }}>
                        <span style={{ fontSize: 10, color: '#999' }}>{formatSize(asset.file_size)}</span>
                        <Popconfirm title="确认删除？" onConfirm={() => handleDelete(asset.id)}>
                          <Button type="text" size="small" danger icon={<DeleteOutlined />} style={{ padding: 0, height: 'auto' }} />
                        </Popconfirm>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Spin>
        </div>

        {total > 40 && (
          <div style={{ textAlign: 'center', paddingTop: 12 }}>
            <Pagination current={page} total={total} pageSize={40} onChange={setPage} size="small" />
          </div>
        )}
      </div>

      {/* 新建分类弹窗 */}
      <Modal
        title="新建分类"
        open={newFolderOpen}
        onOk={handleCreateFolder}
        onCancel={() => setNewFolderOpen(false)}
      >
        <Input
          placeholder="输入分类名称"
          value={newFolderName}
          onChange={(e) => setNewFolderName(e.target.value)}
          onPressEnter={handleCreateFolder}
        />
      </Modal>
    </div>
  );
}
