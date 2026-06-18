# openGauss HA Cluster - 架构设计

## 架构概览

```
              ┌─────────────────────────────────────────────────────────┐
              │                    etcd Cluster (3 节点)                 │
              │                                                         │
              │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
              │   │   etcd-a1    │  │   etcd-b1    │  │   etcd-c1    │ │
              │   │  (机房 A)    │  │  (机房 B)    │  │  (机房 C)    │ │
              │   │ 10.0.1.10    │  │ 10.0.2.10    │  │ 10.0.3.10    │ │
              │   │ :2379 :2380  │  │ :2379 :2380  │  │ :2379 :2380  │ │
              │   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
              │          └─────────────────┼─────────────────┘          │
              └────────────────────────────┼────────────────────────────┘
                                           │ Patroni DCS API (2379)
              ┌────────────────────────────┼────────────────────────────┐
              │              openGauss + Patroni Cluster                │
              │                                                         │
              │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
              │   │   master     │  │   slave01    │  │   slave02    │ │
              │   │  (机房 A)    │  │  (机房 B)    │  │  (机房 C)    │ │
              │   │ 10.0.1.11    │  │ 10.0.2.11    │  │ 10.0.3.11    │ │
              │   │ :5432 :8008  │  │ :5432 :8008  │  │ :5432 :8008  │ │
              │   │   Leader     │  │   Standby    │  │   Standby    │ │
              │   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
              │          │  WAL stream     │                    │       │
              │          └─────────────────┴────────────────────┘       │
              │                   :5433 (replication)                   │
              └─────────────────────────────────────────────────────────┘
```

## 部署模式

openGauss 支持从单机 POC 到多机房 HA 的多种部署形态。镜像应保持固定：openGauss/Patroni 镜像和 etcd 镜像作为稳定制品发布；不同形态只改变 compose 文件、配置文件和配套脚本。完整部署矩阵见 [deployment-modes.md](deployment-modes.md)。

### Single 模式（1 节点）
单机 POC 或产品演示使用，不启动 etcd，也不提供 Patroni 自动故障切换：

```
Node 1: openGauss  (RUN_MODE=standard)
```

该模式只用于功能验证、兼容性验证和轻量 POC，不承诺 HA。生产 HA 应选择双机房或三机房形态。

### Compact 模式（3 节点）
每个物理节点同时运行 etcd + openGauss：

```
Node 1 [DC-A]  : etcd-a1 + master  (10.0.1.10)
Node 2 [DC-B]  : etcd-b1 + slave01 (10.0.2.10)
Node 3 [DC-C]  : etcd-c1 + slave02 (10.0.3.10)
```

### Dedicated 模式（6 节点）
etcd 与数据库分离部署：

```
Node 1 [DC-A]  : etcd-a1  (10.0.1.10)
Node 2 [DC-A]  : master   (10.0.1.11)
Node 3 [DC-B]  : etcd-b1  (10.0.2.10)
Node 4 [DC-B]  : slave01  (10.0.2.11)
Node 5 [DC-C]  : etcd-c1  (10.0.3.10)
Node 6 [DC-C]  : slave02  (10.0.3.11)
```

生产环境优先推荐 Dedicated 模式。etcd 是 Patroni 的 DCS，不承载业务数据；独立部署可以避免数据库 CPU、IO、内存抖动影响 Raft 选举和租约续期，也便于单独做 etcd 备份、TLS、磁盘告警和成员恢复。

### 为什么 etcd 要独立

旧方案将 openGauss、Patroni、etcd 放在同一个容器内，适合本地验证，但不适合作为生产 HA 的默认形态。核心原因是它把数据库数据面和集群控制面绑定到了同一个故障域：

