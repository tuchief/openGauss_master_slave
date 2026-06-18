# openGauss HA Cluster - 使用文档

## 架构

```
etcd Cluster (3 节点) ← Patroni DCS API ── openGauss + Patroni Cluster (3 节点)
┌──────────────┐                              ┌──────────────┐
│   etcd-a1    │                              │   master     │
│   etcd-b1    │  ← WAL stream ────────────── │   slave01    │
│   etcd-c1    │                              │   slave02    │
└──────────────┘                              └──────────────┘
```

- **etcd**: 分布式一致性存储，Patroni 依赖 etcd 进行选主和状态管理
- **Patroni**: 负责自动故障切换和集群管理
- **openGauss**: 数据库内核，支持同步/异步流复制

## 前提条件

- Docker Desktop (macOS) 或 Docker Engine (Linux)
- ARM64 架构（当前镜像为 ARM64 构建）
- 磁盘空间: 每个节点约 2GB

## 部署形态

openGauss 镜像和 etcd 镜像应作为固定制品发布；单机、双机房、三机房的差异由 compose、配置文件和脚本表达。完整矩阵见 [deployment-modes.md](deployment-modes.md)。

| 形态 | 用途 | 启动入口 |
|------|------|----------|
| 单机 POC | 产品演示、POC 测试 | `docker-compose.single.yml` |
| 本地 HA 测试 | 单机模拟 3 etcd + 3 DB | `docker-compose.test.yml` |
| 双机房低成本 | A 主 B 备，B 手工接管 | `docker-compose.yml` + `cluster.conf` |
| 双机房自动切换 | A/B + 第三故障域 witness | `docker-compose.yml` + witness 配置 |
| 三机房 HA | 三故障域生产 HA | `docker-compose.yml` + 三机房配置 |

## 快速开始

### 1. 构建镜像

```bash
docker build -t opengauss-ha:5.0.3_arm -f Dockerfile.patch .
```

构建过程会自动:
- 编译 MOT shim (LD_PRELOAD)
- 对 gaussdb 二进制进行 MOT 初始化补丁（ARM64 Docker NUMA bug）
- 复制 entrypoint 脚本和配置

### 2. 启动单机 POC

```bash
docker compose --env-file configs/single.env.example -f docker-compose.single.yml up -d
```

连接数据库：

```bash
gsql -h 127.0.0.1 -p 5432 -d test -U gauss -W SecurePass123
```

### 3. 启动本地 HA 测试集群

```bash
# 本地测试模式 (6 容器: 3 etcd + 3 openGauss)
docker compose -f docker-compose.test.yml up -d
```

### 4. 验证集群

```bash
# 检查各节点容器状态
docker ps

# 检查 etcd 集群健康
docker exec etcd-a1 etcdctl --endpoints=http://172.20.0.10:2379 endpoint health -w table

# 检查数据库状态 (以 omm 用户执行)
docker exec master su - omm -c "export PATH=/opt/software/openGauss/bin:\$PATH; \
  export LD_LIBRARY_PATH=/opt/software/openGauss/lib:\$LD_LIBRARY_PATH; \
  gs_ctl query -D /opt/software/openGauss/data/db"
```

### 5. 连接 HA 数据库

```bash
# 通过容器内 gsql
docker exec master su - omm -c "export PATH=/opt/software/openGauss/bin:\$PATH; \
  export LD_LIBRARY_PATH=/opt/software/openGauss/lib:\$LD_LIBRARY_PATH; \
  gsql -d test -U gauss -W SecurePass123"

# 通过主机端口映射 (master: 15432)
gsql -h 127.0.0.1 -p 15432 -d test -U gauss -W SecurePass123
```

## 集群管理

### 查看集群拓扑

```bash
docker exec master su - omm -c "export PATH=/opt/software/openGauss/bin:\$PATH; \
  export LD_LIBRARY_PATH=/opt/software/openGauss/lib:\$LD_LIBRARY_PATH; \
  patronictl -c /opt/software/openGauss/data/conf/patroni.yaml list"
```

### 健康检查

```bash
for node in master slave01 slave02; do
  ROLE=$(docker exec $node su - omm -c "export PATH=/opt/software/openGauss/bin:\$PATH; \
    export LD_LIBRARY_PATH=/opt/software/openGauss/lib:\$LD_LIBRARY_PATH; \
    gs_ctl query -D /opt/software/openGauss/data/db 2>&1 | grep 'local_role' | head -1")
  echo "$node: $ROLE"
done
```

