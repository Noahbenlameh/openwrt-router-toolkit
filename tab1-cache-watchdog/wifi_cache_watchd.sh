#!/bin/sh
# wifi_cache_watchd.sh - watches the system log for hostapd's
# AP-STA-CONNECTED / AP-STA-DISCONNECTED lines (emitted for ANY VAP on ANY
# radio, no dependency on /etc/config/wireless contents) and triggers
# clear_net_cache.sh, with debounce so a rapid reassociate doesn't fire the
# cleanup multiple times back-to-back.
#
# Originally used `ubus listen 'hostapd.*'`, but that requires hostapd's
# ubus notify support, which turned out to be MISSING on some real-world
# builds (confirmed absent on wpad-basic-mbedtls, OpenWrt 24.10.3) even
# though the hostapd.<iface> ubus object itself still exists. hostapd's
# plain syslog output (AP-STA-CONNECTED/DISCONNECTED) is present on every
# build regardless of ubus notify support, so it's used as the event
# source instead -- more portable, not just a workaround for one router.
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

log "started, watching syslog for hostapd AP-STA-CONNECTED/DISCONNECTED lines (debounce=${DEBOUNCE}s)"

# hostapd logs lines like:
#   hostapd: phy0-ap4: AP-STA-CONNECTED 06:6c:9a:66:12:35 auth_alg=open
#   hostapd: phy0-ap4: AP-STA-DISCONNECTED 06:6c:9a:66:12:35
# for every VAP on every radio, unconditionally, regardless of ubus notify
# support in the installed hostapd/wpad build.
logread -f 2>/dev/null | while IFS= read -r LINE; do
    case "$LINE" in
        *' hostapd: '*': AP-STA-CONNECTED '*)
            EVT=assoc
            ;;
        *' hostapd: '*': AP-STA-DISCONNECTED '*)
            EVT=disassoc
            ;;
        *)
            continue
            ;;
    esac

    IFACE=$(printf '%s' "$LINE" | sed -n 's/.*hostapd: \([^:]*\): AP-STA-[A-Z]*.*/\1/p')
    [ -n "$IFACE" ] || IFACE=unknown

    MAC=$(printf '%s' "$LINE" | sed -n 's/.*AP-STA-[A-Z]* \([0-9A-Fa-f:]*\).*/\1/p')

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

log "logread -f exited (syslog daemon restarted or gone) -- procd will respawn this instance"
exit 1
