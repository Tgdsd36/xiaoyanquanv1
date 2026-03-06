import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ClearOutlined, PlayCircleOutlined, ReloadOutlined, StopOutlined, UploadOutlined } from '@ant-design/icons';
import { Button, Card, message, Progress, Select, Space, Switch, Tag, Typography, Upload } from 'antd';
import type { AxiosProgressEvent } from 'axios';
import type { RcFile, UploadProps } from 'antd/es/upload';
import { useNavigate } from 'react-router-dom';
import mobileHttp from '../api/mobileHttp';
import './MobileUploadPage.css';

type UploadMode = 'all' | 'image' | 'video' | 'live';
type QueueItemType = 'image' | 'video' | 'live';
type QueueItemStatus = 'pending' | 'uploading' | 'success' | 'error' | 'canceled' | 'blocked';

interface FolderInfo {
  folder: string;
  count: number;
}

interface SourceFile {
  key: string;
  file: File;
  name: string;
  ext: string;
  baseName: string;
}

interface QueueItem {
  id: string;
  label: string;
  type: QueueItemType;
  status: QueueItemStatus;
  progress: number;
  loaded: number;
  total: number;
  attempt: number;
  maxAttempts: number;
  errorMessage: string;
  sourceKeys: string[];
  singleFile?: SourceFile;
  liveImageFile?: SourceFile;
  liveVideoFile?: SourceFile;
  missingParts?: Array<'image' | 'video'>;
}

interface BuildQueueResult {
  items: QueueItem[];
  ignoredCount: number;
  blockedCount: number;
}

const IMAGE_EXTS = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif']);
const VIDEO_EXTS = new Set(['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm']);
const LIVE_IMAGE_EXTS = new Set(['heic', 'heif']);
const LIVE_VIDEO_EXTS = new Set(['mov']);

const modeOptions: Array<{ value: UploadMode; label: string }> = [
  { value: 'all', label: '全部（图片/视频/Live）' },
  { value: 'image', label: '仅图片' },
  { value: 'video', label: '仅视频' },
  { value: 'live', label: '仅Live套件' },
];

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

function isImageExt(ext: string): boolean {
  return IMAGE_EXTS.has(ext);
}

function isVideoExt(ext: string): boolean {
  return VIDEO_EXTS.has(ext);
}

function isLiveImageExt(ext: string): boolean {
  return LIVE_IMAGE_EXTS.has(ext);
}

function isLiveVideoExt(ext: string): boolean {
  return LIVE_VIDEO_EXTS.has(ext);
}

function formatSize(bytes: number): string {
  if (bytes <= 0) return '0B';
  if (bytes >= 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024 / 1024).toFixed(2)}GB`;
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${bytes}B`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

function isCanceledError(error: unknown): boolean {
  const maybe = error as { code?: string; name?: string; message?: string };
  return maybe?.code === 'ERR_CANCELED' || maybe?.name === 'CanceledError';
}

function extractErrorMessage(error: unknown): string {
  const respMessage = (error as { response?: { data?: { message?: string } } })?.response?.data?.message;
  if (respMessage) return respMessage;
  const msg = (error as { message?: string })?.message;
  if (msg) return msg;
  return '上传失败';
}

