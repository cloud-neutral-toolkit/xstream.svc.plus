#!/usr/bin/env bash
set -euo pipefail

# PostgreSQL host migration automation
# Flow:
# 1) Optional target host bootstrap
# 2) Full backup from source host
# 3) Restore to target host
# 4) Source/target validation
# 5) Print manual DNS switch checklist

SOURCE_HOST="root@postgresql.svc.plus"
TARGET_HOST="root@47.120.61.35"
TARGET_INIT_SCRIPT_URL="https://raw.githubusercontent.com/cloud-neutral-toolkit/postgresql.svc.plus/main/scripts/init_vhost.sh"
TARGET_INIT_ARG1="17"
TARGET_INIT_ARG2="postgresql.svc.plus"
DB_LIST="account knowledge_db postgres"
WORKDIR="./build/postgres-migration"
CONTAINER_NAME="postgresql-svc-plus"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"
INIT_TARGET=1
SKIP_DNS_NOTE=0
FORCE=0

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --source <user@host>          Source host (default: ${SOURCE_HOST})
  --target <user@host>          Target host (default: ${TARGET_HOST})
  --dbs "db1 db2 ..."           Databases to migrate (default: "${DB_LIST}")
  --container <name>            PostgreSQL container name (default: ${CONTAINER_NAME})
  --workdir <path>              Local working dir (default: ${WORKDIR})
  --no-init-target              Skip target bootstrap init_vhost step
  --skip-dns-note               Do not print final DNS cutover checklist
  --force                       Do not prompt before destructive restore actions
  -h, --help                    Show help

Notes:
  - Requires local: ssh, scp, sha256sum
  - Requires remote source/target: docker + container '${CONTAINER_NAME}'
  - Restore phase drops/recreates target databases listed in --dbs
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_HOST="$2"; shift 2 ;;
    --target)
      TARGET_HOST="$2"; shift 2 ;;
    --dbs)
      DB_LIST="$2"; shift 2 ;;
    --container)
      CONTAINER_NAME="$2"; shift 2 ;;
    --workdir)
      WORKDIR="$2"; shift 2 ;;
    --no-init-target)
      INIT_TARGET=0; shift ;;
    --skip-dns-note)
      SKIP_DNS_NOTE=1; shift ;;
    --force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp
require_cmd sha256sum

TS="$(date +%Y%m%d-%H%M%S)"
LOCAL_DIR="${WORKDIR}/${TS}"
DUMP_DIR="${LOCAL_DIR}/dump"
SIG_DIR="${LOCAL_DIR}/signatures"
LOG_FILE="${LOCAL_DIR}/migration.log"
mkdir -p "${DUMP_DIR}" "${SIG_DIR}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG_FILE}"
}

run_ssh() {
  local host="$1"
  shift
  ssh ${SSH_OPTS} "$host" "$@"
}

check_remote_connectivity() {
  local host="$1"
  log "Checking connectivity on ${host}"
  run_ssh "$host" "echo ok >/dev/null"
}

check_remote_ready() {
  local host="$1"
  log "Checking docker/container on ${host}"
  run_ssh "$host" "command -v docker >/dev/null && docker ps >/dev/null"
  run_ssh "$host" "docker ps --format '{{.Names}}' | grep -Fx '${CONTAINER_NAME}' >/dev/null"
}

remote_pg_exec() {
  local host="$1"
  local sql="$2"
  run_ssh "$host" "docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 -Atqc \"${sql}\""
}

bootstrap_target() {
  if [[ "${INIT_TARGET}" != "1" ]]; then
    log "Skipping target bootstrap (--no-init-target)"
    return
  fi
  log "Bootstrapping target host ${TARGET_HOST}"
  run_ssh "$TARGET_HOST" "curl -fsSL '${TARGET_INIT_SCRIPT_URL}' | bash -s -- '${TARGET_INIT_ARG1}' '${TARGET_INIT_ARG2}'"
}

backup_source() {
  log "Creating full backup on source ${SOURCE_HOST}"

  log "Dumping global roles/settings"
  run_ssh "$SOURCE_HOST" "docker exec -i ${CONTAINER_NAME} pg_dumpall -U postgres --globals-only" > "${DUMP_DIR}/globals.sql"

  for db in ${DB_LIST}; do
    log "Dumping database: ${db}"
    run_ssh "$SOURCE_HOST" "docker exec -i ${CONTAINER_NAME} pg_dump -U postgres -Fc --no-owner --no-privileges '${db}'" > "${DUMP_DIR}/${db}.dump"
    sha256sum "${DUMP_DIR}/${db}.dump" | tee -a "${LOG_FILE}"
  done
}

transfer_backup() {
  log "Transferring backup files to target ${TARGET_HOST}"
  run_ssh "$TARGET_HOST" "mkdir -p /tmp/pg-migration-${TS}"
  scp ${SSH_OPTS} "${DUMP_DIR}/globals.sql" "${TARGET_HOST}:/tmp/pg-migration-${TS}/globals.sql"
  for db in ${DB_LIST}; do
    scp ${SSH_OPTS} "${DUMP_DIR}/${db}.dump" "${TARGET_HOST}:/tmp/pg-migration-${TS}/${db}.dump"
  done
}

