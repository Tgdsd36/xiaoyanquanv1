import { useEffect, useState, useCallback, useMemo } from 'react';
import { Table, Button, Input, Select, Space, Tag, Modal, Form, message, Popconfirm, Switch, Alert } from 'antd';
import { DeleteOutlined, PlusOutlined, SearchOutlined } from '@ant-design/icons';
import http from '../api/http';
import AssetPicker, { MultiAssetPicker } from '../components/AssetPicker';
import LivePackPicker from '../components/LivePackPicker';
import { toAbsoluteUrl } from '../utils/url';

interface LivePackEntry {
  packId?: number;
  imageUrl: string;
  videoUrl: string;
}

const VIDEO_EXTS = new Set(['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi']);
function isVideoUrl(url: string): boolean {
  const clean = url.split('?')[0];
  const dot = clean.lastIndexOf('.');
  if (dot < 0) return false;
  return VIDEO_EXTS.has(clean.substring(dot).toLowerCase());
}

/** 从素材已存储的 URL 重建 Live 套件列表 */
function reconstructLivePacks(originalUrls: string[], previewMovUrl: string): LivePackEntry[] {
  const imageUrls: string[] = [];
  const videoUrls: string[] = [];
  for (const url of originalUrls) {
    if (isVideoUrl(url)) {
      videoUrls.push(url);
    } else if (url.trim()) {
      imageUrls.push(url);
    }
  }
  if (previewMovUrl && !videoUrls.includes(previewMovUrl)) {
    videoUrls.unshift(previewMovUrl);
  }
  const count = Math.max(imageUrls.length, videoUrls.length);
  if (count === 0) return [];
  const packs: LivePackEntry[] = [];
  for (let i = 0; i < count; i++) {
    packs.push({ imageUrl: imageUrls[i] || '', videoUrl: videoUrls[i] || '' });
  }
  return packs;
}
const statusColors: Record<string, string> = { draft: 'default', published: 'green', offline: 'red' };
const statusLabels: Record<string, string> = { draft: '草稿', published: '已发布', offline: '已下线' };
const typeLabels: Record<string, string> = { image: '图片', video: '视频', live_photo: 'Live Photo' };

function buildSecondLevelCategoryOptions(categories: any[]) {
  const options: Array<{ value: number; label: string }> = [];
  categories.forEach((parent: any) => {
    const parentName = parent?.name || '';
    const children = Array.isArray(parent?.children) ? parent.children : [];
    children.forEach((child: any) => {
      if (!child || child.slug === 'male' || child.slug === 'female') return;
      options.push({
        value: child.id,
        label: parentName ? `${parentName} / ${child.name}` : child.name,
      });
    });
  });
  return options;
}

function toFullUrl(url?: string) {
  if (!url) return '';
  return toAbsoluteUrl(url);
}

function deriveHEICPreviewUrl(url?: string) {
  const raw = (url || '').trim();
  if (!raw) return '';
  const queryIndex = raw.indexOf('?');
  const base = queryIndex >= 0 ? raw.slice(0, queryIndex) : raw;
  const query = queryIndex >= 0 ? raw.slice(queryIndex) : '';
  if (!/\.hei[cf]$/i.test(base)) return '';
  return base.replace(/\.hei[cf]$/i, '_preview.jpg') + query;
}

function getMaterialImageCandidates(material: any): string[] {
  const firstOriginal = Array.isArray(material?.original_urls)
    ? material.original_urls.find((u: unknown) => typeof u === 'string' && !!u)
    : '';
  const thumbnail = typeof material?.thumbnail_url === 'string' ? material.thumbnail_url : '';
  const list = [
    deriveHEICPreviewUrl(thumbnail),
    thumbnail,
    typeof firstOriginal === 'string' ? deriveHEICPreviewUrl(firstOriginal) : '',
    typeof firstOriginal === 'string' ? firstOriginal : '',
  ].filter((v) => typeof v === 'string' && v.trim() !== '') as string[];
  return Array.from(new Set(list));
}

