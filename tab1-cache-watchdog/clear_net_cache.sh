#!/bin/sh
# clear_net_cache.sh - flush transient network state, scoped per client.
# Triggered by a Wi-Fi assoc/disassoc event; WHICH clients get cleaned on
# that event depends on the persisted mode (see MODE_FILE below):
#   wifi - only the Wi-Fi client that triggered the event
#   lan  - only the currently known wired (LAN) clients
#   both - the triggering Wi-Fi client AND all wired clients
# Target: OpenWrt 24.10.3 (GL-MT3000, GL-XE3000, ash/busybox only, no bash)
#
# Usage: clear_net_cache.sh <reason> [ifname] [client_mac]
#   reason     - free text, goes to the log (e.g. "assoc", "disassoc", "manual")
#   ifname     - wireless interface the event came from (e.g. wlan1-2), optional
#   client_mac - MAC of the Wi-Fi client that triggered the event (from the
#                hostapd ubus "address" field)
#
# Does NOT touch /etc/config/*. Only flushes kernel/daemon runtime state,
# reloads/restarts services, and reads/writes its own small state file
# (MODE_FILE, outside /etc/config) to remember the selected mode.

REASON="${1:-manual}"
IFNAME="${2:-unknown}"
TRIGGER_MAC="${3:-}"
LOGTAG="wifi_cache_watchd"
LEASEFILE=/tmp/dhcp.leases
MODE_FILE=/etc/wifi_cache_watchd.mode
RESULT_FILE=/tmp/.wcw_last_result

# File-based flags (not shell vars) so they survive being set from inside a
# piped `while read` subshell (the lan-mode client loop below runs in one).
FLAG_PARTIAL=/tmp/.wcw_flag_partial
FLAG_FAILED=/tmp/.wcw_flag_failed
rm -f "$FLAG_PARTIAL" "$FLAG_FAILED"
mark_partial() { : > "$FLAG_PARTIAL"; }
mark_failed()  { : > "$FLAG_FAILED"; }

# Set to 0 to skip the vm.drop_caches step (it's unrelated to networking and
# can cause a brief slowdown on low-RAM devices; kept optional per request).
ENABLE_DROP_CACHES="${ENABLE_DROP_CACHES:-1}"

# The DNS cache itself cannot be scoped per-client (dnsmasq has one shared
# cache); clearing it briefly restarts dnsmasq for EVERYONE regardless of
# mode (sub-second DNS hiccup, no lease/session loss for anyone). Set to 0
# to skip this and avoid touching dnsmasq at all.
ENABLE_DNS_CACHE_CLEAR="${ENABLE_DNS_CACHE_CLEAR:-1}"

log() {
    logger -t "$LOGTAG" "$1"
}

MODE=$(cat "$MODE_FILE" 2>/dev/null)
case "$MODE" in
    wifi|lan|both) ;;
    *) MODE=wifi ;;
esac

log "cache clear triggered: reason=$REASON iface=$IFNAME trigger_mac=${TRIGGER_MAC:-unknown} mode=$MODE"

# --- helpers -----------------------------------------------------------------

# Resolve a MAC to an IP via the DHCP lease table, falling back to the
# current neighbor (ARP/ND) table.
resolve_ip() {
    _mac=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
    _ip=""
    if [ -f "$LEASEFILE" ]; then
        _ip=$(awk -v m="$_mac" 'tolower($2)==m {ip=$3} END{if(ip)print ip}' "$LEASEFILE")
    fi
    if [ -z "$_ip" ]; then
        _ip=$(ip neigh show 2>/dev/null | awk -v m="$_mac" 'tolower($5)==m {print $1; exit}')
    fi
    printf '%s' "$_ip"
}

# Currently active Wi-Fi (hostapd) interface names, queried live via ubus --
# no dependency on /etc/config/wireless contents.
wifi_ifaces() {
    ubus list 2>/dev/null | sed -n 's/^hostapd\.//p'
}

# Classify a MAC as "wifi" or "lan" by looking up which physical bridge port
# it's actually seen on (bridge fdb), not by which event fired.
classify_mac() {
    _mac=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
    if ! command -v bridge >/dev/null 2>&1; then
        echo unknown
        return
    fi
    _dev=$(bridge fdb show 2>/dev/null | awk -v m="$_mac" 'tolower($1)==m && $2=="dev" {print $3; exit}')
    [ -n "$_dev" ] || { echo unknown; return; }
    for _w in $WIFI_IFACES; do
        [ "$_dev" = "$_w" ] && { echo wifi; return; }
    done
    echo lan
}

