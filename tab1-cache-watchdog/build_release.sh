#!/bin/bash
# Run this on the Mac after any file changes to produce a single
# wifi_cache_watchd.tar.gz that mirrors the router's absolute paths.
# On the router: tar -xzf wifi_cache_watchd.tar.gz -C /
set -euo pipefail
cd "$(dirname "$0")"

rm -rf payload wifi_cache_watchd.tar.gz

mkdir -p \
    payload/usr/bin \
    payload/usr/sbin \
    payload/etc/init.d \
    payload/usr/libexec/rpcd \
    payload/usr/share/rpcd/acl.d \
    payload/usr/share/luci/menu.d \
    payload/www/luci-static/resources/view

cp clear_net_cache.sh                   payload/usr/bin/clear_net_cache.sh
cp wifi_cache_watchd.sh                 payload/usr/sbin/wifi_cache_watchd.sh
cp wifi_cache_watchd.init               payload/etc/init.d/wifi_cache_watchd
cp luci.wifi_cache_watchd               payload/usr/libexec/rpcd/luci.wifi_cache_watchd
cp luci-app-wifi-cache-watchd.acl.json  payload/usr/share/rpcd/acl.d/luci-app-wifi-cache-watchd.json
cp luci-app-wifi-cache-watchd.menu.json payload/usr/share/luci/menu.d/luci-app-wifi-cache-watchd.json
cp wifi_cache_watchd.js                 payload/www/luci-static/resources/view/wifi_cache_watchd.js

chmod +x \
    payload/usr/bin/clear_net_cache.sh \
    payload/usr/sbin/wifi_cache_watchd.sh \
    payload/etc/init.d/wifi_cache_watchd \
    payload/usr/libexec/rpcd/luci.wifi_cache_watchd

tar -czf wifi_cache_watchd.tar.gz -C payload .
rm -rf payload

echo "Built: $(pwd)/wifi_cache_watchd.tar.gz"
tar -tzf wifi_cache_watchd.tar.gz
