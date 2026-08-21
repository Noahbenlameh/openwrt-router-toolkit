#!/bin/sh
# wifi_cache_watchd.sh - listens for hostapd assoc/disassoc ubus events on
# ANY wireless interface (works regardless of how many VAPs/BSSIDs exist,
# no dependency on /etc/config/wireless contents) and triggers
# clear_net_cache.sh, with debounce so a rapid reassociate doesn't fire the
# cleanup multiple times back-to-back.
#
# Meant to be run under procd via /etc/init.d/wifi_cache_watchd, but can also
# be run directly in a foreground shell for testing.

BIN_CLEAR=/usr/bin/clear_net_cache.sh
GEN_DIR=/tmp/.wifi_cache_watchd_gen
CONNECTED_DIR=/tmp/.wcw_connected
DEBOUNCE="${WIFI_CACHE_WATCHD_DEBOUNCE:-1}"   # seconds of quiet time before firing
LOGTAG="wifi_cache_watchd"

log() {
    logger -t "$LOGTAG" "$1"
}

mkdir -p "$GEN_DIR"
rm -f "$GEN_DIR"/*  2>/dev/null

# Per-MAC "connected since" timestamps, used by the rpcd `clients` method for
# the uptime column. Cleared on (re)start: any client that was already
# connected before this restart will get a fresh timestamp on its next
# natural assoc event rather than a stale/fabricated one.
mkdir -p "$CONNECTED_DIR"
rm -f "$CONNECTED_DIR"/*  2>/dev/null

# Coalesces bursts of events into a single trailing-edge run, keyed PER CLIENT
# MAC: each call bumps that MAC's own generation counter, so a rapid
# reassociate of the SAME device collapses into one run, while two different
# devices reconnecting close together each still get their own scoped run
# (needed now that cleanup only touches the triggering client, not everyone).
schedule_run() {
    _reason="$1"
    _iface="$2"
    _mac="$3"
    _key=$(printf '%s' "${_mac:-unknown}" | tr -dc 'A-Za-z0-9')
    [ -n "$_key" ] || _key="unknown_$$"
    _gen_file="$GEN_DIR/$_key"
    _gen=$(( $(cat "$_gen_file" 2>/dev/null || echo 0) + 1 ))
    echo "$_gen" > "$_gen_file"
    (
        sleep "$DEBOUNCE"
        _cur=$(cat "$_gen_file" 2>/dev/null || echo -1)
        if [ "$_cur" = "$_gen" ]; then
            "$BIN_CLEAR" "$_reason" "$_iface" "$_mac"
        fi
    ) &
}

log "started, listening on ubus for hostapd assoc/disassoc events (debounce=${DEBOUNCE}s)"

# Restrict the event stream to hostapd.* objects only -- this naturally
# excludes wired interfaces and any non-Wi-Fi ubus traffic.
ubus listen 'hostapd.*' 2>/dev/null | while IFS= read -r LINE; do
    case "$LINE" in
        *'"hostapd.'*'"disassoc"'*)
            EVT=disassoc
            ;;
        *'"hostapd.'*'"assoc"'*)
            EVT=assoc
            ;;
        *)
            continue
            ;;
    esac

    IFACE=$(printf '%s' "$LINE" | sed -n 's/.*"hostapd\.\([A-Za-z0-9_.:-]*\)".*/\1/p')
    [ -n "$IFACE" ] || IFACE=unknown

    MAC=$(printf '%s' "$LINE" | sed -n 's/.*"address" *: *"\([0-9A-Fa-f:]*\)".*/\1/p')

    if [ -n "$MAC" ]; then
        MKEY=$(printf '%s' "$MAC" | tr 'A-Z' 'a-z' | tr -dc 'a-z0-9')
        if [ "$EVT" = "assoc" ]; then
            date +%s > "$CONNECTED_DIR/$MKEY" 2>/dev/null
        else
            rm -f "$CONNECTED_DIR/$MKEY" 2>/dev/null
        fi
    fi

    log "event received: $EVT on $IFACE mac=${MAC:-unknown}"
    schedule_run "$EVT" "$IFACE" "$MAC"
done

log "ubus listen exited (hostapd/ubus daemon restarted or gone) -- procd will respawn this instance"
exit 1