# Scoped cleanup of ONE client (conntrack / ARP-ND / DHCP lease). Does not
# touch the DNS cache (handled once, globally, at the end).
clean_one_client() {
    _mac="$1"
    _label="$2"   # for logging only, e.g. "wifi" or "lan"
    _ip=$(resolve_ip "$_mac")

    if [ -z "$_ip" ]; then
        log "[$_label] skip $_mac: could not resolve an IP (no lease, no neighbor entry)"
        mark_failed
        return
    fi

    if command -v conntrack >/dev/null 2>&1; then
        _ct_hit=1
        conntrack -D -s "$_ip" >/dev/null 2>&1 && _ct_hit=0
        conntrack -D -d "$_ip" >/dev/null 2>&1 && _ct_hit=0
        if [ "$_ct_hit" = 0 ]; then
            log "[$_label] conntrack entries for $_ip ($_mac) deleted"
        else
            log "[$_label] conntrack: no matching entries for $_ip ($_mac) (normal for a fresh connection)"
        fi
    else
        log "[$_label] conntrack flush skipped for $_ip ($_mac): conntrack tool not installed (opkg install conntrack)"
        mark_partial
    fi

    if ip neigh flush to "$_ip" >/dev/null 2>&1; then
        log "[$_label] ARP/ND entry for $_ip ($_mac) flushed"
    else
        log "[$_label] warning: 'ip neigh flush to $_ip' failed or unsupported"
        mark_partial
    fi

    if [ -f "$LEASEFILE" ] && grep -qi "$_mac" "$LEASEFILE"; then
        TMP_LEASE="${LEASEFILE}.wcw.tmp"
        grep -vi "$_mac" "$LEASEFILE" > "$TMP_LEASE" && mv "$TMP_LEASE" "$LEASEFILE"
        log "[$_label] DHCP lease for $_mac removed from $LEASEFILE"
    fi
}

# --- apply the selected mode --------------------------------------------------

WIFI_IFACES=$(wifi_ifaces)

if [ "$MODE" = "wifi" ] || [ "$MODE" = "both" ]; then
    if [ -n "$TRIGGER_MAC" ]; then
        clean_one_client "$TRIGGER_MAC" "wifi"
    else
        log "[wifi] skip: no trigger MAC available for this event"
        mark_failed
    fi
fi

if [ "$MODE" = "lan" ] || [ "$MODE" = "both" ]; then
    if ! command -v bridge >/dev/null 2>&1; then
        log "[lan] skipped entirely: 'bridge' command not found (opkg install ip-full) -- cannot tell wired clients apart from Wi-Fi ones"
        mark_partial
    elif [ ! -f "$LEASEFILE" ]; then
        log "[lan] skipped: no $LEASEFILE to enumerate known clients from"
    else
        awk '{print $2}' "$LEASEFILE" | while IFS= read -r LMAC; do
            [ -n "$LMAC" ] || continue
            CLASS=$(classify_mac "$LMAC")
            if [ "$CLASS" = "lan" ]; then
                clean_one_client "$LMAC" "lan"
            fi
        done
    fi
fi

# --- DNS cache (dnsmasq) -- inherently global regardless of mode -----------
if [ "$ENABLE_DNS_CACHE_CLEAR" = "1" ]; then
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        log "dnsmasq restarted (DNS cache cleared for all clients, lease table reloaded; sub-second, no lease loss for clients not targeted above)"
    elif killall -HUP dnsmasq 2>/dev/null; then
        log "dnsmasq sent SIGHUP directly (DNS cache cleared for all clients)"
    else
        log "warning: dnsmasq not found or not reloadable"
        mark_partial
    fi
else
    log "DNS cache clear skipped (ENABLE_DNS_CACHE_CLEAR=0)"
fi

# --- optional: kernel page/dentry/inode cache -------------------------------
if [ "$ENABLE_DROP_CACHES" = "1" ] && [ -w /proc/sys/vm/drop_caches ]; then
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    log "kernel filesystem cache dropped (vm.drop_caches=3)"
fi

if [ -f "$FLAG_FAILED" ]; then
    RESULT=failed
elif [ -f "$FLAG_PARTIAL" ]; then
    RESULT=partial
else
    RESULT=ok
fi
rm -f "$FLAG_PARTIAL" "$FLAG_FAILED"
printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$RESULT" "$REASON" "$IFNAME" "${TRIGGER_MAC:-unknown}" > "$RESULT_FILE"

log "cache clear finished: reason=$REASON iface=$IFNAME mode=$MODE result=$RESULT"
exit 0
