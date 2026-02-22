#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-OneXray}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname)"
REPORT_DIR="${REPORT_DIR:-$PWD/build/network-audit}"
REPORT_FILE="$REPORT_DIR/onexray-audit-$(date '+%Y%m%d-%H%M%S').log"

mkdir -p "$REPORT_DIR"

log() {
  echo "$@" | tee -a "$REPORT_FILE"
}

run_block() {
  local title="$1"
  shift
  log ""
  log "===== $title ====="
  if "$@" >>"$REPORT_FILE" 2>&1; then
    log "[ok] $title"
  else
    log "[warn] $title failed (non-fatal)"
  fi
}

run_cmd() {
  local title="$1"
  local cmd="$2"
  log ""
  log "===== $title ====="
  log "\$ $cmd"
  if /bin/zsh -lc "$cmd" >>"$REPORT_FILE" 2>&1; then
    log "[ok] $title"
  else
    log "[warn] $title failed (non-fatal)"
  fi
}

log "OneXray Network Audit"
log "Timestamp: $TS"
log "Host: $HOSTNAME"
log "App Keyword: $APP_NAME"
log "Report: $REPORT_FILE"

run_cmd "System Info" "sw_vers && uname -a"
run_cmd "Current User" "id && whoami"

run_cmd "VPN Service List (scutil --nc list)" "scutil --nc list"
run_cmd "VPN Service Detail by Name" "scutil --nc show \"$APP_NAME\" || true"
run_cmd "All Network Services" "networksetup -listallnetworkservices"
run_cmd "Network Service Order" "networksetup -listnetworkserviceorder"

run_cmd "IPv4 Routes" "netstat -rn -f inet"
run_cmd "IPv6 Routes" "netstat -rn -f inet6"
run_cmd "Default Route (IPv4)" "route -n get default"
run_cmd "Default Route (IPv6)" "route -n get -inet6 default || true"

run_cmd "Interfaces (ifconfig)" "ifconfig"
run_cmd "Tunnel Interfaces (utun/ipsec/p2p)" "ifconfig | rg -n \"^(utun|ipsec|ppp)\" -A 6 || true"

run_cmd "DNS Resolver State" "scutil --dns"

log ""
log "===== DNS Per Network Service ====="
SERVICES="$(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 || true)"
if [[ -n "$SERVICES" ]]; then
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    if [[ "$svc" == \** ]]; then
      svc="${svc#* }"
    fi
    log ""
    log "[$svc]"
    /bin/zsh -lc "networksetup -getinfo \"$svc\"; echo; networksetup -getdnsservers \"$svc\"" >>"$REPORT_FILE" 2>&1 || true
  done <<<"$SERVICES"
  log "[ok] DNS Per Network Service"
else
  log "[warn] DNS Per Network Service: no service found"
fi

run_cmd "Process List (network stack focus)" \
  "ps aux | rg -i \"${APP_NAME}|xray|packet|tunnel|networkextension|neagent\" | rg -v rg"

log ""
log "===== PID Discovery ====="
PIDS_RAW="$(pgrep -f -i "${APP_NAME}|xray|PacketTunnel|NetworkExtension|Tunnel" || true)"
if [[ -z "$PIDS_RAW" ]]; then
  log "[warn] no matching process PID found"
else
  log "PIDs: $(echo "$PIDS_RAW" | tr '\n' ' ')"
  log ""
  log "===== Connection Matrix by PID ====="
  {
    printf "%-8s %-20s %-6s %-24s %-24s %-13s\n" "PID" "PROC" "PROTO" "LOCAL" "REMOTE" "STATE"
    printf "%-8s %-20s %-6s %-24s %-24s %-13s\n" "--------" "--------------------" "------" "------------------------" "------------------------" "-------------"
  } >>"$REPORT_FILE"

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    proc_name="$(ps -p "$pid" -o comm= 2>/dev/null | awk '{print $1}' || true)"
    [[ -z "$proc_name" ]] && proc_name="-"
    lsof_out="$(lsof -nP -a -p "$pid" -i 2>/dev/null || true)"
    if [[ -z "$lsof_out" ]]; then
      printf "%-8s %-20s %-6s %-24s %-24s %-13s\n" "$pid" "$proc_name" "-" "-" "-" "-" >>"$REPORT_FILE"
      continue
    fi

    echo "$lsof_out" | awk -v pid="$pid" -v proc="$proc_name" '
      NR==1 {next}
      {
        proto=$8
        name=$9
        state="-"
        if (index($0, "(") > 0) {
          state=$0
          sub(/^.*\(/, "", state)
          sub(/\).*$/, "", state)
        }
        local=name
        remote="-"
        if (index(name, "->") > 0) {
          split(name, arr, "->")
          local=arr[1]
          remote=arr[2]
        }
        printf "%-8s %-20s %-6s %-24s %-24s %-13s\n", pid, proc, proto, local, remote, state
      }' >>"$REPORT_FILE"
  done <<<"$PIDS_RAW"
  log "[ok] Connection Matrix by PID"
fi

run_cmd "Socket Summary" "netstat -anv -p tcp | head -n 120"
run_cmd "System Extensions" "systemextensionsctl list || true"
run_cmd "Kernel Route Snapshot" "route -n monitor -t 1 >/dev/null 2>&1 || true"

log ""
log "Audit complete."
log "Saved report to: $REPORT_FILE"
echo "$REPORT_FILE"
