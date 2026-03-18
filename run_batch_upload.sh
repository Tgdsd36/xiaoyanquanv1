#!/bin/bash
# 批量上传脚本 - 自动建立SSH隧道

echo "🔐 建立SSH隧道到数据库..."
echo "请输入服务器密码（root@159.75.44.225）"

# 在后台建立SSH隧道
ssh -f -N -L 15432:127.0.0.1:15432 root@159.75.44.225

if [ $? -eq 0 ]; then
    echo "✅ SSH隧道已建立"
    echo ""

    # 激活虚拟环境并运行脚本
    source venv/bin/activate
    python batch_upload_pengyou.py

    # 脚本结束后关闭SSH隧道
    echo ""
    echo "🔒 关闭SSH隧道..."
    pkill -f "ssh.*15432:127.0.0.1:15432"
    echo "✅ 完成"
else
    echo "❌ SSH隧道建立失败"
    exit 1
fi