function MaterialThumb({ row }: { row: any }) {
  const imageCandidates = useMemo(() => getMaterialImageCandidates(row), [row]);
  const videoUrl = useMemo(() => {
    if (row?.type === 'video') {
      return Array.isArray(row?.original_urls) ? row.original_urls[0] || '' : '';
    }
    if (row?.type === 'live_photo') {
      return row?.preview_mov_url || '';
    }
    return '';
  }, [row]);
  const [imgIndex, setImgIndex] = useState(0);
  const [useVideoFallback, setUseVideoFallback] = useState(false);
  const imageKey = imageCandidates.join('|');

  useEffect(() => {
    setImgIndex(0);
    setUseVideoFallback(false);
  }, [imageKey, videoUrl, row?.id]);

  if (row?.type === 'video') {
    if (!videoUrl) return <>-</>;
    return <video src={toFullUrl(videoUrl)} style={{ width: 50, height: 50, objectFit: 'cover', borderRadius: 4 }} muted playsInline preload="metadata" />;
  }

  if (!useVideoFallback) {
    const currentImage = imageCandidates[imgIndex];
    if (currentImage) {
      return (
        <img
          src={toFullUrl(currentImage)}
          style={{ width: 50, height: 50, objectFit: 'cover', borderRadius: 4 }}
          onError={() => {
            if (imgIndex < imageCandidates.length - 1) {
              setImgIndex((prev) => prev + 1);
            } else {
              setUseVideoFallback(true);
            }
          }}
        />
      );
    }
  }

  if (videoUrl) {
    return <video src={toFullUrl(videoUrl)} style={{ width: 50, height: 50, objectFit: 'cover', borderRadius: 4 }} muted playsInline preload="metadata" />;
  }
  return <>-</>;
}

