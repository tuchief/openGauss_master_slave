#!/usr/bin/env bash
# Manual DR helper for two data centers without a third etcd witness.
#
# This script is intentionally conservative. Destructive or role-changing
# actions require FENCE_A_CONFIRMED=yes because promoting B while A is still
# writable can create split brain.

set -euo pipefail

SSH_USER="${SSH_USER:-root}"
PATRONI_CONFIG="${PATRONI_CONFIG:-/opt/software/openGauss/data/conf/patroni.yaml}"
DRY_RUN="${DRY_RUN:-yes}"

A_DB_NODES="${A_DB_NODES:-master}"
B_DB_NODES="${B_DB_NODES:-slave01}"
B_CANDIDATE="${B_CANDIDATE:-slave01}"
A_ETCD_NODES="${A_ETCD_NODES:-etcd-a1 etcd-b1}"
B_ETCD_NODES="${B_ETCD_NODES:-etcd-c1}"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = "yes" ]; then
        printf '[DRY-RUN] %s\n' "$*"
    else
        eval "$@"
    fi
}

entry_host() { printf '%s' "${1%%:*}"; }

entry_container() {
    if [[ "$1" == *:* ]]; then
        printf '%s' "${1#*:}"
    else
        printf '%s' "$1"
    fi
}

remote() {
    local host="$1"
    shift
    run "ssh ${SSH_USER}@${host} '$*'"
}

need_fencing_confirmation() {
    if [ "${FENCE_A_CONFIRMED:-no}" != "yes" ]; then
        die "Refusing to continue. Set FENCE_A_CONFIRMED=yes only after A is fenced or its write path is isolated."
    fi
}

patroni_list() {
    local entry="$1"
    local host container
    host="$(entry_host "$entry")"
    container="$(entry_container "$entry")"
    remote "$host" "docker exec ${container} patronictl -c ${PATRONI_CONFIG} list || true"
}

status() {
    log "A DB nodes"
    for host in $A_DB_NODES; do
        patroni_list "$host"
    done

    log "B DB nodes"
    for host in $B_DB_NODES; do
        patroni_list "$host"
    done

    log "etcd health"
    for entry in $A_ETCD_NODES $B_ETCD_NODES; do
        local host container
        host="$(entry_host "$entry")"
        container="$(entry_container "$entry")"
        remote "$host" "docker exec ${container} etcdctl --endpoints=http://127.0.0.1:2379 endpoint health || true"
    done
}

fence_a() {
    cat <<'EOF'
Before promoting B, fence A with one or more audited controls:
- Power off A database hosts.
- Disable A database VIP/load-balancer backend.
- Block application access to A openGauss port 5432.
- Stop A openGauss/Patroni containers if A is reachable.

This helper can only stop containers when A is reachable. If A is isolated by a
network failure, use your infrastructure console or load balancer to fence it.
EOF

    for entry in $A_DB_NODES; do
        local host container
        host="$(entry_host "$entry")"
        container="$(entry_container "$entry")"
        remote "$host" "docker stop ${container} || true"
    done
}

takeover_b() {
    need_fencing_confirmation

    cat <<'EOF'
Takeover model:
1. A has already been fenced.
2. B may not have etcd quorum because the two-site layout is biased to A.
3. Bring up a temporary B-side DCS before promoting B. In production this can be:
   - a single emergency etcd on B for manual DR, or
   - temporary additional etcd members on B hosts.
4. Promote B only after the DCS is reachable and A is fenced.
EOF

    log "Start B-side etcd/DCS recovery according to your local deploy layout"
    for entry in $B_ETCD_NODES; do
        local host container
        host="$(entry_host "$entry")"
        container="$(entry_container "$entry")"
        remote "$host" "docker start ${container} || true"
    done

    log "Promote B candidate through Patroni"
    local candidate_host candidate_container
    candidate_host="$(entry_host "$B_CANDIDATE")"
    candidate_container="$(entry_container "$B_CANDIDATE")"
    remote "$candidate_host" "docker exec ${candidate_container} patronictl -c ${PATRONI_CONFIG} failover --candidate ${candidate_container} --force"

    log "Point application write traffic to B only"
    warn "Update VIP/load balancer/service discovery outside this script."
}

recover_a_as_standby() {
    need_fencing_confirmation

    cat <<'EOF'
A recovery model after B has been promoted:
1. Keep A fenced from application write traffic.
2. Do not start the old A primary as a writable node.
3. Rebuild A database nodes from the current B leader.
4. Rejoin or rebuild A-side etcd members after the active DCS is healthy.
EOF

    for entry in $A_DB_NODES; do
        local host container
        host="$(entry_host "$entry")"
        container="$(entry_container "$entry")"
        remote "$host" "docker stop ${container} || true"
        remote "$host" "rm -rf /opt/opengauss-ha/data/${container}/data/db || true"
        remote "$host" "cd /opt/opengauss-ha && ./deploy.sh recover ${container}"
    done

    for entry in $A_ETCD_NODES; do
        local host container
        host="$(entry_host "$entry")"
        container="$(entry_container "$entry")"
        remote "$host" "cd /opt/opengauss-ha && ./deploy.sh etcd-recover ${container}"
    done
}

case "${1:-}" in
    status) status ;;
    fence-a) fence_a ;;
    takeover-b) takeover_b ;;
    recover-a-as-standby) recover_a_as_standby ;;
    *)
        cat <<EOF
Usage:
  $0 status
  $0 fence-a
  FENCE_A_CONFIRMED=yes $0 takeover-b
  FENCE_A_CONFIRMED=yes $0 recover-a-as-standby

Environment:
  DRY_RUN=yes|no                 default: yes
  SSH_USER=root
  A_DB_NODES="host-a-db:master"
  B_DB_NODES="host-b-db:slave01"
  B_CANDIDATE="host-b-db:slave01"
  A_ETCD_NODES="host-a-etcd1:etcd-a1 host-a-etcd2:etcd-b1"
  B_ETCD_NODES="host-b-etcd1:etcd-c1"
EOF
        ;;
esac