### 查看日志

```bash
# Patroni 日志
docker exec master tail -f /opt/software/openGauss/logs/patroni.log

# 数据库运行日志
docker exec master tail -f /opt/software/openGauss/logs/gs_log/*.log
```

## 配置指南

### docker-compose.test.yml

本地测试使用 bridge 网络模式，IP 分配:

| 容器 | IP | 角色 |
|------|-----|------|
| etcd-a1 | 172.20.0.10 | etcd 节点 |
| etcd-b1 | 172.20.0.20 | etcd 节点 |
| etcd-c1 | 172.20.0.30 | etcd 节点 |
| master | 172.20.0.11 | openGauss 节点 |
| slave01 | 172.20.0.21 | openGauss 节点 |
| slave02 | 172.20.0.31 | openGauss 节点 |

### 关键环境变量

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `ETCD_PEERS` | etcd 集群节点列表 | - |
| `ETCD_HOSTS` | Patroni DCS etcd 地址 | - |
| `TTL` | Patroni leader lock TTL | 60 |
| `LOOP_WAIT` | Patroni 主循环间隔 | 10 |
| `RETRY_TIMEOUT` | Patroni DCS/数据库操作重试超时 | 30 |
| `SYNCHRONOUS_MODE` | 同步复制模式 | false |
| `MAXIMUM_LAG_ON_FAILOVER` | 允许故障切换的最大复制延迟 | 104857600 |
| `MAX_CONNECTIONS` | 最大连接数 | 1000 |
| `WAL_LEVEL` | WAL 级别 | logical |

这些参数会写入 `/opt/software/openGauss/data/conf/patroni.yaml`。注意 Patroni 的 `bootstrap.dcs` 只在集群首次初始化时写入 DCS；已存在集群需要使用 `patronictl edit-config` 或 Patroni REST API 修改动态配置。

### 独立 etcd 初始化

首次部署 Dedicated 模式时，三个 etcd 节点都属于同一个静态初始集群：

```bash
./deploy.sh install etcd-a1 10.0.1.10
./deploy.sh install etcd-b1 10.0.2.10
./deploy.sh install etcd-c1 10.0.3.10
```

第一个 etcd 节点可能在 quorum 未形成前显示未健康，这是预期现象；至少两个初始成员启动后，etcd 才能选出 leader。故障重建 etcd 节点时使用 `./deploy.sh etcd-recover <name>`，不要把已有集群的恢复节点当作全新集群重新初始化。

## 故障恢复

### Leader 故障

```bash
# Leader 故障后，Patroni 自动选主 (预期 < 60s)
docker stop master

# 验证新 Leader
docker exec slave01 su - omm -c "export PATH=/opt/software/openGauss/bin:\$PATH; \
  export LD_LIBRARY_PATH=/opt/software/openGauss/lib:\$LD_LIBRARY_PATH; \
  gs_ctl query -D /opt/software/openGauss/data/db 2>&1 | grep 'local_role'"

# 恢复旧 Leader (自动以 Standby 加入)
docker start master
```

### Standby 故障

```bash
# Standby 故障不影响 Leader
docker stop slave01
# Leader 继续可写

# 恢复 Standby (自动重同步)
docker start slave01
```

### etcd 故障

```bash
# 单节点故障: 不影响服务
docker stop etcd-a1

# 多数派故障: Patroni 无法续租 leader lock，TTL 过期后应降级保护
docker stop etcd-a1 etcd-b1

# 恢复: 至少恢复一个 etcd 节点
docker start etcd-a1
```

多数派丢失时，数据库侧的安全行为依赖 Patroni TTL、DCS 降级逻辑和故障隔离策略。生产环境应配套 watchdog/fencing，并通过客户端接入层停止向旧 Leader 写入。

### 双机房无第三仲裁的人工接管

当只能在 A/B 两个机房内部署 etcd 时，建议把 quorum 偏向主中心 A，例如 A 放 2 个 etcd，B 放 1 个 etcd。该模式下：

- B 故障: A 保留 2/3 quorum，业务继续写。
- A-B 网络分区且 A 存活: A 继续写，B 不自动提升。
- A 整体故障: B 只有 1/3 quorum，必须人工接管。
- B 人工接管前必须先 fencing A，否则网络恢复后可能形成双主。

低成本生产部署可以压缩到 3 台机器：