function buildQueueItems(sourceFiles: SourceFile[], mode: UploadMode, strictLive: boolean, maxAttempts: number): BuildQueueResult {
  const items: QueueItem[] = [];
  let ignoredCount = 0;

  const pushSingle = (file: SourceFile, type: 'image' | 'video') => {
    items.push({
      id: `single-${file.key}`,
      label: file.name,
      type,
      status: 'pending',
      progress: 0,
      loaded: 0,
      total: file.file.size,
      attempt: 0,
      maxAttempts,
      errorMessage: '',
      sourceKeys: [file.key],
      singleFile: file,
    });
  };

  const pushLive = (
    baseName: string,
    imageFile: SourceFile | undefined,
    videoFile: SourceFile | undefined,
    blocked: boolean,
  ) => {
    const missingParts: Array<'image' | 'video'> = [];
    if (!imageFile) missingParts.push('image');
    if (!videoFile) missingParts.push('video');

    items.push({
      id: `live-${baseName}-${imageFile?.key ?? 'none'}-${videoFile?.key ?? 'none'}`,
      label: baseName,
      type: 'live',
      status: blocked ? 'blocked' : 'pending',
      progress: 0,
      loaded: 0,
      total: (imageFile?.file.size ?? 0) + (videoFile?.file.size ?? 0),
      attempt: 0,
      maxAttempts,
      errorMessage: blocked ? `缺少${missingParts.includes('image') ? ' HEIC' : ''}${missingParts.length === 2 ? ' 和' : ''}${missingParts.includes('video') ? ' MOV' : ''}` : '',
      sourceKeys: [imageFile?.key, videoFile?.key].filter((v): v is string => !!v),
      liveImageFile: imageFile,
      liveVideoFile: videoFile,
      missingParts,
    });
  };

  const liveCandidates = sourceFiles.filter((file) => isLiveImageExt(file.ext) || isLiveVideoExt(file.ext));
  const usedKeys = new Set<string>();

  if (mode === 'all' || mode === 'live') {
    const grouped = new Map<string, { images: SourceFile[]; videos: SourceFile[] }>();

    liveCandidates.forEach((file) => {
      const bucket = grouped.get(file.baseName) ?? { images: [], videos: [] };
      if (isLiveImageExt(file.ext)) bucket.images.push(file);
      if (isLiveVideoExt(file.ext)) bucket.videos.push(file);
      grouped.set(file.baseName, bucket);
    });

    grouped.forEach((bucket, baseName) => {
      const imageList = [...bucket.images];
      const videoList = [...bucket.videos];
      const pairCount = Math.min(imageList.length, videoList.length);

      for (let idx = 0; idx < pairCount; idx += 1) {
        const image = imageList[idx];
        const video = videoList[idx];
        usedKeys.add(image.key);
        usedKeys.add(video.key);
        pushLive(baseName, image, video, false);
      }

      if (mode === 'live') {
        const remainImages = imageList.slice(pairCount);
        const remainVideos = videoList.slice(pairCount);

        remainImages.forEach((img) => {
          usedKeys.add(img.key);
          pushLive(baseName, img, undefined, strictLive);
        });

        remainVideos.forEach((mov) => {
          usedKeys.add(mov.key);
          pushLive(baseName, undefined, mov, strictLive);
        });
      }
    });
  }

  sourceFiles.forEach((file) => {
    if (usedKeys.has(file.key)) return;

    if (mode === 'live') {
      if (isLiveImageExt(file.ext) || isLiveVideoExt(file.ext)) {
        if (strictLive) {
          pushLive(file.baseName, isLiveImageExt(file.ext) ? file : undefined, isLiveVideoExt(file.ext) ? file : undefined, true);
        } else {
          pushLive(file.baseName, isLiveImageExt(file.ext) ? file : undefined, isLiveVideoExt(file.ext) ? file : undefined, false);
        }
      } else {
        ignoredCount += 1;
      }
      return;
    }

    if (mode === 'image') {
      if (isImageExt(file.ext)) {
        pushSingle(file, 'image');
      } else {
        ignoredCount += 1;
      }
      return;
    }

    if (mode === 'video') {
      if (isVideoExt(file.ext)) {
        pushSingle(file, 'video');
      } else {
        ignoredCount += 1;
      }
      return;
    }

    if (mode === 'all') {
      if (isImageExt(file.ext)) {
        pushSingle(file, 'image');
        return;
      }
      if (isVideoExt(file.ext)) {
        pushSingle(file, 'video');
        return;
      }
      ignoredCount += 1;
    }
  });

  const blockedCount = items.filter((item) => item.status === 'blocked').length;
  return { items, ignoredCount, blockedCount };
}

const { Text } = Typography;

