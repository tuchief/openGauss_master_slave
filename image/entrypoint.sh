#!/bin/bash
#set -e

# Pre-create conf directory with correct ownership so app.sh (running as omm) can write to it
# Always ensure data directories are owned by omm
# Bind mounts are created as root by Docker, run unconditionally
chown -R omm:dbgrp /opt/software/openGauss/data 2>/dev/null || true
chown -R omm:dbgrp /opt/software/openGauss/logs 2>/dev/null || true
chmod -R 0700 /opt/software/openGauss/data 2>/dev/null || true
chmod -R 0700 /opt/software/openGauss/logs 2>/dev/null || true
chown -R omm:dbgrp /docker-entrypoint-initdb.d 2>/dev/null || true
chmod -R 0700 /docker-entrypoint-initdb.d 2>/dev/null || true
mkdir -p /opt/software/openGauss/data/conf
chown omm:dbgrp /opt/software/openGauss/data/conf
chmod 0700 /opt/software/openGauss/data/conf

# -----------------------------
# 设置 ulimit（运行时生效）
# -----------------------------
ulimit -n 1000000    # 最大打开文件数
ulimit -u 65535      # 最大进程数（视需求可调）

# Ensure GAUSSHOME is correctly set for omm user
export SOFT_HOME=/opt/software
export GAUSSHOME=$SOFT_HOME/openGauss
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
export PATH=$GAUSSHOME/bin:$PATH

# MOT shim — intercepts MOT initialization to prevent crash on ARM64 Docker (NUMA detection bug)
echo "/opt/software/mot_shim.so" > /etc/ld.so.preload 2>/dev/null || true

su omm -s /bin/bash -c '/bin/bash /opt/software/app.sh'