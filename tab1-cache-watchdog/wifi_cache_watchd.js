'use strict';
'require view';
'require ui';
'require rpc';
'require poll';

var callStatus = rpc.declare({
	object: 'luci.wifi_cache_watchd',
	method: 'status'
});

var callLog = rpc.declare({
	object: 'luci.wifi_cache_watchd',
	method: 'log'
});

var callAction = rpc.declare({
	object: 'luci.wifi_cache_watchd',
	method: 'action',
	params: [ 'name' ]
});

var callSetMode = rpc.declare({
	object: 'luci.wifi_cache_watchd',
	method: 'set_mode',
	params: [ 'mode' ]
});

var callClients = rpc.declare({
	object: 'luci.wifi_cache_watchd',
	method: 'clients'
});

function fmtRate(kbit) {
	kbit = kbit || 0;
	return kbit > 0 ? (kbit / 1000).toFixed(1) + ' Mbit/s' : '-';
}

function fmtDuration(sec) {
	sec = Math.max(0, Math.floor(sec));
	var h = Math.floor(sec / 3600);
	var m = Math.floor((sec % 3600) / 60);
	var s = sec % 60;
	if (h > 0) return h + 'h ' + m + 'm';
	if (m > 0) return m + 'm ' + s + 's';
	return s + 's';
}

function fmtSince(epoch) {
	if (!epoch) return '-';
	return fmtDuration(Date.now() / 1000 - epoch) + ' ' + _('ago');
}

function fmtMs(ms) {
	ms = ms || 0;
	return ms >= 1000 ? (ms / 1000).toFixed(1) + ' s' : ms + ' ms';
}

function fmtEpoch(epoch) {
	if (!epoch) return '-';
	return new Date(epoch * 1000).toLocaleString();
}

var MODES = [
	{ key: 'wifi', label: _('Only Wi-Fi') },
	{ key: 'lan', label: _('Only LAN') },
	{ key: 'both', label: _('Wi-Fi + LAN') }
];