- openGauss 是重 CPU、内存和磁盘 IO 的组件，checkpoint、WAL 写入、慢盘或内存压力都可能拖慢 etcd 的 fsync、Raft 心跳和 leader lock 续租，进而造成误判或不必要的故障切换。
- 容器重启会同时带走数据库、Patroni 和 etcd。原本只是单个数据库节点异常，却会同步损失一个 DCS 成员，扩大故障半径。
- etcd 成员恢复、证书轮换、备份和 member add/remove 属于控制面运维；openGauss 参数调整、补丁升级、重建属于数据面运维。放在一起会让两类维护互相影响。
- 双机房或三机房容灾时，etcd quorum 的位置应该按仲裁需求设计，而不是被数据库节点的容量和主从分布绑定。独立 etcd 可以把第三个仲裁节点放在第三故障域。

因此，独立 etcd 的目的不是增加组件数量，而是让 Patroni 依赖的仲裁系统尽量不被 openGauss 自身故障拖下水。

### 为什么 Patroni 可以和 openGauss 同容器

Patroni 与 etcd 的角色不同。Patroni 是每个数据库节点上的本地管理代理，它需要直接控制本机 openGauss：

- 启动、停止、重启、提升、降级本机数据库实例。
- 读取和写入本地数据目录、`postgresql.conf`、`patroni.yaml` 等配置。
- 调用本机 `gs_ctl`、检查本机进程状态，并把本节点状态上报到 etcd。

如果某个节点的 Patroni 不可用，该节点就不应继续作为可自动管理的 HA 成员。Patroni 与对应 openGauss 共享生命周期，符合“一个容器代表一个数据库 HA 节点”的模型；它不会参与 Raft quorum，也不会承担跨集群一致性仲裁。因此 Patroni + openGauss 同容器是本地控制域，etcd + openGauss 同容器则会把集群控制面绑到数据库工作负载上，风险更高。

### 生产接入边界

- etcd 只负责一致性元数据和 leader lock，不转发 SQL 流量。
- openGauss 的主从复制仍由数据库节点之间的流复制完成。
- 业务连接不应固定写到 `master` 主机名；生产需在前面增加 HAProxy/VIP/Keepalived 或服务发现，根据 Patroni REST API 将写流量导向当前 Leader。
- 若要强约束 split-brain 风险，需补充 watchdog、STONITH/fencing 或同等隔离机制；仅依赖 DCS 超时降级不能替代故障隔离。

## 组件职责 & 端口

| 组件 | 端口 | 用途 |
|------|------|------|
| etcd | 2379 | 客户端 API (Patroni DCS) |
| etcd | 2380 | Peer 通信 (Raft) |
| openGauss | 5432 | SQL |
| openGauss | 5433 | 流复制 (GAUSS_PORT+1) |
| openGauss | 5436 | 复制服务 (GAUSS_PORT+4) |
| openGauss | 5437 | 复制心跳 (GAUSS_PORT+5) |
| Patroni | 8008 | REST API (健康/角色) |

## 数据流

```
Client ──► openGauss Leader (:5432)
                │
                ├──► WAL Stream ──► Standby1 (:5433)
                ├──► WAL Stream ──► Standby2 (:5433)
                │
                ├──► etcd DCS (leader lock + member state)
                │
                └──► Patroni REST (:8008) 健康检查
```

## Patroni 选主流程

```
1. Leader 每 TTL/2 秒续租 etcd leader lock
2. Leader 锁过期 → 所有 Standby 竞争
3. 选主优先级: 同步 Standby > lag 最小 > 时间线最新
4. 新 Leader 提升后更新 etcd
5. 旧 Leader 恢复后自动降级为 Standby
```

## 双机房 vs 三机房

| 参数 | 双机房 | 三机房 |
|------|--------|--------|
| etcd 部署 | 2+1 仲裁或 3 跨两机房 | 每机房 1 节点 |
| 同步模式 | synchronous_mode=false (异步) | synchronous_mode=true |
| RPO | >0 (异步 lag) | 配置同步提交且有同步 Standby 时为 0 |
| RTO | 30-60s | 30-60s |
| 机房故障 | 取决 etcd quorum 位置 | 单机房故障多数派仍存活 |

### 双机房关键约束
- etcd 3 节点才有 quorum，仲裁节点位置决定可用性
- 若 etcd 的 2 节点在 DC-A、1 在 DC-B → DC-A 故障 → 失去 quorum → Patroni 无法安全自动选主，写入应被降级保护拒绝
- 建议: 第 3 个 etcd 放第三方（云/小机房），实现真正双机房容灾