| 机房 | 机器 | 部署 |
|------|------|------|
| A | node-a1 | etcd-a1 + openGauss/Patroni |
| A | node-a2 | etcd-a2 + openGauss/Patroni |
| B | node-b1 | etcd-b1 + openGauss/Patroni |

该方案仍属于 `A 主 B 备 + A 优先 quorum + B 手工灾备接管`。etcd 和 openGauss 可以共用物理机，但必须分容器、分数据目录，并给 etcd 保留 CPU、内存和磁盘 IO 资源。

如果要求“两中心任意一边故障都自动切换”，不要采用 3 台机器双机房方案。最佳生产方案是增加第三故障域 etcd witness：A 放 1 个 etcd + DB，B 放 1 个 etcd + DB，第三故障域放 1 个 etcd witness。这样 A 或 B 任意一边故障时，另一边加 witness 都能保留 2/3 quorum。

辅助脚本位于 `scripts/two-dc-manual-dr.sh`，默认 `DRY_RUN=yes`，只打印命令。生产执行前需要按实际主机名设置环境变量：

```bash
export A_DB_NODES="host-a-db:master"
export B_DB_NODES="host-b-db:slave01"
export B_CANDIDATE="host-b-db:slave01"
export A_ETCD_NODES="host-a-etcd1:etcd-a1 host-a-etcd2:etcd-b1"
export B_ETCD_NODES="host-b-etcd1:etcd-c1"
```

变量格式为 `SSH主机名:容器名`；如果两者相同，也可以只写一个名字。

A 故障后接管 B 的操作步骤：

```bash
# 1. 查看当前状态
scripts/two-dc-manual-dr.sh status

# 2. 隔离 A。A 可达时可停容器；A 不可达时必须在电源、网络或负载均衡层完成 fencing
DRY_RUN=no scripts/two-dc-manual-dr.sh fence-a

# 3. 确认 A 已不可写后，才允许 B 侧接管
FENCE_A_CONFIRMED=yes DRY_RUN=no scripts/two-dc-manual-dr.sh takeover-b

# 4. 在 VIP、负载均衡或服务发现中，将写流量切到 B
```

B 已接管后恢复 A 的操作步骤：

```bash
# A 不能直接以旧 Leader 身份恢复服务，必须从 B 重建为 Standby
FENCE_A_CONFIRMED=yes DRY_RUN=no scripts/two-dc-manual-dr.sh recover-a-as-standby

./deploy.sh status
```

## 已知问题与解决方案

### 1. MOT 引擎在 ARM64 Docker 中崩溃

**症状**: `FATAL: MOT engine initialization failed`

**原因**: MOT 引擎使用 NUMA API，ARM64 Docker 环境下 `numa_available()` 返回 -1。

**解决方案**: `patch_gaussdb.py` 对 gaussdb 二进制进行补丁，将 `InitMOT()` 等入口点替换为 `ret` 指令。不使用 MOT 表时安全。

### 2. Docker 绑定挂载目录权限

**症状**: Slave 节点 conf 目录为空，无法创建 patroni.yaml。

**原因**: Docker 绑定挂载目录属主为 `root:root`，`omm` 用户无法写入。

**解决方案**: `entrypoint.sh` 中无条件执行 `chown -R omm:dbgrp` 并预创建 conf 目录。

### 3. 外部 etcd 模式下节点发现未初始化

**症状**: Slave 节点 `replconninfo` 未配置，无法建立复制。

**原因**: `get_HOST_NAMES_IP()` 仅在 `start_etcd()` 中调用，使用外部 etcd 时被跳过。

**解决方案**: 无论是否使用外部 etcd，在 `init_db` 前调用 `get_HOST_NAMES_IP`。

## HA 测试结果

| 测试 | 结果 | RTO |
|------|------|-----|
| TC-01: Leader 自动切换 | ✅ PASS | 40s |
| TC-02: Standby 故障不影响服务 | ✅ PASS | 0 |
| TC-03: Standby 恢复后自动重同步 | ✅ PASS | - |
| TC-04: etcd 单节点故障 | ✅ PASS | 0 |
| TC-05: etcd 多数派故障 → 降级保护 | ✅ PASS | - |
| TC-06: 旧 Leader 恢复后自动降级 | ✅ PASS | - |
| DC-01: 双机房 Leader 侧故障 | ✅ PASS | 42s |
| DC-02: 双机房 Standby 侧故障 | ✅ PASS | 0 |

完整测试用例: [test-cases.md](test-cases.md)
