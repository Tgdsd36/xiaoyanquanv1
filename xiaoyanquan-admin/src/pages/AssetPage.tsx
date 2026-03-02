import { useEffect, useState, useCallback } from 'react';
import { Upload, Button, Input, Select, Space, Spin, Empty, Pagination, Popconfirm, Modal, message } from 'antd';
import { UploadOutlined, DeleteOutlined, FolderOutlined, FolderOpenOutlined, PlusOutlined, EditOutlined, DeleteFilled } from '@ant-design/icons';
import http from '../api/http';

const API_BASE = 'http://localhost:8080';

interface Asset {
  id: number;
  filename: string;
  original_name: string;
  url: string;
  file_type: string;
  file_size: number;
  folder: string;
  created_at: string;
}

interface FolderInfo {
  folder: string;
  count: number;
}

function formatSize(bytes: number) {
  if (bytes >= 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return bytes + ' B';
}

export default function AssetPage() {
  const [assets, setAssets] = useState<Asset[]>([]);
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
    if (fileType) params.file_type = fileType;
    if (currentFolder !== null) params.folder = currentFolder;
    if (keyword) params.keyword = keyword;
    try {
      const { data: resp } = await http.get('/assets', { params });
      if (resp.code === 0) {
        setAssets(resp.data.list || []);
        setTotal(resp.data.total);
      }
    } catch { /* ignore */ }
    setLoading(false);
  }, [page, fileType, currentFolder, keyword]);

  useEffect(() => { fetchFolders(); }, [fetchFolders]);
  useEffect(() => { fetchData(); }, [fetchData]);

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

  const handleDelete = async (id: number) => {
    await http.delete(`/assets/${id}`);
    message.success('已删除');
    fetchData();
    fetchFolders();
  };

  const handleCreateFolder = async () => {
    if (!newFolderName.trim()) return;
    setNewFolderOpen(false);
    setCurrentFolder(newFolderName.trim());
    setNewFolderName('');
    setPage(1);
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
          <Upload
            showUploadList={false}
            accept="image/*,video/*"
            multiple
            beforeUpload={(file) => { handleUpload(file); return false; }}
          >
            <Button type="primary" icon={<UploadOutlined />}>上传文件</Button>
          </Upload>
          <Input.Search
            placeholder="搜索文件名"
            style={{ width: 200 }}
            allowClear
            onSearch={(v) => { setKeyword(v); setPage(1); }}
          />
          <Select
            placeholder="文件类型"
            style={{ width: 100 }}
            value={fileType || undefined}
            onChange={(v) => { setFileType(v || ''); setPage(1); }}
            allowClear
            options={[
              { value: 'image', label: '图片' },
              { value: 'video', label: '视频' },
            ]}
          />
          <span style={{ color: '#999', fontSize: 13 }}>共 {total} 个文件</span>
        </Space>

        {/* 文件网格 */}
        <div style={{ flex: 1, overflowY: 'auto' }}>
          <Spin spinning={loading}>
            {assets.length === 0 ? (
              <Empty description="暂无文件" style={{ marginTop: 60 }} />
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 10 }}>
                {assets.map((asset) => (
                  <div
                    key={asset.id}
                    style={{ border: '1px solid #e8e8e8', borderRadius: 8, overflow: 'hidden', background: '#fafafa' }}
                  >
                    <div style={{ aspectRatio: '1', overflow: 'hidden', background: '#f0f0f0' }}>
                      {asset.file_type === 'image' ? (
                        <img src={`${API_BASE}${asset.url}`} alt={asset.original_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      ) : (
                        <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 32 }}>
                          🎦
                        </div>
                      )}
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