### 低成本生产方案（3 台机器）

当机器数量必须进一步压缩时，可以采用 A 机房 2 台、B 机房 1 台的 3 节点方案。每台机器同时部署 1 个 etcd 容器和 1 个 openGauss+Patroni 容器，但两者必须保持独立容器、独立数据目录和独立资源限制：

```
Node A1 [DC-A] : etcd-a1 + openGauss/Patroni master 优先
Node A2 [DC-A] : etcd-a2 + openGauss/Patroni standby
Node B1 [DC-B] : etcd-b1 + openGauss/Patroni standby
```

该方案是 `A 主 B 备 + A 优先 quorum + B 手工灾备接管` 的低成本形态：

| 故障场景 | 结果 |
|----------|------|
| B 机房故障 | A 仍有 2/3 etcd quorum，业务继续写 |
| A 单台机器故障 | 剩余 A+B 仍有 2/3 etcd quorum，可自动切换 |
| B 单台机器故障 | A 两台继续服务 |
| A-B 网络分区且 A 存活 | A 侧 2/3 quorum 继续写，B 不自动提升 |
| A 整体故障 | B 只有 1/3 etcd，无 quorum，不能自动接管 |

使用该方案时必须接受以下 SLA 边界：

- 可自动处理: 单机故障、B 机房故障、A-B 网络分区且 A 存活。
- 不可自动处理: A 机房整体故障。
- A 整体故障 RTO: 人工接管时间。
- RPO: 异步复制下取决于 B standby 的复制延迟；同步复制会增加跨机房写延迟，并在 B 不可用时影响写入能力。

该方案降低机器数量，但会放大单机故障半径：任意机器故障都会同时损失一个 etcd 成员和一个数据库成员。生产上应给 etcd 设置 CPU/memory reservation，etcd 数据目录使用独立磁盘或独立 volume，并保持 openGauss 与 etcd 分容器部署。

### 任意中心故障自动切换的最佳生产方案

如果目标是“两中心任意一边整体故障都能自动切换”，仅有 A/B 两个故障域无法安全实现。原因是 etcd/Patroni 依赖多数派仲裁，3 个 etcd 节点放在两个机房内必然形成 `2+1` 偏置；放 2 个 etcd 的机房整体故障时，另一侧只剩 1/3 quorum，不能安全自动选主。

最佳生产方案是引入第三故障域的 etcd witness：

```
DC-A          : etcd-a1 + openGauss/Patroni
DC-B          : etcd-b1 + openGauss/Patroni
DC-Witness    : etcd-w1
```

最小机器数为 5 台：

| 位置 | 机器数 | 角色 |
|------|--------|------|
| DC-A | 2 | 1 台 etcd，1 台 openGauss/Patroni |
| DC-B | 2 | 1 台 etcd，1 台 openGauss/Patroni |
| 第三故障域 | 1 | 1 台 etcd witness |

该形态下：

- A 故障: B + witness 保留 2/3 quorum，B 可自动提升。
- B 故障: A + witness 保留 2/3 quorum，A 继续服务。
- witness 故障: A + B 保留 2/3 quorum，业务继续。

如果数据库需要 3 副本，可在 A 或 B 增加第 3 个 openGauss/Patroni 节点；etcd 仲裁仍建议保持独立 3 节点、跨 3 个故障域部署。

### etcd 首次部署与恢复

- 首次创建静态 3 节点 etcd 集群时，3 个空数据目录的初始成员都使用 `initial-cluster-state=new`，并配置相同的 `initial-cluster` 和 token。至少启动 2 个成员后才形成 quorum。
- 已加入过集群的 etcd 节点重建时，不能当作新集群初始化；应使用 `initial-cluster-state=existing`，必要时先通过健康成员执行 `etcdctl member remove/add`。
- etcd 数据目录必须使用独立持久化卷，避免误删后以旧 member ID 或错误 cluster token 重新加入。
