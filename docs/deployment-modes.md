# openGauss Deployment Modes

## Principle

The openGauss and etcd images should be fixed release artifacts. Deployment topology is controlled by compose files, configuration files, and operational scripts.

This keeps the product path consistent:

| Layer | Changes by topology | Should stay stable |
|-------|---------------------|--------------------|
| Image | No | openGauss binaries, Patroni, etcd runtime, entrypoint |
| Compose | Yes | Service count, network mode, volume mapping, ports |
| Config | Yes | Node names, IPs, DCS endpoints, sync mode, credentials |
| Scripts | Yes | Install, recover, manual DR, verification workflows |

## Mode Matrix

| Mode | Target | Machines | etcd | openGauss | Failover |
|------|--------|----------|------|-----------|----------|
| Single POC | Demo, product POC, local validation | 1 | none | 1 | none |
| Local HA Test | Developer HA validation | 1 host / 6 containers | 3 containers | 3 containers | automatic in local lab |
| Two-DC Low Cost | Production with minimal machines | A:2, B:1 | 3, co-located with DB hosts | 3 | automatic except whole A failure |
| Two-DC + Witness | Production auto failover across two centers | A:2, B:2, witness:1 | 3 across fault domains | 2+ | automatic for A or B failure |
| Three-DC HA | Production HA across three centers | 6+ recommended | 3 across DCs | 3 | automatic for one DC failure |

## Fixed Images

Use the same image tags across all modes:

```bash
OPENGAUSS_IMAGE=opengauss-ha:5.0.3_arm
ETCD_IMAGE=opengauss-ha:5.0.3_arm
```

In the current layout, the same image supports both database and etcd roles through `RUN_MODE`:

| RUN_MODE | Behavior |
|----------|----------|
| `standard` | Single openGauss instance, no Patroni HA and no etcd |
| `etcd` | etcd-only node |
| `master`, `slave01`, `slave02` | openGauss + Patroni node using external `ETCD_HOSTS` |

If etcd is split into a dedicated image later, compose files should be the only place that changes. The topology and HA rules remain the same.

## Single POC

Use this for product POC testing where HA is not required:

```bash
docker compose --env-file configs/single.env.example -f docker-compose.single.yml up -d
```

Characteristics:

- One openGauss container.
- `RUN_MODE=standard`.
- No etcd, no Patroni failover.
- Lowest operational complexity.

This mode is not HA. Backup, restore, and restart behavior must be handled as single-node database operations.

## Two-DC Low Cost

Use this when only three physical machines are available:

```text
DC-A: node-a1 = etcd-a1 + openGauss/Patroni
DC-A: node-a2 = etcd-a2 + openGauss/Patroni
DC-B: node-b1 = etcd-b1 + openGauss/Patroni
```

This is still `A primary / B standby + A-preferred quorum + manual B takeover`.

It can automatically handle:

- B site failure.
- One machine failure.
- A-B network partition while A is alive.

It cannot automatically handle:

- Whole A site failure.

Whole A failure requires the manual DR runbook:

```bash
scripts/two-dc-manual-dr.sh status
DRY_RUN=no scripts/two-dc-manual-dr.sh fence-a
FENCE_A_CONFIRMED=yes DRY_RUN=no scripts/two-dc-manual-dr.sh takeover-b
```

## Two-DC Automatic Failover

Use this when the requirement is that either A or B can fail and the remaining center can automatically become writable:

```text
DC-A:       1 etcd + 1+ openGauss/Patroni
DC-B:       1 etcd + 1+ openGauss/Patroni
DC-Witness: 1 etcd witness
```

The witness can be a small host because it only runs etcd. It must be in a third failure domain. Placing all three etcd members inside A/B only creates a `2+1` bias and cannot safely support automatic failover for either whole-site failure.

## Three-DC HA

Use this for symmetric production HA:

```text
DC-A: 1 etcd + 1 openGauss/Patroni
DC-B: 1 etcd + 1 openGauss/Patroni
DC-C: 1 etcd + 1 openGauss/Patroni
```

For stricter isolation, use Dedicated mode with separate etcd and database machines in each DC. This increases machine count but keeps the control plane away from database resource spikes.
