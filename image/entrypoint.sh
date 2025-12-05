#!/bin/bash
#set -e

if [[ ! -f "$GAUSSHOME/data/isconfig" ]]; then
    chown -R omm:dbgrp /opt/software/openGauss/data
    chown -R omm:dbgrp /opt/software/openGauss/logs
    chmod -R 0700 /opt/software/openGauss/data
    chmod -R 0700 /opt/software/openGauss/logs
    chown -R omm:dbgrp /docker-entrypoint-initdb.d
    chmod -R 0700 /docker-entrypoint-initdb.d
fi

# -----------------------------
# 设置 ulimit（运行时生效）
# -----------------------------
ulimit -n 1000000    # 最大打开文件数
ulimit -u 65535      # 最大进程数（视需求可调）

su omm -s /bin/bash -c '/bin/bash /opt/software/app.sh'