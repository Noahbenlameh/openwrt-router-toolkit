#!/bin/sh
# install.sh - one-shot installer for BOTH LuCI tabs (Терминал + Wi-Fi Cache
# Watchdog), run directly ON the router. Downloads the repo's tarball from
# GitHub (no git needed on the router), places every file at its correct
# absolute path, installs the needed opkg packages, enables/starts both
# services, and registers everything in /etc/sysupgrade.conf so it survives
# a sysupgrade.
#
# Usage on the router (two steps, NOT piped through `sh` directly, so the
# password prompt below works):
#   wget -O install.sh https://raw.githubusercontent.com/Noahbenlameh/openwrt-router-toolkit/master/install.sh
#   sh install.sh
#
# Safe to re-run: overwrites files with the latest version, skips the
# password prompt if /etc/webconsole.auth already exists, skips already-done
# sysupgrade.conf entries.

set -e

OWNER="Noahbenlameh"
REPO="openwrt-router-toolkit"
BRANCH="master"
TARBALL_URL="https://github.com/$OWNER/$REPO/archive/refs/heads/$BRANCH.tar.gz"
WORKDIR=/tmp/install_openwrt_toolkit
ARCHIVE=/tmp/openwrt_toolkit_repo.tar.gz

log() { echo "[install] $1"; }

log "Скачиваю $TARBALL_URL"
if command -v wget >/dev/null 2>&1; then
    wget -O "$ARCHIVE" "$TARBALL_URL"
elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O "$ARCHIVE" "$TARBALL_URL"
else
    echo "Нет ни wget, ни uclient-fetch - нечем скачать архив." >&2
    exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
tar -xzf "$ARCHIVE" -C "$WORKDIR"
rm -f "$ARCHIVE"

SRC=$(find "$WORKDIR" -maxdepth 1 -mindepth 1 -type d | head -n1)
if [ -z "$SRC" ]; then
    echo "Не нашёл распакованную папку репозитория внутри архива." >&2
    exit 1
fi

log "Устанавливаю вкладку «Терминал»..."
mkdir -p /etc/init.d /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d /www/luci-static/resources/view

cp "$SRC/tab2-terminal/webconsole.init" /etc/init.d/webconsole
cp "$SRC/tab2-terminal/luci.webconsole" /usr/libexec/rpcd/luci.webconsole
cp "$SRC/tab2-terminal/luci-app-webconsole.acl.json" /usr/share/rpcd/acl.d/luci-app-webconsole.json
cp "$SRC/tab2-terminal/luci-app-webconsole.menu.json" /usr/share/luci/menu.d/luci-app-webconsole.json
cp "$SRC/tab2-terminal/webconsole.js" /www/luci-static/resources/view/webconsole.js
chmod +x /etc/init.d/webconsole /usr/libexec/rpcd/luci.webconsole

log "Устанавливаю вкладку «Wi-Fi Cache Watchdog»..."
mkdir -p /usr/bin /usr/sbin

cp "$SRC/tab1-cache-watchdog/clear_net_cache.sh" /usr/bin/clear_net_cache.sh
cp "$SRC/tab1-cache-watchdog/wifi_cache_watchd.sh" /usr/sbin/wifi_cache_watchd.sh
cp "$SRC/tab1-cache-watchdog/wifi_cache_watchd.init" /etc/init.d/wifi_cache_watchd
cp "$SRC/tab1-cache-watchdog/luci.wifi_cache_watchd" /usr/libexec/rpcd/luci.wifi_cache_watchd
cp "$SRC/tab1-cache-watchdog/luci-app-wifi-cache-watchd.acl.json" /usr/share/rpcd/acl.d/luci-app-wifi-cache-watchd.json
cp "$SRC/tab1-cache-watchdog/luci-app-wifi-cache-watchd.menu.json" /usr/share/luci/menu.d/luci-app-wifi-cache-watchd.json
cp "$SRC/tab1-cache-watchdog/wifi_cache_watchd.js" /www/luci-static/resources/view/wifi_cache_watchd.js
chmod +x /usr/bin/clear_net_cache.sh /usr/sbin/wifi_cache_watchd.sh /etc/init.d/wifi_cache_watchd /usr/libexec/rpcd/luci.wifi_cache_watchd

rm -rf "$WORKDIR"

log "Ставлю opkg-пакеты (ttyd, conntrack, ip-full)..."
opkg update
opkg install ttyd conntrack ip-full || log "предупреждение: какой-то пакет не встал, проверь вручную (opkg install <имя>)"

if [ ! -s /etc/webconsole.auth ]; then
    echo
    echo "Пароль для веб-терминала ещё не задан (нужен один раз)."
    printf 'Придумай логин:пароль (например root:MyPass123) и введи здесь: '
    read -r CRED
    if [ -n "$CRED" ]; then
        printf '%s\n' "$CRED" > /etc/webconsole.auth
        chmod 600 /etc/webconsole.auth
        log "Сохранено в /etc/webconsole.auth"
    else
        log "Пароль не введён - вкладка «Терминал» не запустится, пока вручную не создашь /etc/webconsole.auth"
    fi
fi

/etc/init.d/webconsole enable
/etc/init.d/webconsole start
/etc/init.d/wifi_cache_watchd enable
/etc/init.d/wifi_cache_watchd restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*

for f in \
  /etc/init.d/webconsole \
  /usr/libexec/rpcd/luci.webconsole \
  /usr/share/rpcd/acl.d/luci-app-webconsole.json \
  /usr/share/luci/menu.d/luci-app-webconsole.json \
  /www/luci-static/resources/view/webconsole.js \
  /etc/webconsole.auth \
  /usr/bin/clear_net_cache.sh \
  /usr/sbin/wifi_cache_watchd.sh \
  /etc/init.d/wifi_cache_watchd \
  /usr/libexec/rpcd/luci.wifi_cache_watchd \
  /usr/share/rpcd/acl.d/luci-app-wifi-cache-watchd.json \
  /usr/share/luci/menu.d/luci-app-wifi-cache-watchd.json \
  /www/luci-static/resources/view/wifi_cache_watchd.js \
  /etc/wifi_cache_watchd.mode
do
  grep -qxF "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
done

log "Готово. Открой http://<router-ip> в браузере: System -> Терминал и Status -> Wi-Fi Cache Watchdog."
