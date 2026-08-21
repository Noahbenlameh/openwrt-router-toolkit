#!/bin/bash
# Run this on the Mac to produce webconsole.tar.gz (Tab 2: "Терминал"),
# packaged separately from wifi_cache_watchd.tar.gz (Tab 1) on purpose --
# so either can be installed/removed independently of the other.
# On the router: tar -xzf webconsole.tar.gz -C /
set -euo pipefail
cd "$(dirname "$0")"

rm -rf payload_terminal webconsole.tar.gz

mkdir -p \
    payload_terminal/etc/init.d \
    payload_terminal/usr/libexec/rpcd \
    payload_terminal/usr/share/rpcd/acl.d \
    payload_terminal/usr/share/luci/menu.d \
    payload_terminal/www/luci-static/resources/view

cp webconsole.init                 payload_terminal/etc/init.d/webconsole
cp luci.webconsole                 payload_terminal/usr/libexec/rpcd/luci.webconsole
cp luci-app-webconsole.acl.json    payload_terminal/usr/share/rpcd/acl.d/luci-app-webconsole.json
cp luci-app-webconsole.menu.json   payload_terminal/usr/share/luci/menu.d/luci-app-webconsole.json
cp webconsole.js                   payload_terminal/www/luci-static/resources/view/webconsole.js

chmod +x \
    payload_terminal/etc/init.d/webconsole \
    payload_terminal/usr/libexec/rpcd/luci.webconsole

tar -czf webconsole.tar.gz -C payload_terminal .
rm -rf payload_terminal

echo "Built: $(pwd)/webconsole.tar.gz"
tar -tzf webconsole.tar.gz
