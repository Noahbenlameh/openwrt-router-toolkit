# Терминал — установка / как пользоваться дальше

Архив `webconsole.tar.gz` собираю и присылаю я. От тебя — сохранить его на
Windows-ноутбук и один раз пройти Часть A через PuTTY. После этого Часть A
больше не нужна: обновления (в том числе Вкладки 1) делаются через саму
вкладку «Терминал» — см. Часть B.

**Если Вкладка 2 уже была установлена и что-то в ней поломалось** (как с
ошибкой `Access to path denied by ACL`) — обновление делается теми же
командами, что и установка, то есть снова через Часть A (PuTTY): шаг с
`printf 'root:...' > /etc/webconsole.auth` можно пропустить, он уже сделан
раньше, всё остальное — повторить как есть, файлы просто перезапишутся.

## Часть A — установка (один раз, через PuTTY)

PowerShell:
```powershell
cd "C:\Program Files\PuTTY"
.\pscp.exe -scp C:\Users\<Имя>\Downloads\webconsole.tar.gz root@<router-ip>:/tmp/
```
Host key — `y`. Пароль — root от роутера.

Флаг `-scp` обязателен: на OpenWrt (dropbear) обычно нет `sftp-server`, а
`pscp` по умолчанию сперва пробует SFTP — без флага упадёт с ошибкой вида
`ash: /usr/libexec/sftp-server: not found`.

PuTTY, SSH-сессия (root@<router-ip>):
```sh
cd /tmp
tar -xzf webconsole.tar.gz -C / && rm webconsole.tar.gz

opkg update
opkg install ttyd
chmod +x /etc/init.d/webconsole /usr/libexec/rpcd/luci.webconsole
```

Придумай и введи здесь свой пароль для терминала (мне не присылай):
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

Проверка: `http://<router-ip>` → **System → Терминал** →
`running` / `autostart: on` / `password: set`. Первое открытие терминала
спросит логин отдельным окном — это пароль из `/etc/webconsole.auth`, не
LuCI-пароль.

Если LuCI на https — открой один раз `http://<router-ip>:7681/` отдельной
вкладкой и прими предупреждение браузера, иначе iframe не загрузится
(mixed content).

## Часть B — как ставить/обновлять всё остальное дальше (без PuTTY)

Пример на Вкладке 1, но так же для любого будущего архива:

1. Сохрани присланный мной `wifi_cache_watchd.tar.gz` на Windows.
2. LuCI → **System → Терминал** → **Upload file / archive** → выбрать файл
   → **Upload to router**. Файл всегда ложится под одним и тем же именем —
   `/tmp/webconsole_upload` (не зависит от исходного имени файла).
3. В окне терминала на той же странице (логин — пароль из `/etc/webconsole.auth`):
```sh
tar -xzf /tmp/webconsole_upload -C / && rm /tmp/webconsole_upload
/etc/init.d/wifi_cache_watchd restart
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache*
```

`/tmp` — это RAM (tmpfs), не флеш, так что даже без `rm` ничего не
накапливается на постоянной памяти и всё пропадает при перезагрузке;
`&&` просто убирает файл сразу же, без отдельного шага. Каждая новая
загрузка через кнопку и так перезаписывает `/tmp/webconsole_upload`, так
что там никогда не может скопиться больше одного файла одновременно.

## Удаление вкладки «Терминал»

Через PuTTY (логично — удаляешь то, чем только что пользовался):
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
Пути из `/etc/sysupgrade.conf` удали вручную, если нужно (`vi /etc/sysupgrade.conf`).
