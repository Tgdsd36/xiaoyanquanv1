import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Card, Empty, Form, Input, message, Modal, Select, Space, Switch, Tag } from 'antd';
import mobileHttp from '../../api/mobileHttp';
import { toAbsoluteUrl } from '../../utils/url';

const typeLabels: Record<string, string> = {
  image: '图片',
  video: '视频',
  live_photo: 'Live',
};

const statusLabels: Record<string, { label: string; color: string }> = {
  draft: { label: '草稿', color: 'default' },
  published: { label: '已发布', color: 'green' },
  offline: { label: '已下线', color: 'red' },
};

interface AssetOption {
  id: number;
  original_name: string;
  url: string;
  preview_url?: string;
}

interface LivePackOption {
  id: number;
  base_name: string;
  image_url: string;
  image_preview_url?: string;
  video_url: string;
}

function deriveHEICPreviewUrl(url?: string): string {
  const raw = (url || '').trim();
  if (!raw) return '';
  const queryIndex = raw.indexOf('?');
  const base = queryIndex >= 0 ? raw.slice(0, queryIndex) : raw;
  const query = queryIndex >= 0 ? raw.slice(queryIndex) : '';
  if (!/\.hei[cf]$/i.test(base)) return '';
  return base.replace(/\.hei[cf]$/i, '_preview.jpg') + query;
}

function buildSecondLevelCategoryOptions(categories: any[]) {
  const options: Array<{ value: number; label: string }> = [];
  categories.forEach((parent: any) => {
    const children = Array.isArray(parent?.children) ? parent.children : [];
    children.forEach((child: any) => {
      if (!child || child.slug === 'male' || child.slug === 'female') return;
      options.push({
        value: child.id,
        label: parent?.name ? `${parent.name} / ${child.name}` : child.name,
      });
    });
  });
  return options;
}

function getMaterialImageCandidates(item: any): string[] {
  const firstOriginal = Array.isArray(item?.original_urls)
    ? item.original_urls.find((u: unknown) => typeof u === 'string' && !!u)
    : '';
  const thumb = typeof item?.thumbnail_url === 'string' ? item.thumbnail_url : '';
  return [
    deriveHEICPreviewUrl(thumb),
    thumb,
    typeof firstOriginal === 'string' ? deriveHEICPreviewUrl(firstOriginal) : '',
    typeof firstOriginal === 'string' ? firstOriginal : '',
  ].filter((v) => typeof v === 'string' && !!v) as string[];
}

function MaterialThumb({ item }: { item: any }) {
  const candidates = useMemo(() => getMaterialImageCandidates(item), [item]);
  const [index, setIndex] = useState(0);
  const [fallbackVideo, setFallbackVideo] = useState(false);

  useEffect(() => {
    setIndex(0);
    setFallbackVideo(false);
  }, [item?.id, item?.thumbnail_url, item?.type]);

  const videoUrl = item?.type === 'video'
    ? (Array.isArray(item?.original_urls) ? item.original_urls[0] || '' : '')
    : (item?.type === 'live_photo' ? item?.preview_mov_url || '' : '');

  if ((item?.type === 'video' || fallbackVideo) && videoUrl) {
    return <video src={toAbsoluteUrl(videoUrl)} muted playsInline preload="metadata" />;
  }

  const current = candidates[index];
  if (!current) return <span>无预览</span>;

  return (
    <img
      src={toAbsoluteUrl(current)}
      alt={item?.title || '素材'}
      onError={() => {
        if (index < candidates.length - 1) {
          setIndex((prev) => prev + 1);
        } else {
          setFallbackVideo(true);
        }
      }}
    />
  );
}

function getAssetPreviewCandidates(asset: AssetOption): string[] {
  return [
    deriveHEICPreviewUrl(asset.preview_url || ''),
    asset.preview_url || '',
    deriveHEICPreviewUrl(asset.url),
    asset.url,
  ].filter((v) => !!v);
}

function SourceAssetThumb({ asset, isVideo }: { asset: AssetOption; isVideo: boolean }) {
  const candidates = useMemo(() => getAssetPreviewCandidates(asset), [asset]);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    setIndex(0);
  }, [asset.id, asset.url, asset.preview_url, isVideo]);

  if (isVideo) {
    return <video src={toAbsoluteUrl(asset.url)} muted playsInline preload="metadata" />;
  }

  const src = candidates[index];
  if (!src) return <span>无预览</span>;

  return (
    <img
      src={toAbsoluteUrl(src)}
      alt={asset.original_name}
      onError={() => setIndex((prev) => Math.min(prev + 1, candidates.length - 1))}
    />
  );
}