/** Live 套件卡片：多级图片回退 + 视频回退 */
function LivePackCard({
  index,
  pack,
  imageCandidates,
  onDelete,
}: {
  index: number;
  pack: LivePackEntry;
  imageCandidates: string[];
  onDelete: () => void;
}) {
  const [imgIdx, setImgIdx] = useState(0);
  const [useVideo, setUseVideo] = useState(false);
  const candidateKey = imageCandidates.join('|');

  useEffect(() => {
    setImgIdx(0);
    setUseVideo(false);
  }, [candidateKey, pack.videoUrl]);

  let preview: React.ReactNode;
  if (!useVideo && imageCandidates.length > 0) {
    const src = imageCandidates[imgIdx];
    if (src) {
      preview = (
        <img
          src={src}
          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
          onError={() => {
            if (imgIdx < imageCandidates.length - 1) {
              setImgIdx((prev) => prev + 1);
            } else {
              setUseVideo(true);
            }
          }}
        />
      );
    } else {
      preview = null;
    }
  } else if (pack.videoUrl) {
    preview = (
      <video
        src={toFullUrl(pack.videoUrl)}
        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
        muted
        playsInline
        preload="metadata"
      />
    );
  } else {
    preview = <span style={{ color: '#999', fontSize: 12 }}>无预览</span>;
  }

  return (
    <div
      style={{
        width: 180,
        border: '1px solid #e8e8e8',
        borderRadius: 8,
        overflow: 'hidden',
        position: 'relative',
        background: '#fafafa',
      }}
    >
      <div style={{ height: 100, background: '#f0f0f0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {preview}
      </div>
      <Tag
        color="blue"
        style={{ position: 'absolute', top: 6, left: 6 }}
      >
        Live #{index + 1}
      </Tag>
      <div
        onClick={onDelete}
        style={{
          position: 'absolute',
          top: 6,
          right: 6,
          width: 22,
          height: 22,
          borderRadius: '50%',
          background: 'rgba(0,0,0,0.5)',
          color: '#fff',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: 'pointer',
        }}
      >
        <DeleteOutlined style={{ fontSize: 12 }} />
      </div>
    </div>
  );
}

export default function MaterialPage() {
  const [data, setData] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [keyword, setKeyword] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editItem, setEditItem] = useState<any>(null);
  const [categories, setCategories] = useState<any[]>([]);
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);
  const [form] = Form.useForm();
  const materialType = Form.useWatch('type', form) || 'image';
  const [livePacks, setLivePacks] = useState<LivePackEntry[]>([]);
  const [messageApi, contextHolder] = message.useMessage();
  const secondLevelCategoryOptions = buildSecondLevelCategoryOptions(categories);

  useEffect(() => {
    http.get('/categories').then(({ data: resp }) => {
      if (resp.code === 0) setCategories(resp.data || []);
    });
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const params: any = { page, page_size: 20 };
    if (keyword) params.keyword = keyword;
    if (statusFilter) params.status = statusFilter;
    const { data: resp } = await http.get('/materials', { params });
    if (resp.code === 0) {
      setData(resp.data.list || []);
      setTotal(resp.data.total);
    }
    setLoading(false);
  }, [page, keyword, statusFilter]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSave = async () => {
    const isEdit = !!editItem;
    const key = isEdit ? `material-save-${editItem?.id ?? 'new'}` : 'material-create';
    try {
      await form.validateFields();
      const values = form.getFieldsValue(true);
      const payload = { ...values };
      const originalUrls = Array.isArray(payload.original_urls)
        ? payload.original_urls.filter((u: unknown) => typeof u === 'string' && !!u)
        : [];
      payload.original_urls = originalUrls;

      if (payload.type === 'video') {
        if (originalUrls.length === 0) {
          messageApi.warning('请先上传视频文件');
          return;
        }
        if (!payload.thumbnail_url) {
          payload.thumbnail_url = originalUrls[0];
        }
      } else if (payload.type === 'live_photo') {
        if (livePacks.length === 0) {
          messageApi.warning('请先选择至少一个 Live 套件');
          return;
        }
        const hasComplete = livePacks.some((p) => p.imageUrl && p.videoUrl);
        if (!hasComplete) {
          messageApi.warning('至少需要一个完整的 Live 套件（静态图 + MOV）');
          return;
        }
        // 所有 image URL + 所有 video URL 存入 original_urls
        const allImages = livePacks.map((p) => p.imageUrl).filter(Boolean);
        const allVideos = livePacks.map((p) => p.videoUrl).filter(Boolean);
        payload.original_urls = [...allImages, ...allVideos];
        payload.preview_mov_url = allVideos[0] || '';
        payload.thumbnail_url = allImages[0] || '';
      } else if (payload.type === 'image') {
        if (originalUrls.length === 0 && !payload.thumbnail_url) {
          messageApi.warning('请先上传图片素材');
          return;
        }
        if (!payload.thumbnail_url && originalUrls.length > 0) {
          payload.thumbnail_url = originalUrls[0];
        }
        payload.preview_mov_url = '';
      }

      messageApi.open({
        type: 'loading',
        content: isEdit ? '正在更新素材...' : '正在创建素材...',
        key,
        duration: 0,
      });

      if (isEdit) {
        await http.put(`/materials/${editItem.id}`, payload);
        messageApi.success({ content: '更新成功', key });
      } else {
        await http.post('/materials', payload);
        messageApi.success({ content: '创建成功', key });
      }

      setModalOpen(false);
      form.resetFields();
      setEditItem(null);
      fetchData();
    } catch (error: any) {
      if (error?.errorFields) {
        messageApi.warning('请先完善必填项');
        return;
      }
      messageApi.error({ content: isEdit ? '更新失败' : '创建失败', key });
    }
  };

  const handleDelete = async (id: number) => {
    const key = `material-delete-${id}`;
    try {
      messageApi.open({
        type: 'loading',
        content: '正在删除素材...',
        key,
        duration: 0,
      });
      await http.delete(`/materials/${id}`);
      messageApi.success({ content: '已删除', key });
      fetchData();
    } catch {
      messageApi.error({ content: '删除失败', key });
    }
  };

  const handleBatchStatus = async (status: string) => {
    const key = `material-batch-status-${status}`;
    if (!selectedRowKeys.length) { messageApi.warning('请先选择素材'); return; }
    try {
      messageApi.open({
        type: 'loading',
        content: '正在批量更新状态...',
        key,
        duration: 0,
      });
      await http.post('/materials/batch-status', { ids: selectedRowKeys.map(Number), status });
      messageApi.success({ content: '批量更新成功', key });
      setSelectedRowKeys([]);
      fetchData();
    } catch {
      messageApi.error({ content: '批量更新失败', key });
    }
  };

  const handleBatchDelete = async () => {
    const key = 'material-batch-delete';
    if (!selectedRowKeys.length) { messageApi.warning('请先选择素材'); return; }
    try {
      messageApi.open({
        type: 'loading',
        content: '正在批量删除素材...',
        key,
        duration: 0,
      });
      await http.post('/materials/batch-delete', { ids: selectedRowKeys.map(Number) });
      messageApi.success({ content: '批量删除成功', key });
      setSelectedRowKeys([]);
      fetchData();
    } catch {
      messageApi.error({ content: '批量删除失败', key });
    }
  };

  const handleBatchChannel = async (
    channel: 'inspiration' | 'moments',
    enabled: boolean,
  ) => {
    const key = `material-batch-channel-${channel}-${enabled ? 'on' : 'off'}`;
    if (!selectedRowKeys.length) { messageApi.warning('请先选择素材'); return; }
    try {
      messageApi.open({
        type: 'loading',
        content: '正在批量更新投放状态...',
        key,
        duration: 0,
      });
      await http.post('/materials/batch-channel', {
        ids: selectedRowKeys.map(Number),
        channel,
        enabled,
      });
      const channelName = channel === 'inspiration' ? '找灵感' : '朋友圈';
      messageApi.success({
        content: enabled ? `已批量投放到${channelName}` : `已批量从${channelName}移除`,
        key,
      });
      setSelectedRowKeys([]);
      fetchData();
    } catch {
      messageApi.error({ content: '批量渠道操作失败', key });
    }
  };

  const handleToggleChannel = async (
    row: any,
    field: 'show_inspiration' | 'show_moments',
    checked: boolean,
  ) => {
    const key = `material-toggle-channel-${row.id}-${field}`;
    try {
      messageApi.open({
        type: 'loading',
        content: '正在更新投放状态...',
        key,
        duration: 0,
      });
      await http.put(`/materials/${row.id}`, { [field]: checked });
      const channelName = field === 'show_inspiration' ? '找灵感' : '朋友圈';
      messageApi.success({
        content: checked ? `已投放到${channelName}` : `已从${channelName}移除`,
        key,
      });
      fetchData();
    } catch {
      messageApi.error({ content: '更新投放状态失败', key });
    }
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    {
      title: '缩略图', width: 80,
      render: (_: unknown, row: any) => {
        return <MaterialThumb row={row} />;
      },
    },
    { title: '标题', dataIndex: 'title', ellipsis: true },
    { title: '类型', dataIndex: 'type', width: 90, render: (t: string) => typeLabels[t] || t },
    { title: '分类', dataIndex: ['category', 'name'], width: 90 },
    { title: '性别', dataIndex: 'gender', width: 80, render: (v: string) => v === 'male' ? '男' : v === 'female' ? '女' : '不限' },
    {
      title: '状态', dataIndex: 'status', width: 80,
      render: (s: string) => <Tag color={statusColors[s]}>{statusLabels[s] || s}</Tag>,
    },
    { title: '下载', dataIndex: 'download_count', width: 60 },
    {
      title: '操作', width: 260,
      render: (_: any, row: any) => (
        <Space direction="vertical" size={6}>
          <Space size={10}>
            <span style={{ fontSize: 12, color: '#666' }}>找灵感</span>
            <Switch
              size="small"
              checked={!!row.show_inspiration}
              onChange={(checked) => handleToggleChannel(row, 'show_inspiration', checked)}
            />
            <span style={{ fontSize: 12, color: '#666' }}>朋友圈</span>
            <Switch
              size="small"
              checked={!!row.show_moments}
              onChange={(checked) => handleToggleChannel(row, 'show_moments', checked)}
            />
          </Space>
          <Space>
          <Button size="small" onClick={() => {
              setEditItem(row);
              form.setFieldsValue({
                ...row,
                show_inspiration: !!row.show_inspiration,
                show_moments: !!row.show_moments,
              });
              // 重建 Live 套件列表
              if (row.type === 'live_photo') {
                const urls = Array.isArray(row.original_urls) ? row.original_urls : [];
                setLivePacks(reconstructLivePacks(urls, row.preview_mov_url || ''));
              } else {
                setLivePacks([]);
              }
              setModalOpen(true);
            }}
            >
              编辑
            </Button>
            <Popconfirm title="确认删除？" onConfirm={() => handleDelete(row.id)}>
              <Button size="small" danger>删除</Button>
            </Popconfirm>
          </Space>
        </Space>
      ),
    },
  ];

  return (
    <>
      {contextHolder}
      <Space style={{ marginBottom: 16 }} wrap>
        <Input placeholder="搜索标题" prefix={<SearchOutlined />} value={keyword} onChange={(e) => { setKeyword(e.target.value); setPage(1); }} allowClear />
        <Select placeholder="状态筛选" style={{ width: 120 }} value={statusFilter || undefined} onChange={(v) => { setStatusFilter(v || ''); setPage(1); }} allowClear
          options={[{ value: 'draft', label: '草稿' }, { value: 'published', label: '已发布' }, { value: 'offline', label: '已下线' }]}
        />
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={() => {
            setEditItem(null);
            form.resetFields();
            form.setFieldsValue({
              type: 'image',
              status: 'published',
              gender: '',
              preview_mov_url: '',
              show_inspiration: false,
              show_moments: false,
            });
            setLivePacks([]);
            setModalOpen(true);
          }}
        >
          新增素材
        </Button>
        {selectedRowKeys.length > 0 && (
          <>
            <span>已选 {selectedRowKeys.length} 项</span>
            <Button onClick={() => handleBatchStatus('published')}>批量发布</Button>
            <Button onClick={() => handleBatchStatus('offline')}>批量下线</Button>
            <Button onClick={() => handleBatchChannel('inspiration', true)}>批量投放找灵感</Button>
            <Button onClick={() => handleBatchChannel('inspiration', false)}>批量取消找灵感</Button>
            <Button onClick={() => handleBatchChannel('moments', true)}>批量投放朋友圈</Button>
            <Button onClick={() => handleBatchChannel('moments', false)}>批量取消朋友圈</Button>
            <Popconfirm title={`确认删除这 ${selectedRowKeys.length} 项？`} onConfirm={handleBatchDelete}>
              <Button danger>批量删除</Button>
            </Popconfirm>
          </>
        )}
      </Space>
      {selectedRowKeys.length > 0 && (
        <Alert
          style={{ marginBottom: 12 }}
          type="info"
          showIcon
          message={`已选择 ${selectedRowKeys.length} 个素材，可执行批量发布/下线、批量投放或取消找灵感和朋友圈。`}
          description="批量渠道操作会立即生效，请确认后再执行。"
        />
      )}

      <Table rowKey="id" columns={columns} dataSource={data} loading={loading}
        rowSelection={{ selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) }}
        pagination={{ current: page, total, pageSize: 20, onChange: setPage }} scroll={{ x: 1100 }}
      />

      <Modal title={editItem ? '编辑素材' : '新增素材'} open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)} width={640}>
        <Form form={form} layout="vertical" initialValues={{ status: 'published', gender: '', show_inspiration: false, show_moments: false }}>
          <Form.Item name="title" label="标题" rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="description" label="描述"><Input.TextArea rows={2} /></Form.Item>
          <Space>
            <Form.Item name="type" label="类型" rules={[{ required: true }]}>
              <Select
                style={{ width: 120 }}
                onChange={() => {
                  form.setFieldsValue({
                    original_urls: [],
                    preview_mov_url: '',
                    thumbnail_url: '',
                  });
                  setLivePacks([]);
                }}
                options={[{ value: 'image', label: '图片' }, { value: 'video', label: '视频' }, { value: 'live_photo', label: 'Live Photo' }]}
              />
            </Form.Item>
            <Form.Item name="category_id" label="分类" rules={[{ required: true, message: '请选择分类' }]}>
              <Select
                style={{ width: 200 }}
                placeholder="选择二级分类"
                allowClear
                notFoundContent="请先在分类管理中创建二级分类"
                options={secondLevelCategoryOptions}
              />
            </Form.Item>
            <Form.Item name="gender" label="性别">
              <Select style={{ width: 120 }}
                options={[
                  { value: '', label: '不限' },
                  { value: 'male', label: '男' },
                  { value: 'female', label: '女' },
                ]}
              />
            </Form.Item>
            <Form.Item name="status" label="状态" rules={[{ required: true, message: '请选择状态' }]}>
              <Select style={{ width: 120 }} options={[{ value: 'draft', label: '草稿' }, { value: 'published', label: '已发布' }, { value: 'offline', label: '已下线' }]} />
            </Form.Item>
          </Space>
          {materialType === 'video' ? (
            <Alert
              style={{ marginBottom: 12 }}
              type="info"
              showIcon
              message="视频封面将自动使用视频文件预览，无需单独上传封面图片。"
            />
          ) : materialType === 'live_photo' ? (
            <Alert
              style={{ marginBottom: 12 }}
              type="info"
              showIcon
              message="支持添加多个 Live 套件，所有图片和视频将一并保存。封面自动使用第一张静态图。"
              description="iPhone 可查看动效，Android 将展示静态图。"
            />
          ) : (
            <Form.Item name="thumbnail_url" label="缩略图">
              <AssetPicker fileType="image" />
            </Form.Item>
          )}
          {materialType === 'video' ? (
            <Form.Item name="original_urls" label="视频文件（最多1个）">
              <MultiAssetPicker max={1} fileType="video" />
            </Form.Item>
          ) : materialType === 'live_photo' ? (
            <>
              <Form.Item name="original_urls" hidden><Input /></Form.Item>
              <Form.Item name="preview_mov_url" hidden><Input /></Form.Item>
              <Form.Item name="thumbnail_url" hidden><Input /></Form.Item>
              {/* 封面预览 */}
              {editItem && editItem.thumbnail_url && (
                <Form.Item label="当前封面">
                  <MaterialThumb row={editItem} />
                </Form.Item>
              )}
              <Form.Item label={`Live 套件（${livePacks.length} 个）`}>
                <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'flex-start' }}>
                  {livePacks.map((pack, idx) => {
                    // 构建多级回退的预览候选列表
                    const candidates: string[] = [];
                    if (pack.imageUrl) {
                      const heicPreview = deriveHEICPreviewUrl(pack.imageUrl);
                      if (heicPreview) candidates.push(toFullUrl(heicPreview));
                      candidates.push(toFullUrl(pack.imageUrl));
                    }
                    return (
                      <LivePackCard
                        key={`${pack.imageUrl}-${pack.videoUrl}-${idx}`}
                        index={idx}
                        pack={pack}
                        imageCandidates={candidates}
                        onDelete={() => setLivePacks((prev) => prev.filter((_, i) => i !== idx))}
                      />
                    );
                  })}
                  {/* 添加按钮 */}
                  <LivePackPicker
                    onChange={(value) => {
                      if (!value) return;
                      setLivePacks((prev) => [
                        ...prev,
                        { packId: value.packId, imageUrl: value.imageUrl, videoUrl: value.videoUrl },
                      ]);
                    }}
                  />
                </div>
              </Form.Item>
            </>
          ) : (
            <Form.Item name="original_urls" label="原图（最多9张）">
              <MultiAssetPicker max={9} fileType="image" />
            </Form.Item>
          )}
          <Form.Item name="tags" label="标签">
            <Select
              mode="tags"
              style={{ width: '100%' }}
              placeholder="输入标签后按回车添加"
              tokenSeparators={[',', '，', ' ']}
            />
          </Form.Item>
          <Space size={32}>
            <Form.Item name="show_inspiration" label="投放找灵感" valuePropName="checked">
              <Switch />
            </Form.Item>
            <Form.Item name="show_moments" label="投放朋友圈" valuePropName="checked">
              <Switch />
            </Form.Item>
          </Space>
        </Form>
      </Modal>
    </>
  );
}
