#!/bin/bash

# 设置变量
HAPROXY_DIR="./openeuler_haproxy/haproxy"

# 检查 haproxy 目录是否存在
if [ ! -d "$HAPROXY_DIR" ]; then
  echo "目录 $HAPROXY_DIR 不存在，正在克隆仓库..."

  cd $HAPROXY_DIR

  # 克隆指定分支
  git clone --branch v2.5.0 https://github.com/haproxy/haproxy.git

  # 检查克隆是否成功
  if [ $? -ne 0 ]; then
    echo "克隆失败，请检查网络连接或仓库地址是否正确。"
    exit 1
  fi

  echo "克隆成功，已下载 haproxy 源代码。"
else
  echo "目录 $HAPROXY_DIR 已存在，跳过克隆步骤。"
fi

# 继续后续操作
echo "编译环境检查完成。"