return view.extend({
	load: function () {
		return callStatus();
	},

	render: function (initialStatus) {
		var statusBadge = E('span', { 'class': 'label' }, '');
		var enabledBadge = E('span', { 'class': 'label' }, '');
		var logBox = E('textarea', {
			'id': 'wcw_log',
			'style': 'width:100%; height:320px; font-family:monospace; font-size:12px; white-space:pre;',
			'readonly': 'readonly'
		}, _('loading log...'));

		var rows = {
			ct: E('td', { 'class': 'td left' }, '-'),
			arp: E('td', { 'class': 'td left' }, '-'),
			dhcp: E('td', { 'class': 'td left' }, '-'),
			dns: E('td', { 'class': 'td left' }, '-'),
			last: E('td', { 'class': 'td left' }, '-')
		};

		var modeWarn = E('p', { 'class': 'alert-message warning', 'style': 'display:none' }, '');

		var modeButtons = {};
		MODES.forEach(function (m) {
			modeButtons[m.key] = E('button', {
				'class': 'btn',
				'click': ui.createHandlerFn(this, function () { return doSetMode(m.key); })
			}, m.label);
		}, this);

		function paintStatus(st) {
			statusBadge.textContent = st.running ? _('running') : _('stopped');
			statusBadge.className = 'label ' + (st.running ? 'label-success' : 'label-danger');

			enabledBadge.textContent = st.enabled ? _('autostart: on') : _('autostart: off');
			enabledBadge.className = 'label ' + (st.enabled ? 'label-success' : 'label-warning');

			rows.ct.textContent = st.conntrack_count + ' / ' + st.conntrack_max;
			rows.arp.textContent = st.arp_count;
			rows.dhcp.textContent = st.dhcp_leases;
			rows.dns.textContent = st.dns_cache_size;
			rows.last.textContent = st.last_event || '-';

			MODES.forEach(function (m) {
				modeButtons[m.key].className = 'btn' + (st.mode === m.key ? ' cbi-button-apply' : ' cbi-button-neutral');
			});

			var warnings = [];
			if ((st.mode === 'wifi' || st.mode === 'both') && !st.has_conntrack_tools) {
				warnings.push(_('conntrack tool not installed: conntrack cleanup for Wi-Fi clients is skipped. Install: opkg install conntrack'));
			}
			if ((st.mode === 'lan' || st.mode === 'both') && !st.has_bridge_tool) {
				warnings.push(_('"bridge" command not found: LAN clients cannot be told apart from Wi-Fi ones, LAN cleanup is skipped. Install: opkg install ip-full'));
			}
			if (warnings.length) {
				modeWarn.textContent = warnings.join(' ');
				modeWarn.style.display = '';
			} else {
				modeWarn.style.display = 'none';
			}
		}

		function paintLog(res) {
			var lines = (res && res.lines) || [];
			logBox.value = lines.join('\n');
			logBox.scrollTop = logBox.scrollHeight;
		}

		var clientsBody = E('tbody', {});
		var expanded = {};

		function detailRow(c) {
			var rows = [
				[ _('MAC'), c.mac ],
				[ _('IP'), c.ip || '-' ],
				[ _('Hostname'), c.hostname || '-' ],
				[ _('Type'), c.type === 'wifi' ? _('Wi-Fi') : _('LAN (wired)') ],
				[ _('Interface'), c.iface || '-' ]
			];
			if (c.type === 'wifi') {
				rows.push([ _('SSID'), c.ssid || '-' ]);
				rows.push([ _('Signal / noise'), c.signal + ' dBm / ' + c.noise + ' dBm (SNR ' + (c.signal - c.noise) + ')' ]);
				rows.push([ _('RX rate'), fmtRate(c.rx_rate_kbit) ]);
				rows.push([ _('TX rate'), fmtRate(c.tx_rate_kbit) ]);
				rows.push([ _('Inactive for'), fmtMs(c.inactive_ms) ]);
				rows.push([ _('Connected since'), fmtSince(c.connected_since) ]);
			}
			rows.push([ _('DHCP lease expires'), fmtEpoch(c.lease_expires) ]);

			var dl = E('div', { 'style': 'padding:8px 16px; background:rgba(128,128,128,0.08);' },
				rows.map(function (r) {
					return E('div', { 'style': 'display:flex; gap:8px; padding:2px 0;' }, [
						E('div', { 'style': 'width:180px; opacity:0.7;' }, r[0]),
						E('div', {}, String(r[1]))
					]);
				})
			);

			return E('tr', {}, [
				E('td', { 'colspan': '5' }, dl)
			]);
		}

		function paintClients(res) {
			var list = (res && res.clients) || [];
			clientsBody.innerHTML = '';

			if (!list.length) {
				clientsBody.appendChild(E('tr', {}, [
					E('td', { 'colspan': '5', 'class': 'td' }, _('no clients known yet'))
				]));
				return;
			}

			list.forEach(function (c) {
				var isOpen = !!expanded[c.mac];
				var arrow = E('span', {}, isOpen ? '▾ ' : '▸ ');

				var mainRow = E('tr', {
					'style': 'cursor:pointer;',
					'click': function () {
						expanded[c.mac] = !expanded[c.mac];
						paintClients(res);
					}
				}, [
					E('td', { 'class': 'td left' }, [ arrow, c.mac ]),
					E('td', { 'class': 'td left' }, c.type === 'wifi' ? _('Wi-Fi') : _('LAN')),
					E('td', { 'class': 'td left' }, c.ip || '-'),
					E('td', { 'class': 'td left' }, c.hostname || '-'),
					E('td', { 'class': 'td left' }, c.type === 'wifi' ? (c.signal + ' dBm') : '-')
				]);

				clientsBody.appendChild(mainRow);
				if (isOpen) clientsBody.appendChild(detailRow(c));
			});
		}

		function doAction(name) {
			return callAction(name).then(function () {
				return callStatus().then(paintStatus);
			});
		}

		function doSetMode(mode) {
			return callSetMode(mode).then(function () {
				return callStatus().then(paintStatus);
			});
		}

		var startBtn = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function () { return doAction('start'); })
		}, _('Start'));

		var stopBtn = E('button', {
			'class': 'btn cbi-button cbi-button-remove',
			'click': ui.createHandlerFn(this, function () { return doAction('stop'); })
		}, _('Stop'));

		var enableBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': ui.createHandlerFn(this, function () { return doAction('enable'); })
		}, _('Enable autostart'));

		var disableBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': ui.createHandlerFn(this, function () { return doAction('disable'); })
		}, _('Disable autostart'));

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '55%' }, _('conntrack entries (current / max)')),
				rows.ct
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, _('ARP / ND neighbor entries')),
				rows.arp
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, _('active DHCP leases')),
				rows.dhcp
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, _('dnsmasq cache size (configured)')),
				rows.dns
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, _('last Wi-Fi event seen')),
				rows.last
			])
		]);

		var clientsTable = E('table', { 'class': 'table' }, [
			E('thead', {}, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, _('MAC')),
					E('th', { 'class': 'th' }, _('Type')),
					E('th', { 'class': 'th' }, _('IP')),
					E('th', { 'class': 'th' }, _('Hostname')),
					E('th', { 'class': 'th' }, _('Signal'))
				])
			]),
			clientsBody
		]);

		paintStatus(initialStatus);
		paintClients({ clients: [] });

		poll.add(function () {
			return callStatus().then(paintStatus);
		}, 3);

		poll.add(function () {
			return callLog().then(paintLog);
		}, 2);

		poll.add(function () {
			return callClients().then(paintClients);
		}, 4);

		return E('div', {}, [
			E('h2', {}, _('Wi-Fi Cache Watchdog')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _(
					'Слушает события подключения/отключения клиентов к Wi-Fi (hostapd) на любой ' +
					'точке доступа и при каждом таком событии стирает ВРЕМЕННОЕ сетевое ' +
					'состояние этого клиента на роутере: запись conntrack, запись ARP/ND и ' +
					'строку DHCP-аренды. DNS-кэш dnsmasq тоже чистится, но он всегда общий для ' +
					'всех клиентов (привязать к одному конкретно нельзя) - отключается флагом ' +
					'ENABLE_DNS_CACHE_CLEAR в самом скрипте. Кого именно из клиентов трогать ' +
					'(того Wi-Fi клиента, что вызвал событие, проводных на LAN, или обоих сразу) ' +
					'выбирается переключателем "Cleanup scope" ниже. Настройки роутера ' +
					'(/etc/config/*) не трогаются никогда - только временное состояние в памяти.'
				))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ statusBadge, ' ', enabledBadge ]),
				E('div', { 'class': 'cbi-page-actions' }, [ startBtn, ' ', stopBtn, ' ', enableBtn, ' ', disableBtn ])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Cleanup scope')),
				E('div', { 'class': 'cbi-page-actions' }, [
					modeButtons.wifi, ' ', modeButtons.lan, ' ', modeButtons.both
				]),
				modeWarn
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Live cache state')),
				table
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Подключённые устройства')),
				E('p', { 'class': 'cbi-value-description' }, _('Клик по строке раскрывает полные характеристики устройства.')),
				clientsTable
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Live event log')),
				logBox
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