restore_target() {
  if [[ "${FORCE}" != "1" ]]; then
    echo
    echo "About to restore on target ${TARGET_HOST}."
    echo "Target databases will be dropped and recreated: ${DB_LIST}"
    read -r -p "Type YES to continue: " answer
    if [[ "$answer" != "YES" ]]; then
      log "User aborted restore phase"
      exit 1
    fi
  fi

  log "Restoring globals on target"
  run_ssh "$TARGET_HOST" "cat /tmp/pg-migration-${TS}/globals.sql | docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 postgres"

  for db in ${DB_LIST}; do
    log "Recreating and restoring target db: ${db}"
    run_ssh "$TARGET_HOST" "docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid();\""
    run_ssh "$TARGET_HOST" "docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 postgres -c \"DROP DATABASE IF EXISTS \\\"${db}\\\";\""
    run_ssh "$TARGET_HOST" "docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 postgres -c \"CREATE DATABASE \\\"${db}\\\";\""
    run_ssh "$TARGET_HOST" "cat /tmp/pg-migration-${TS}/${db}.dump | docker exec -i ${CONTAINER_NAME} pg_restore -U postgres -d '${db}' --no-owner --no-privileges -v"
  done
}

# Exact table-row fingerprint by counting every user table.
# Output format: schema.table<TAB>rows
fingerprint_sql() {
  cat <<'SQL'
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname !~ '^pg_toast'
    ORDER BY 1, 2
  LOOP
    EXECUTE format(
      'COPY (SELECT %L || E''\t'' || count(*)::text FROM %I.%I) TO STDOUT',
      r.schema_name || '.' || r.table_name,
      r.schema_name,
      r.table_name
    );
  END LOOP;
END $$;
SQL
}

collect_signatures() {
  local host="$1"
  local side="$2"

  for db in ${DB_LIST}; do
    log "Collecting ${side} signature for db=${db}"

    remote_pg_exec "$host" "SELECT pg_database_size('${db}');" > "${SIG_DIR}/${side}.${db}.size"

    local tmp_sql
    tmp_sql="$(mktemp)"
    fingerprint_sql > "$tmp_sql"

    scp ${SSH_OPTS} "$tmp_sql" "${host}:/tmp/pg-migration-${TS}/fingerprint.sql" >/dev/null
    rm -f "$tmp_sql"

    run_ssh "$host" "docker exec -i ${CONTAINER_NAME} psql -U postgres -v ON_ERROR_STOP=1 '${db}' -f /tmp/pg-migration-${TS}/fingerprint.sql" \
      | LC_ALL=C sort > "${SIG_DIR}/${side}.${db}.rows.tsv"

    sha256sum "${SIG_DIR}/${side}.${db}.rows.tsv" | awk '{print $1}' > "${SIG_DIR}/${side}.${db}.rows.sha256"
  done
}

validate_compare() {
  log "Comparing source vs target signatures"

  local failed=0
  for db in ${DB_LIST}; do
    local src_hash
    local dst_hash
    local src_size
    local dst_size
    local pct

    src_hash="$(cat "${SIG_DIR}/source.${db}.rows.sha256")"
    dst_hash="$(cat "${SIG_DIR}/target.${db}.rows.sha256")"

    src_size="$(cat "${SIG_DIR}/source.${db}.size")"
    dst_size="$(cat "${SIG_DIR}/target.${db}.size")"

    log "DB=${db} source_size=${src_size} target_size=${dst_size}"

    if [[ "$src_hash" != "$dst_hash" ]]; then
      log "ERROR: Row fingerprint mismatch for ${db}"
      diff -u "${SIG_DIR}/source.${db}.rows.tsv" "${SIG_DIR}/target.${db}.rows.tsv" > "${SIG_DIR}/${db}.rows.diff" || true
      log "Diff saved: ${SIG_DIR}/${db}.rows.diff"
      failed=1
    else
      log "OK: Row fingerprint matched for ${db}"
    fi

    pct="$(awk -v s="$src_size" -v t="$dst_size" 'BEGIN{if(s==0){print 0}else{d=(t-s); if(d<0)d=-d; printf "%.2f", (d*100.0)/s}}')"
    if awk -v p="$pct" 'BEGIN{exit !(p>10.0)}'; then
      log "WARN: Size delta >10% for ${db} (${pct}%)"
    fi
  done

  if [[ "$failed" == "1" ]]; then
    log "Validation failed. DNS cutover must NOT proceed."
    exit 2
  fi

  log "Validation passed for all databases."
}

print_dns_cutover_note() {
  if [[ "${SKIP_DNS_NOTE}" == "1" ]]; then
    return
  fi

  cat <<NOTE | tee -a "${LOG_FILE}"

===== Manual DNS Cutover Checklist =====
1. Ensure application write traffic is paused or confirmed safe for cutover.
2. Confirm script finished with: Validation passed for all databases.
3. Update DNS A record for postgresql.svc.plus to target host IP.
4. Wait for DNS propagation based on your TTL policy.
5. Run post-cutover application checks.
6. Keep source host online for rollback window until stable.
========================================
NOTE
}

main() {
  log "Migration started"
  log "SOURCE_HOST=${SOURCE_HOST}"
  log "TARGET_HOST=${TARGET_HOST}"
  log "DB_LIST=${DB_LIST}"
  log "CONTAINER_NAME=${CONTAINER_NAME}"
  log "WORKDIR=${LOCAL_DIR}"

  check_remote_connectivity "$SOURCE_HOST"
  check_remote_connectivity "$TARGET_HOST"

  check_remote_ready "$SOURCE_HOST"
  bootstrap_target
  check_remote_ready "$TARGET_HOST"
  backup_source
  transfer_backup
  restore_target

  collect_signatures "$SOURCE_HOST" "source"
  collect_signatures "$TARGET_HOST" "target"
  validate_compare
  print_dns_cutover_note

  log "Migration completed successfully"
}

main "$@"
