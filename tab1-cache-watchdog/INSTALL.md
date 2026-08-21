# Wi-Fi Cache Watchdog — установка / обновление

Архив `wifi_cache_watchd.tar.gz` собираю и присылаю я. От тебя — сохранить
его на Windows-ноутбук и выполнить команды ниже. Пути с `<router-ip>` и
`<Имя>`/`Downloads` замени на свои.

## PuTTY (один раз, если ещё не стоит)

Скачать с putty.org, установить с настройками по умолчанию. Нужны
`putty.exe` (SSH) и `pscp.exe` (SCP) — оба ставятся вместе.

## PowerShell — закачать архив на роутер

```powershell
cd "C:\Program Files\PuTTY"
.\pscp.exe -scp C:\Users\<Имя>\Downloads\wifi_cache_watchd.tar.gz root@<router-ip>:/tmp/
```
Host key (первый раз) — `y`. Пароль — root от роутера.

Флаг `-scp` обязателен: на OpenWrt (dropbear) обычно нет `sftp-server`, а
`pscp` по умолчанию сперва пробует SFTP — без флага упадёт с ошибкой вида
`ash: /usr/libexec/sftp-server: not found`.

## PuTTY — SSH-сессия (root@<router-ip>)

**Первая установка:**
```sh
cd /tmp
tar -xzf wifi_cache_watchd.tar.gz -C / && rm wifi_cache_watchd.tar.gz

opkg update
opkg install conntrack ip-full
/etc/init.d/wifi_cache_watchd enable

for f in \
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

/etc/init.d/wifi_cache_watchd restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

**Повторное обновление** (пакеты и enable уже сделаны раньше):
```sh
cd /tmp
tar -xzf wifi_cache_watchd.tar.gz -C / && rm wifi_cache_watchd.tar.gz
/etc/init.d/wifi_cache_watchd restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

`/tmp` на роутере — это оперативная память (tmpfs), не флеш: даже если
забыть `rm`, файл пропадёт сам после перезагрузки и не расходует место
на постоянном хранилище. `&&` просто гарантирует удаление сразу после
успешной распаковки, без отдельного шага, который можно забыть.

Если что-то пошло не так и архивы всё же скопились в `/tmp` — почистить
разом:
```sh
rm -f /tmp/*.tar.gz
```

## Проверка

```sh
ps | grep wifi_cache_watchd
logread -f | grep wifi_cache_watchd
```
Ctrl+C останавливает live-лог. Страница: `http://<router-ip>` →
**Status → Wi-Fi Cache Watchdog**.

## Удаление

```sh
/etc/init.d/wifi_cache_watchd stop
/etc/init.d/wifi_cache_watchd disable
rm -f /usr/bin/clear_net_cache.sh \
      /usr/sbin/wifi_cache_watchd.sh \
      /etc/init.d/wifi_cache_watchd \
      /usr/libexec/rpcd/luci.wifi_cache_watchd \
      /usr/share/rpcd/acl.d/luci-app-wifi-cache-watchd.json \
      /usr/share/luci/menu.d/luci-app-wifi-cache-watchd.json \
      /www/luci-static/resources/view/wifi_cache_watchd.js \
      /etc/wifi_cache_watchd.mode
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```
Пути из `/etc/sysupgrade.conf` удали вручную, если нужно (`vi /etc/sysupgrade.conf`).
