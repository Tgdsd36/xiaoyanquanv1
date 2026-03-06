import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Card, Empty, Input, message, Modal, Popconfirm, Select, Space, Tag } from 'antd';
import mobileHttp from '../../api/mobileHttp';
import { toAbsoluteUrl } from '../../utils/url';

interface Asset {
  id: number;
  original_name: string;
  url: string;
  preview_url?: string;
  file_type: string;
  file_size: number;
  folder: string;
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
  video_asset_id?: number;
  video_url?: string;
}

interface FolderInfo {
  folder: string;
  count: number;
}

function formatSize(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${bytes}B`;
}

function deriveHEICPreviewUrl(url: string): string {
  const raw = (url || '').trim();
  if (!raw) return '';
  const queryIndex = raw.indexOf('?');
  const base = queryIndex >= 0 ? raw.slice(0, queryIndex) : raw;
  const query = queryIndex >= 0 ? raw.slice(queryIndex) : '';
  if (!/\.hei[cf]$/i.test(base)) return '';
  return base.replace(/\.hei[cf]$/i, '_preview.jpg') + query;
}

function AssetThumb({ asset }: { asset: Asset }) {
  const candidates = [asset.preview_url || '', deriveHEICPreviewUrl(asset.url), asset.url].filter(Boolean);
  const [index, setIndex] = useState(0);
  const [videoFallback, setVideoFallback] = useState(false);

  useEffect(() => {
    setIndex(0);
    setVideoFallback(false);
  }, [asset.id, asset.url, asset.preview_url]);

  if (asset.file_type === 'video' || videoFallback) {
    return (
      <video src={toAbsoluteUrl(asset.url)} muted playsInline preload="metadata" />
    );
  }

  const src = candidates[index];
  if (!src) return <span>无预览</span>;

  return (
    <img
      src={toAbsoluteUrl(src)}
      alt={asset.original_name}
      onError={() => {
        if (index < candidates.length - 1) {
          setIndex((prev) => prev + 1);
        } else {
          setVideoFallback(true);
        }
      }}
    />
  );
}

function LiveImageThumb({ pack }: { pack: LivePack }) {
  const candidates = [pack.image_preview_url || '', deriveHEICPreviewUrl(pack.image_url || ''), pack.image_url || ''].filter(Boolean);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    setIndex(0);
  }, [pack.id, pack.image_url, pack.image_preview_url]);

  const src = candidates[index];
  if (!src) return <span>无图</span>;

  return (
    <img
      src={toAbsoluteUrl(src)}
      alt={pack.base_name}
      onError={() => setIndex((prev) => Math.min(prev + 1, candidates.length - 1))}
    />
  );
}

function LiveVideoThumb({ pack }: { pack: LivePack }) {
  if (!pack.video_url) return <span>无视频</span>;
  return <video src={toAbsoluteUrl(pack.video_url)} muted playsInline preload="metadata" />;
}

export default function MobileAssetsPage() {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [livePacks, setLivePacks] = useState<LivePack[]>([]);
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [fileType, setFileType] = useState<'image' | 'video' | 'live_photo' | ''>('');
  const [folder, setFolder] = useState('');
  const [keyword, setKeyword] = useState('');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [folderModalOpen, setFolderModalOpen] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [creatingFolder, setCreatingFolder] = useState(false);

  const liveMode = fileType === 'live_photo';

  const fetchFolders = useCallback(async () => {
    try {
      const { data: resp } = await mobileHttp.get('/assets/folders');
      if (resp.code === 0) {
        setFolders(resp.data.folders || []);
      }
    } catch {
      // ignore
    }
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: Record<string, string | number> = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (folder) params.folder = folder;

    try {
      if (liveMode) {
        const { data: resp } = await mobileHttp.get('/assets/live-packs', { params });
        if (resp.code === 0) {
          setLivePacks(resp.data.list || []);
          setAssets([]);
          setHasMore(Boolean(resp.data.has_more));
        }
      } else {
        if (fileType) params.file_type = fileType;
        const { data: resp } = await mobileHttp.get('/assets', { params });
        if (resp.code === 0) {
          setAssets(resp.data.list || []);
          setLivePacks([]);
          setHasMore(Boolean(resp.data.has_more));
        }
      }
    } finally {
      setLoading(false);
    }
  }, [fileType, folder, keyword, liveMode, page]);

  useEffect(() => {
    void fetchFolders();
  }, [fetchFolders]);

  useEffect(() => {
    void fetchData();
  }, [fetchData]);

  const removeAsset = async (id: number) => {
    await mobileHttp.delete(`/assets/${id}`);
    message.success('素材已删除');
    void fetchData();
    void fetchFolders();
  };

  const removeLivePack = async (pack: LivePack) => {
    const ids = [pack.image_asset_id, pack.video_asset_id].filter((v): v is number => typeof v === 'number');
    if (ids.length === 0) {
      message.warning('该套件没有可删除素材');
      return;
    }
    await Promise.all(ids.map((id) => mobileHttp.delete(`/assets/${id}`)));
    message.success('Live套件已删除');
    void fetchData();
    void fetchFolders();
  };

  const folderOptions = useMemo(
    () => [
      { value: '', label: '全部分类' },
      ...folders.map((f) => ({ value: f.folder, label: f.folder || '未分类' })),
    ],
    [folders],
  );

  const handleCreateFolder = async () => {
    const name = newFolderName.trim();
    if (!name) {
      message.warning('请输入分组名称');
      return;
    }
    setCreatingFolder(true);
    try {
      const { data: resp } = await mobileHttp.post('/assets/folders/create', { name });
      if (resp.code === 0) {
        message.success('素材分组创建成功');
        setFolderModalOpen(false);
        setNewFolderName('');
        setFolder(name);
        setPage(1);
        void fetchFolders();
        void fetchData();
      } else {
        message.error(resp.message || '创建分组失败');
      }
    } catch (error: any) {
      message.error(error?.response?.data?.message || '创建分组失败');
    } finally {
      setCreatingFolder(false);
    }
  };

  return (
    <div>
      <Card size="small" style={{ marginBottom: 10 }}>
        <Space direction="vertical" style={{ width: '100%' }} size={10}>
          <Input.Search
            placeholder={liveMode ? '搜索套件名' : '搜索素材名'}
            allowClear
            onSearch={(value) => {
              setKeyword(value.trim());
              setPage(1);
            }}
          />
          <Select
            value={fileType || undefined}
            allowClear
            placeholder="文件类型"
            onChange={(value) => {
              setFileType((value || '') as 'image' | 'video' | 'live_photo' | '');
              setPage(1);
            }}
            options={[
              { value: 'image', label: '图片' },
              { value: 'video', label: '视频' },
              { value: 'live_photo', label: 'Live套件' },
            ]}
          />
          <Select
            value={folder}
            onChange={(value) => {
              setFolder(value);
              setPage(1);
            }}
            options={folderOptions}
          />
          <Button onClick={() => setFolderModalOpen(true)}>创建素材分组</Button>
        </Space>
      </Card>

      {liveMode ? (
        livePacks.length === 0 ? (
          <Card size="small"><Empty description="暂无Live套件" /></Card>
        ) : (
          livePacks.map((pack) => (
            <Card key={pack.id} size="small" style={{ marginBottom: 10 }} loading={loading}>
              <div className="mobile-section-head">
                <h3 title={pack.base_name}>{pack.base_name}</h3>
                <Space size={6}>
                  <Tag color={pack.status === 'complete' ? 'green' : 'gold'}>
                    {pack.status === 'complete' ? '完整' : '半成品'}
                  </Tag>
                  <Popconfirm title="确认删除该Live套件？" onConfirm={() => void removeLivePack(pack)}>
                    <Button size="small" danger>删除</Button>
                  </Popconfirm>
                </Space>
              </div>

              <div className="mobile-media-card__body">
                <div className="mobile-media-card__thumb">
                  <LiveImageThumb pack={pack} />
                </div>
                <div className="mobile-media-card__thumb">
                  <LiveVideoThumb pack={pack} />
                </div>
                <div className="mobile-media-card__meta">
                  <div className="line">分类：{pack.folder || '未分类'}</div>
                  {pack.status !== 'complete' ? <div className="line">缺少：{(pack.missing || []).join(' + ')}</div> : null}
                </div>
              </div>
            </Card>
          ))
        )
      ) : (
        assets.length === 0 ? (
          <Card size="small"><Empty description="暂无素材文件" /></Card>
        ) : (
          assets.map((asset) => (
            <Card key={asset.id} size="small" style={{ marginBottom: 10 }} loading={loading}>
              <div className="mobile-section-head">
                <h3 title={asset.original_name}>{asset.original_name || '未命名文件'}</h3>
                <Space size={6}>
                  <Tag>{asset.file_type === 'video' ? '视频' : '图片'}</Tag>
                  <Popconfirm title="确认删除该素材？" onConfirm={() => void removeAsset(asset.id)}>
                    <Button size="small" danger>删除</Button>
                  </Popconfirm>
                </Space>
              </div>

              <div className="mobile-media-card__body">
                <div className="mobile-media-card__thumb">
                  <AssetThumb asset={asset} />
                </div>
                <div className="mobile-media-card__meta">
                  <div className="line">ID：{asset.id}</div>
                  <div className="line">大小：{formatSize(asset.file_size || 0)}</div>
                  <div className="line">分类：{asset.folder || '未分类'}</div>
                </div>
              </div>
            </Card>
          ))
        )
      )}

      <Card size="small">
        <Space style={{ width: '100%', justifyContent: 'space-between' }}>
          <Button disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>上一页</Button>
          <span style={{ color: '#7a8798', fontSize: 12 }}>第 {page} 页</span>
          <Button disabled={!hasMore} onClick={() => setPage((p) => p + 1)}>下一页</Button>
        </Space>
      </Card>

      <Modal
        title="创建素材分组"
        open={folderModalOpen}
        onOk={() => void handleCreateFolder()}
        okText="创建"
        cancelText="取消"
        confirmLoading={creatingFolder}
        onCancel={() => setFolderModalOpen(false)}
      >
        <Input
          maxLength={30}
          placeholder="输入分组名称"
          value={newFolderName}
          onChange={(e) => setNewFolderName(e.target.value)}
          onPressEnter={() => void handleCreateFolder()}
        />
      </Modal>
    </div>
  );
}
