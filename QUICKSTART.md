# Быстрая установка: Терминал → Wi-Fi Cache Watchdog

Порядок обязателен: сначала «Терминал» (через PuTTY, один раз), потом всё
остальное — уже через сам «Терминал», без PuTTY. Оба архива присылаю я.

Замени в командах: `<router-ip>` — IP роутера, `C:\путь\...` — куда сохранил
архив на Windows.

---

## Часть 1 — «Терминал» (один раз, через PuTTY)

Если PuTTY не стоит — поставь с putty.org, настройки по умолчанию (даст
`putty.exe` + `pscp.exe`).

**PowerShell** (папка с `pscp.exe`, обычно `C:\Program Files\PuTTY`):
```powershell
cd "C:\Program Files\PuTTY"
.\pscp.exe -scp C:\путь\к\webconsole.tar.gz root@<router-ip>:/tmp/
```
- Флаг **`-scp` обязателен** — на OpenWrt (dropbear) нет `sftp-server`, без
  флага будет ошибка `ash: /usr/libexec/sftp-server: not found`.
- Host key в первый раз — `y`. Пароль — root от роутера.

**PuTTY**, SSH-сессия (root@<router-ip>):
```sh
cd /tmp
tar -xzf webconsole.tar.gz -C / && rm webconsole.tar.gz
opkg update
opkg install ttyd
chmod +x /etc/init.d/webconsole /usr/libexec/rpcd/luci.webconsole
```

Свой пароль для терминала — придумай и введи сам, мне не присылай:
```sh
printf 'root:ЗАМЕНИ_НА_СВОЙ_ПАРОЛЬ\n' > /etc/webconsole.auth
chmod 600 /etc/webconsole.auth
```

```sh
/etc/init.d/webconsole enable
/etc/init.d/webconsole start
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*

grep -qxF /etc/webconsole.auth /etc/sysupgrade.conf 2>/dev/null || echo /etc/webconsole.auth >> /etc/sysupgrade.conf
for f in \
  /etc/init.d/webconsole \
  /usr/libexec/rpcd/luci.webconsole \
  /usr/share/rpcd/acl.d/luci-app-webconsole.json \
  /usr/share/luci/menu.d/luci-app-webconsole.json \
  /www/luci-static/resources/view/webconsole.js
do
  grep -qxF "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
done
```

**Проверка:** `http://<router-ip>` → **System → Терминал** → должно быть
`running` / `autostart: on` / `password: set`. Терминал внизу страницы
попросит логин отдельным окном — это пароль из `/etc/webconsole.auth`, не
LuCI-пароль. Если LuCI на **https** — открой один раз отдельной вкладкой
`http://<router-ip>:7681/`, прими предупреждение сертификата, иначе iframe
терминала не загрузится (mixed content).

---

## Часть 2 — Wi-Fi Cache Watchdog (через уже установленный «Терминал», без PuTTY)

1. Сохрани присланный `wifi_cache_watchd.tar.gz` на Windows.
2. LuCI → **System → Терминал** → **Upload file / archive** → выбрать файл →
   **Upload to router**. Файл всегда ложится под одним и тем же именем —
   `/tmp/webconsole_upload`, независимо от исходного имени файла.
3. В окне терминала на той же странице:
```sh
tar -xzf /tmp/webconsole_upload -C / && rm /tmp/webconsole_upload

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
Пакет называется именно **`conntrack`** (не `conntrack-tools` — так называется
апстрим-проект, а opkg-пакет в OpenWrt называется короче).

**Проверка:** `http://<router-ip>` → **Status → Wi-Fi Cache Watchdog** →
`running` / `autostart: on`. Живой лог в терминале:
```sh
ps | grep wifi_cache_watchd
logread -f | grep wifi_cache_watchd
```
(Ctrl+C — остановить)

---

## Дальнейшие обновления любой вкладки

Всегда одинаково, через страницу «Терминал», без PuTTY:
1. Сохрани новый архив (пришлю я) на Windows.
2. LuCI → **System → Терминал** → **Upload file / archive** → выбрать файл →
   **Upload to router**. Всегда ложится под одним именем — `/tmp/webconsole_upload`.
3. В окне терминала введи команды **по одной строке за раз** (не единой
   строкой через `&&` — в этом браузерном терминале длинная строка при
   вставке иногда рвётся посередине и часть команды теряется):

**Обновление Wi-Fi Cache Watchdog:**
```sh
tar -xzf /tmp/webconsole_upload -C /
```
```sh
rm /tmp/webconsole_upload
```
```sh
/etc/init.d/wifi_cache_watchd restart
```
```sh
/etc/init.d/rpcd restart
```
```sh
rm -f /tmp/luci-indexcache*
```

**Обновление Терминала** (тот же принцип, другой сервис на 3-м шаге):
```sh
tar -xzf /tmp/webconsole_upload -C /
```
```sh
rm /tmp/webconsole_upload
```
```sh
/etc/init.d/webconsole restart
```
```sh
/etc/init.d/rpcd restart
```
```sh
rm -f /tmp/luci-indexcache*
```

Для любой будущей вкладки — те же 5 команд, просто замени имя сервиса в
3-й строке на её собственный `/etc/init.d/<имя>`.

После — обнови страницу LuCI (F5), чтобы увидеть изменения.

`/tmp` — это RAM (tmpfs), не флеш: даже если забудешь `rm`, ничего не
накопится на постоянной памяти, файл пропадёт сам при перезагрузке.

---

## Удаление

**Wi-Fi Cache Watchdog:**
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

**Терминал** (делай это через PuTTY, а не через саму вкладку):
```sh
/etc/init.d/webconsole stop
/etc/init.d/webconsole disable
rm -f /etc/init.d/webconsole \
      /usr/libexec/rpcd/luci.webconsole \
      /usr/share/rpcd/acl.d/luci-app-webconsole.json \
      /usr/share/luci/menu.d/luci-app-webconsole.json \
      /www/luci-static/resources/view/webconsole.js \
      /etc/webconsole.auth
opkg remove ttyd
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

В обоих случаях пути из `/etc/sysupgrade.conf` удали вручную, если нужно
(`vi /etc/sysupgrade.conf`).