export default function MobileMaterialsPage() {
  const [list, setList] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [keyword, setKeyword] = useState('');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [categories, setCategories] = useState<any[]>([]);
  const [imageAssets, setImageAssets] = useState<AssetOption[]>([]);
  const [videoAssets, setVideoAssets] = useState<AssetOption[]>([]);
  const [livePacks, setLivePacks] = useState<LivePackOption[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [pickerKeyword, setPickerKeyword] = useState('');
  const [form] = Form.useForm();
  const materialType = Form.useWatch('type', form) || 'image';
  const selectedAssetId = Form.useWatch('asset_id', form);
  const selectedLivePackId = Form.useWatch('live_pack_id', form);

  const categoryOptions = useMemo(() => buildSecondLevelCategoryOptions(categories), [categories]);
  const currentAssets = useMemo(
    () => (materialType === 'video' ? videoAssets : imageAssets),
    [imageAssets, materialType, videoAssets],
  );
  const selectedAsset = useMemo(
    () => currentAssets.find((item) => item.id === Number(selectedAssetId)),
    [currentAssets, selectedAssetId],
  );
  const selectedLivePack = useMemo(
    () => livePacks.find((item) => item.id === Number(selectedLivePackId)),
    [livePacks, selectedLivePackId],
  );

  const filteredAssetOptions = useMemo(() => {
    const key = pickerKeyword.trim().toLowerCase();
    if (!key) return currentAssets;
    return currentAssets.filter((item) => item.original_name.toLowerCase().includes(key));
  }, [currentAssets, pickerKeyword]);

  const filteredLivePackOptions = useMemo(() => {
    const key = pickerKeyword.trim().toLowerCase();
    if (!key) return livePacks;
    return livePacks.filter((item) => item.base_name.toLowerCase().includes(key));
  }, [livePacks, pickerKeyword]);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (statusFilter) params.status = statusFilter;
    if (typeFilter) params.type = typeFilter;
    try {
      const { data: resp } = await mobileHttp.get('/materials', { params });
      if (resp.code === 0) {
        setList(resp.data.list || []);
        setHasMore(Boolean(resp.data.has_more));
      }
    } finally {
      setLoading(false);
    }
  }, [keyword, page, statusFilter, typeFilter]);

  const fetchCategories = useCallback(async () => {
    const { data: resp } = await mobileHttp.get('/categories');
    if (resp.code === 0) {
      setCategories(resp.data || []);
    }
  }, []);

  useEffect(() => {
    void fetchData();
  }, [fetchData]);

  useEffect(() => {
    void fetchCategories();
  }, [fetchCategories]);

  useEffect(() => {
    if (!createOpen) return;

    const loadSources = async () => {
      try {
        if (materialType === 'image') {
          const { data: resp } = await mobileHttp.get('/assets', {
            params: { page: 1, page_size: 200, file_type: 'image' },
          });
          if (resp.code === 0) {
            setImageAssets(resp.data.list || []);
          }
        }

        if (materialType === 'video') {
          const { data: resp } = await mobileHttp.get('/assets', {
            params: { page: 1, page_size: 200, file_type: 'video' },
          });
          if (resp.code === 0) {
            setVideoAssets(resp.data.list || []);
          }
        }

        if (materialType === 'live_photo') {
          const { data: resp } = await mobileHttp.get('/assets/live-packs', {
            params: { page: 1, page_size: 200 },
          });
          if (resp.code === 0) {
            const listData = (resp.data.list || [])
              .filter((item: any) => item?.status === 'complete' && item?.image_url && item?.video_url)
              .map((item: any) => ({
                id: item.id,
                base_name: item.base_name,
                image_url: item.image_url,
                image_preview_url: item.image_preview_url,
                video_url: item.video_url,
              }));
            setLivePacks(listData);
          }
        }
      } catch {
        // ignore
      }
    };

    void loadSources();
  }, [createOpen, materialType]);

  const updateStatus = async (id: number, status: 'published' | 'offline') => {
    await mobileHttp.put(`/materials/${id}`, { status });
    message.success(status === 'published' ? '素材已发布' : '素材已下线');
    void fetchData();
  };

  const updateChannel = async (
    id: number,
    field: 'show_inspiration' | 'show_moments',
    checked: boolean,
  ) => {
    await mobileHttp.put(`/materials/${id}`, { [field]: checked });
    message.success('投放设置已更新');
    void fetchData();
  };

  const createMaterial = async () => {
    const values = await form.validateFields();

    const payload: any = {
      title: values.title,
      description: values.description || '',
      type: values.type,
      category_id: Number(values.category_id) || 0,
      status: values.status || 'published',
      gender: values.gender || '',
      show_inspiration: !!values.show_inspiration,
      show_moments: !!values.show_moments,
      original_urls: [],
      thumbnail_url: '',
      preview_mov_url: '',
    };

    if (values.type === 'image') {
      const selected = imageAssets.find((item) => item.id === Number(values.asset_id));
      if (!selected) {
        message.warning('请选择图片素材源');
        return;
      }
      payload.original_urls = [selected.url];
      payload.thumbnail_url = selected.preview_url || selected.url;
    } else if (values.type === 'video') {
      const selected = videoAssets.find((item) => item.id === Number(values.asset_id));
      if (!selected) {
        message.warning('请选择视频素材源');
        return;
      }
      payload.original_urls = [selected.url];
      payload.thumbnail_url = selected.preview_url || selected.url;
    } else if (values.type === 'live_photo') {
      const selected = livePacks.find((item) => item.id === Number(values.live_pack_id));
      if (!selected) {
        message.warning('请选择Live套件');
        return;
      }
      payload.original_urls = [selected.image_url, selected.video_url].filter(Boolean);
      payload.thumbnail_url = selected.image_preview_url || selected.image_url;
      payload.preview_mov_url = selected.video_url;
    }

    setCreating(true);
    try {
      const { data: resp } = await mobileHttp.post('/materials', payload);
      if (resp.code === 0) {
        message.success('素材创建成功');
        setCreateOpen(false);
        form.resetFields();
        void fetchData();
      } else {
        message.error(resp.message || '素材创建失败');
      }
    } catch (error: any) {
      message.error(error?.response?.data?.message || '素材创建失败');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div>
      <Card size="small" style={{ marginBottom: 10 }}>
        <Space direction="vertical" style={{ width: '100%' }} size={10}>
          <Input.Search
            placeholder="搜索素材标题"
            allowClear
            onSearch={(v) => {
              setKeyword(v.trim());
              setPage(1);
            }}
          />
          <Select
            value={typeFilter || undefined}
            allowClear
            placeholder="按类型筛选"
            onChange={(v) => {
              setTypeFilter(v || '');
              setPage(1);
            }}
            options={[
              { value: 'image', label: '图片' },
              { value: 'video', label: '视频' },
              { value: 'live_photo', label: 'Live' },
            ]}
          />
          <Select
            value={statusFilter || undefined}
            allowClear
            placeholder="按状态筛选"
            onChange={(v) => {
              setStatusFilter(v || '');
              setPage(1);
            }}
            options={[
              { value: 'draft', label: '草稿' },
              { value: 'published', label: '已发布' },
              { value: 'offline', label: '已下线' },
            ]}
          />
          <Button
            type="primary"
            onClick={() => {
              form.resetFields();
              form.setFieldsValue({
                type: 'image',
                status: 'published',
                gender: '',
                show_inspiration: false,
                show_moments: false,
                asset_id: undefined,
                live_pack_id: undefined,
              });
              setCreateOpen(true);
            }}
          >
            新增素材
          </Button>
        </Space>
      </Card>

      {list.length === 0 ? (
        <Card size="small"><Empty description="暂无素材" /></Card>
      ) : (
        list.map((item) => {
          const status = statusLabels[item.status] || statusLabels.draft;
          return (
            <Card key={item.id} size="small" style={{ marginBottom: 10 }} loading={loading}>
              <div className="mobile-section-head">
                <h3 title={item.title}>{item.title || '未命名素材'}</h3>
                <Space size={6}>
                  <Tag>{typeLabels[item.type] || item.type}</Tag>
                  <Tag color={status.color}>{status.label}</Tag>
                </Space>
              </div>

              <div className="mobile-media-card__body">
                <div className="mobile-media-card__thumb">
                  <MaterialThumb item={item} />
                </div>
                <div className="mobile-media-card__meta">
                  <div className="line">ID：{item.id}</div>
                  <div className="line">分类：{item.category?.name || '-'}</div>
                  <div className="line">下载：{item.download_count || 0}</div>
                </div>
              </div>

              <div className="mobile-switch-row">
                <span>找灵感投放</span>
                <Switch
                  size="small"
                  checked={!!item.show_inspiration}
                  onChange={(checked) => {
                    void updateChannel(item.id, 'show_inspiration', checked);
                  }}
                />
              </div>
              <div className="mobile-switch-row">
                <span>朋友圈投放</span>
                <Switch
                  size="small"
                  checked={!!item.show_moments}
                  onChange={(checked) => {
                    void updateChannel(item.id, 'show_moments', checked);
                  }}
                />
              </div>

              <Space style={{ marginTop: 8 }}>
                <Button size="small" type="primary" onClick={() => void updateStatus(item.id, 'published')}>发布素材</Button>
                <Button size="small" danger onClick={() => void updateStatus(item.id, 'offline')}>下线素材</Button>
              </Space>
            </Card>
          );
        })
      )}

      <Card size="small">
        <Space style={{ width: '100%', justifyContent: 'space-between' }}>
          <Button disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>上一页</Button>
          <span style={{ color: '#7a8798', fontSize: 12 }}>第 {page} 页</span>
          <Button disabled={!hasMore} onClick={() => setPage((p) => p + 1)}>下一页</Button>
        </Space>
      </Card>

      <Modal
        title="新增素材"
        open={createOpen}
        onOk={() => void createMaterial()}
        onCancel={() => setCreateOpen(false)}
        confirmLoading={creating}
        okText="创建"
        cancelText="取消"
      >
        <Form form={form} layout="vertical">
          <Form.Item name="title" label="素材标题" rules={[{ required: true, message: '请输入素材标题' }]}> 
            <Input placeholder="请输入素材标题" maxLength={80} />
          </Form.Item>
          <Form.Item name="description" label="素材描述">
            <Input.TextArea rows={2} maxLength={200} placeholder="可选" />
          </Form.Item>
          <Form.Item name="type" label="素材类型" rules={[{ required: true, message: '请选择素材类型' }]}> 
            <Select
              onChange={() => {
                form.setFieldsValue({
                  asset_id: undefined,
                  live_pack_id: undefined,
                });
              }}
              options={[
                { value: 'image', label: '图片' },
                { value: 'video', label: '视频' },
                { value: 'live_photo', label: 'Live' },
              ]}
            />
          </Form.Item>
          <Form.Item name="category_id" label="分类（二级）" rules={[{ required: true, message: '请选择分类' }]}> 
            <Select showSearch optionFilterProp="label" options={categoryOptions} placeholder="请选择分类" />
          </Form.Item>
          <Form.Item name="status" label="状态" rules={[{ required: true, message: '请选择状态' }]}> 
            <Select
              options={[
                { value: 'draft', label: '草稿' },
                { value: 'published', label: '已发布' },
                { value: 'offline', label: '已下线' },
              ]}
            />
          </Form.Item>
          <Form.Item name="gender" label="性别">
            <Select
              options={[
                { value: '', label: '不限' },
                { value: 'male', label: '男' },
                { value: 'female', label: '女' },
              ]}
            />
          </Form.Item>

          {materialType === 'live_photo' ? (
            <>
              <Form.Item name="live_pack_id" hidden rules={[{ required: true, message: '请选择Live套件' }]}>
                <Input />
              </Form.Item>
              <Form.Item label="素材源（可视化选择）" required>
                <div className="mobile-picker-selected">
                  {selectedLivePack ? (
                    <div className="mobile-picker-selected__item">
                      <div className="mobile-picker-selected__thumb">
                        <img
                          src={toAbsoluteUrl(selectedLivePack.image_preview_url || selectedLivePack.image_url)}
                          alt={selectedLivePack.base_name}
                        />
                      </div>
                      <div className="mobile-picker-selected__meta">
                        <div className="line">{selectedLivePack.base_name}</div>
                        <div className="line">套件ID：{selectedLivePack.id}</div>
                      </div>
                    </div>
                  ) : (
                    <div className="mobile-picker-selected__empty">未选择 Live 套件</div>
                  )}
                </div>
                <Button
                  style={{ marginTop: 8 }}
                  block
                  onClick={() => {
                    setPickerKeyword('');
                    setPickerOpen(true);
                  }}
                >
                  从素材库可视化选择 Live 套件
                </Button>
              </Form.Item>
            </>
          ) : (
            <>
              <Form.Item name="asset_id" hidden rules={[{ required: true, message: '请选择素材源' }]}>
                <Input />
              </Form.Item>
              <Form.Item label="素材源（可视化选择）" required>
                <div className="mobile-picker-selected">
                  {selectedAsset ? (
                    <div className="mobile-picker-selected__item">
                      <div className="mobile-picker-selected__thumb">
                        <SourceAssetThumb asset={selectedAsset} isVideo={materialType === 'video'} />
                      </div>
                      <div className="mobile-picker-selected__meta">
                        <div className="line">{selectedAsset.original_name}</div>
                        <div className="line">素材ID：{selectedAsset.id}</div>
                      </div>
                    </div>
                  ) : (
                    <div className="mobile-picker-selected__empty">未选择素材源</div>
                  )}
                </div>
                <Button
                  style={{ marginTop: 8 }}
                  block
                  onClick={() => {
                    setPickerKeyword('');
                    setPickerOpen(true);
                  }}
                >
                  从素材库可视化选择{materialType === 'video' ? '视频' : '图片'}
                </Button>
              </Form.Item>
            </>
          )}

          <Space size={24}>
            <Form.Item name="show_inspiration" label="投放找灵感" valuePropName="checked">
              <Switch />
            </Form.Item>
            <Form.Item name="show_moments" label="投放朋友圈" valuePropName="checked">
              <Switch />
            </Form.Item>
          </Space>
        </Form>
      </Modal>

      <Modal
        title={materialType === 'live_photo' ? '选择 Live 套件' : `选择${materialType === 'video' ? '视频' : '图片'}素材`}
        open={pickerOpen}
        footer={null}
        onCancel={() => setPickerOpen(false)}
      >
        <Input.Search
          placeholder={materialType === 'live_photo' ? '搜索套件名' : '搜索素材名'}
          allowClear
          value={pickerKeyword}
          onChange={(e) => setPickerKeyword(e.target.value)}
          style={{ marginBottom: 10 }}
        />

        <div className="mobile-picker-grid">
          {materialType === 'live_photo'
            ? (
              filteredLivePackOptions.length === 0 ? (
                <div className="mobile-picker-empty">暂无可选 Live 套件</div>
              ) : filteredLivePackOptions.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  className={`mobile-picker-card ${Number(selectedLivePackId) === item.id ? 'is-selected' : ''}`}
                  onClick={() => {
                    form.setFieldValue('live_pack_id', item.id);
                    setPickerOpen(false);
                  }}
                >
                  <div className="mobile-picker-card__thumbs">
                    <div className="mobile-picker-card__thumb">
                      <img
                        src={toAbsoluteUrl(item.image_preview_url || item.image_url)}
                        alt={item.base_name}
                      />
                    </div>
                    <div className="mobile-picker-card__thumb">
                      <video src={toAbsoluteUrl(item.video_url)} muted playsInline preload="metadata" />
                    </div>
                  </div>
                  <div className="mobile-picker-card__name">{item.base_name}</div>
                  <div className="mobile-picker-card__sub">ID: {item.id}</div>
                </button>
              ))
            )
            : (
              filteredAssetOptions.length === 0 ? (
                <div className="mobile-picker-empty">暂无可选素材</div>
              ) : filteredAssetOptions.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  className={`mobile-picker-card ${Number(selectedAssetId) === item.id ? 'is-selected' : ''}`}
                  onClick={() => {
                    form.setFieldValue('asset_id', item.id);
                    setPickerOpen(false);
                  }}
                >
                  <div className="mobile-picker-card__thumb">
                    <SourceAssetThumb asset={item} isVideo={materialType === 'video'} />
                  </div>
                  <div className="mobile-picker-card__name">{item.original_name}</div>
                  <div className="mobile-picker-card__sub">ID: {item.id}</div>
                </button>
              ))
            )}
        </div>
      </Modal>
    </div>
  );
}