export default function MobileUploadPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<UploadMode>('all');
  const [folder, setFolder] = useState<string>('');
  const [strictLive, setStrictLive] = useState(true);
  const [autoRetry, setAutoRetry] = useState(true);
  const [sourceFiles, setSourceFiles] = useState<SourceFile[]>([]);
  const [queue, setQueue] = useState<QueueItem[]>([]);
  const [folders, setFolders] = useState<FolderInfo[]>([]);
  const [uploading, setUploading] = useState(false);
  const [ignoredCount, setIgnoredCount] = useState(0);
  const [blockedCount, setBlockedCount] = useState(0);

  const queueRef = useRef<QueueItem[]>([]);
  const controllersRef = useRef<Map<string, AbortController>>(new Map());
  const stopRequestedRef = useRef(false);

  const applyQueue = useCallback((updater: (prev: QueueItem[]) => QueueItem[]) => {
    setQueue((prev) => {
      const next = updater(prev);
      queueRef.current = next;
      return next;
    });
  }, []);

  const replaceQueue = useCallback((next: QueueItem[]) => {
    queueRef.current = next;
    setQueue(next);
  }, []);

  const patchQueueItem = useCallback((id: string, patcher: (item: QueueItem) => QueueItem) => {
    applyQueue((prev) => prev.map((item) => (item.id === id ? patcher(item) : item)));
  }, [applyQueue]);

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

  useEffect(() => {
    void fetchFolders();
  }, [fetchFolders]);

  useEffect(() => {
    const maxAttempts = autoRetry ? 2 : 1;
    const result = buildQueueItems(sourceFiles, mode, strictLive, maxAttempts);
    replaceQueue(result.items);
    setIgnoredCount(result.ignoredCount);
    setBlockedCount(result.blockedCount);
  }, [autoRetry, mode, replaceQueue, sourceFiles, strictLive]);

  const folderOptions = useMemo(
    () => [
      { value: '', label: '未分类' },
      ...folders.filter((item) => !!item.folder).map((item) => ({ value: item.folder, label: item.folder })),
    ],
    [folders],
  );

  const acceptedExt = useMemo(() => {
    if (mode === 'image') return 'image/*,.heic,.heif';
    if (mode === 'video') return 'video/*,.mov,.mp4,.m4v,.avi,.mkv,.webm';
    if (mode === 'live') return '.heic,.heif,.mov';
    return 'image/*,video/*,.heic,.heif,.mov,.mp4,.m4v,.avi,.mkv,.webm';
  }, [mode]);

  const summary = useMemo(() => {
    const stats = {
      pending: 0,
      uploading: 0,
      success: 0,
      error: 0,
      canceled: 0,
      blocked: 0,
    };

    queue.forEach((item) => {
      stats[item.status] += 1;
    });

    return stats;
  }, [queue]);

  const beforePickFile: UploadProps['beforeUpload'] = (rawFile) => {
    if (uploading) {
      message.warning('上传进行中，请先取消再添加文件');
      return Upload.LIST_IGNORE;
    }

    const file = rawFile as RcFile;
    const ext = getFileExt(file.name);
    const key = `${file.name}-${file.size}-${file.lastModified}`;

    setSourceFiles((prev) => {
      if (prev.some((item) => item.key === key)) {
        return prev;
      }
      return [
        ...prev,
        {
          key,
          file,
          name: file.name,
          ext,
          baseName: normalizeBaseName(file.name),
        },
      ];
    });

    return false;
  };

  const clearSourceFiles = () => {
    if (uploading) return;
    setSourceFiles([]);
    replaceQueue([]);
    setIgnoredCount(0);
    setBlockedCount(0);
  };

  const uploadSinglePart = useCallback(async (params: {
    queueId: string;
    part: 'single' | 'live_image' | 'live_video';
    file: File;
    folderValue: string;
    liveRole?: 'image' | 'video';
    onProgress: (loaded: number) => void;
  }) => {
    const { queueId, part, file, folderValue, liveRole, onProgress } = params;
    const formData = new FormData();
    formData.append('file', file);
    if (folderValue) formData.append('folder', folderValue);
    if (liveRole) formData.append('live_role', liveRole);

    const controllerKey = `${queueId}-${part}`;
    const controller = new AbortController();
    controllersRef.current.set(controllerKey, controller);

    try {
      const { data: resp } = await mobileHttp.post('/assets/upload', formData, {
        signal: controller.signal,
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: (evt: AxiosProgressEvent) => {
          const total = evt.total && evt.total > 0 ? evt.total : file.size;
          const loaded = Math.min(evt.loaded ?? 0, total);
          onProgress(loaded);
        },
      });

      if (resp.code !== 0) {
        throw new Error(resp.message || '上传失败');
      }
    } finally {
      controllersRef.current.delete(controllerKey);
    }
  }, []);

  const executeItemOnce = useCallback(async (item: QueueItem, folderValue: string) => {
    if (item.type === 'live') {
      const totalBytes = Math.max(item.total, 1);
      const imageTotal = item.liveImageFile?.file.size ?? 0;
      const videoTotal = item.liveVideoFile?.file.size ?? 0;
      let imageLoaded = 0;
      let videoLoaded = 0;

      if (item.liveImageFile) {
        await uploadSinglePart({
          queueId: item.id,
          part: 'live_image',
          file: item.liveImageFile.file,
          folderValue,
          liveRole: 'image',
          onProgress: (loaded) => {
            imageLoaded = loaded;
            const loadedBytes = Math.min(imageLoaded, imageTotal) + Math.min(videoLoaded, videoTotal);
            const percent = Math.min(100, Math.round((loadedBytes / totalBytes) * 100));
            patchQueueItem(item.id, (prev) => ({ ...prev, loaded: loadedBytes, progress: percent }));
          },
        });
      }

      if (item.liveVideoFile) {
        await uploadSinglePart({
          queueId: item.id,
          part: 'live_video',
          file: item.liveVideoFile.file,
          folderValue,
          liveRole: 'video',
          onProgress: (loaded) => {
            videoLoaded = loaded;
            const loadedBytes = Math.min(imageLoaded, imageTotal) + Math.min(videoLoaded, videoTotal);
            const percent = Math.min(100, Math.round((loadedBytes / totalBytes) * 100));
            patchQueueItem(item.id, (prev) => ({ ...prev, loaded: loadedBytes, progress: percent }));
          },
        });
      }

      patchQueueItem(item.id, (prev) => ({ ...prev, loaded: prev.total, progress: 100 }));
      return;
    }

    const source = item.singleFile;
    if (!source) throw new Error('缺少上传文件');

    const totalBytes = Math.max(item.total, 1);
    await uploadSinglePart({
      queueId: item.id,
      part: 'single',
      file: source.file,
      folderValue,
      onProgress: (loaded) => {
        const loadedBytes = Math.min(loaded, source.file.size);
        const percent = Math.min(100, Math.round((loadedBytes / totalBytes) * 100));
        patchQueueItem(item.id, (prev) => ({ ...prev, loaded: loadedBytes, progress: percent }));
      },
    });

    patchQueueItem(item.id, (prev) => ({ ...prev, loaded: prev.total, progress: 100 }));
  }, [patchQueueItem, uploadSinglePart]);

  const runQueueItem = useCallback(async (itemId: string, folderValue: string) => {
    const current = queueRef.current.find((item) => item.id === itemId);
    if (!current || current.status !== 'pending') return;

    for (let attempt = 1; attempt <= current.maxAttempts; attempt += 1) {
      if (stopRequestedRef.current) {
        patchQueueItem(itemId, (item) => ({ ...item, status: 'canceled', errorMessage: '已取消上传' }));
        return;
      }

      patchQueueItem(itemId, (item) => ({
        ...item,
        status: 'uploading',
        attempt,
        errorMessage: '',
        loaded: 0,
        progress: 0,
      }));

      const snapshot = queueRef.current.find((item) => item.id === itemId);
      if (!snapshot) return;

      try {
        await executeItemOnce(snapshot, folderValue);
        patchQueueItem(itemId, (item) => ({ ...item, status: 'success', errorMessage: '' }));
        return;
      } catch (error) {
        if (isCanceledError(error) || stopRequestedRef.current) {
          patchQueueItem(itemId, (item) => ({ ...item, status: 'canceled', errorMessage: '已取消上传' }));
          return;
        }

        if (attempt < current.maxAttempts) {
          patchQueueItem(itemId, (item) => ({
            ...item,
            status: 'pending',
            loaded: 0,
            progress: 0,
            errorMessage: `上传失败，${Math.ceil(1.2 * attempt)} 秒后重试`,
          }));
          await sleep(1200 * attempt);
          continue;
        }

        const msg = extractErrorMessage(error);
        patchQueueItem(itemId, (item) => ({ ...item, status: 'error', errorMessage: msg }));
      }
    }
  }, [executeItemOnce, patchQueueItem]);

  const startUpload = useCallback(async () => {
    if (uploading) return;

    const pendingItems = queueRef.current.filter((item) => item.status === 'pending');
    if (pendingItems.length === 0) {
      message.info('没有可上传的队列项');
      return;
    }

    stopRequestedRef.current = false;
    setUploading(true);

    const ids = pendingItems.map((item) => item.id);
    let cursor = 0;
    const workerCount = Math.min(3, ids.length);
    const folderValue = folder;

    const workers = Array.from({ length: workerCount }).map(async () => {
      while (!stopRequestedRef.current) {
        if (cursor >= ids.length) break;
        const index = cursor;
        cursor += 1;
        const itemId = ids[index];
        await runQueueItem(itemId, folderValue);
      }
    });

    await Promise.all(workers);
    setUploading(false);

    const finalQueue = queueRef.current;
    const successCount = finalQueue.filter((item) => item.status === 'success').length;
    const errorCount = finalQueue.filter((item) => item.status === 'error').length;
    const canceledCount = finalQueue.filter((item) => item.status === 'canceled').length;

    if (errorCount > 0) {
      message.warning(`上传完成：成功 ${successCount}，失败 ${errorCount}，取消 ${canceledCount}`);
    } else {
      message.success(`上传完成：成功 ${successCount}，取消 ${canceledCount}`);
    }

    void fetchFolders();
  }, [fetchFolders, folder, runQueueItem, uploading]);

  const cancelUpload = () => {
    stopRequestedRef.current = true;
    controllersRef.current.forEach((controller) => controller.abort());
    controllersRef.current.clear();

    applyQueue((prev) => prev.map((item) => (
      item.status === 'pending' || item.status === 'uploading'
        ? { ...item, status: 'canceled', errorMessage: '已取消上传' }
        : item
    )));

    setUploading(false);
    message.info('已取消上传');
  };

  const retryFailed = () => {
    if (uploading) return;

    let hasRetry = false;
    applyQueue((prev) => prev.map((item) => {
      if (item.status === 'error' || item.status === 'canceled') {
        hasRetry = true;
        return {
          ...item,
          status: item.status === 'canceled' ? 'pending' : 'pending',
          progress: 0,
          loaded: 0,
          attempt: 0,
          errorMessage: '',
        };
      }
      return item;
    }));

    if (hasRetry) {
      message.success('失败项已重置，可重新开始上传');
    } else {
      message.info('没有失败或取消项可重试');
    }
  };

  return (
    <div className="mobile-upload-page">
      <Card className="mobile-upload-card" bordered={false}>
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <div>
            <div className="mobile-upload-label">上传模式</div>
            <Select
              value={mode}
              onChange={(value) => setMode(value)}
              options={modeOptions}
              disabled={uploading}
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
              disabled={uploading}
            />
          </div>

          <div className="mobile-upload-switch-row">
            <div className="mobile-upload-switch-item">
              <span>Live严格模式</span>
              <Switch checked={strictLive} onChange={setStrictLive} disabled={uploading || mode !== 'live'} />
            </div>
            <div className="mobile-upload-switch-item">
              <span>失败自动重试1次</span>
              <Switch checked={autoRetry} onChange={setAutoRetry} disabled={uploading} />
            </div>
          </div>

          <Upload
            multiple
            accept={acceptedExt}
            showUploadList={false}
            beforeUpload={beforePickFile}
            disabled={uploading}
          >
            <Button block type="primary" icon={<UploadOutlined />} size="large" disabled={uploading}>
              选择文件加入队列
            </Button>
          </Upload>

          <div className="mobile-upload-toolbar">
            <Button icon={<ClearOutlined />} onClick={clearSourceFiles} disabled={uploading || sourceFiles.length === 0}>
              清空队列
            </Button>
            <Button icon={<ReloadOutlined />} onClick={retryFailed} disabled={uploading}>
              重试失败
            </Button>
            <Button type="primary" icon={<PlayCircleOutlined />} onClick={() => void startUpload()} disabled={uploading || summary.pending === 0}>
              开始上传
            </Button>
            <Button danger icon={<StopOutlined />} onClick={cancelUpload} disabled={!uploading}>
              取消上传
            </Button>
          </div>

          <div className="mobile-upload-metrics">
            <Tag color="default">源文件 {sourceFiles.length}</Tag>
            <Tag color="processing">待上传 {summary.pending}</Tag>
            <Tag color="success">成功 {summary.success}</Tag>
            <Tag color="error">失败 {summary.error}</Tag>
            <Tag color="warning">阻塞 {summary.blocked}</Tag>
            {ignoredCount > 0 && <Tag color="magenta">忽略 {ignoredCount}</Tag>}
            {blockedCount > 0 && <Tag color="gold">缺配对 {blockedCount}</Tag>}
          </div>

          <Text className="mobile-upload-note">
            说明：Live 套件按 HEIC/HEIF + MOV 自动配对；严格模式下，缺少任一文件会阻塞上传。
          </Text>
          <Button
            type="link"
            style={{ padding: 0, height: 'auto', justifyContent: 'flex-start' }}
            onClick={() => navigate('/mobile/live-debug')}
          >
            未识别为 Live？打开 Live 诊断页查看手机实际上传内容
          </Button>
        </Space>
      </Card>

      <Card className="mobile-upload-card" title="上传队列" bordered={false}>
        <div className="mobile-upload-queue">
          {queue.length === 0 ? (
            <div className="mobile-upload-empty">暂无队列项，请先选择文件</div>
          ) : (
            queue.map((item) => {
              const statusColor = item.status === 'success'
                ? 'green'
                : item.status === 'error'
                  ? 'red'
                  : item.status === 'uploading'
                    ? 'processing'
                    : item.status === 'blocked'
                      ? 'gold'
                      : item.status === 'canceled'
                        ? 'default'
                        : 'blue';

              const statusText = item.status === 'success'
                ? '成功'
                : item.status === 'error'
                  ? '失败'
                  : item.status === 'uploading'
                    ? '上传中'
                    : item.status === 'blocked'
                      ? '阻塞'
                      : item.status === 'canceled'
                        ? '已取消'
                        : '待上传';

              const typeText = item.type === 'live' ? 'Live套件' : item.type === 'image' ? '图片' : '视频';
              const missingLabel = item.missingParts?.length
                ? `缺少 ${item.missingParts.includes('image') ? 'HEIC' : ''}${item.missingParts.length === 2 ? ' + ' : ''}${item.missingParts.includes('video') ? 'MOV' : ''}`
                : '';

              return (
                <div key={item.id} className="mobile-upload-queue-item">
                  <div className="mobile-upload-queue-head">
                    <div className="mobile-upload-queue-title">{item.label}</div>
                    <Space size={6}>
                      <Tag>{typeText}</Tag>
                      <Tag color={statusColor}>{statusText}</Tag>
                    </Space>
                  </div>

                  <Progress percent={item.progress} size="small" status={item.status === 'error' ? 'exception' : 'normal'} />

                  <div className="mobile-upload-queue-meta">
                    <span>{formatSize(item.loaded)} / {formatSize(item.total)}</span>
                    <span>尝试 {item.attempt}/{item.maxAttempts}</span>
                  </div>

                  {(item.errorMessage || missingLabel) && (
                    <div className="mobile-upload-queue-error">
                      {item.errorMessage || missingLabel}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </Card>
    </div>
  );
}
