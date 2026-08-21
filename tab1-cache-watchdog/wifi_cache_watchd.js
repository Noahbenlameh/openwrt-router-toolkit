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

		paintStatus(initialStatus);

		poll.add(function () {
			return callStatus().then(paintStatus);
		}, 3);

		poll.add(function () {
			return callLog().then(paintLog);
		}, 2);

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
				E('h3', {}, _('Live event log')),
				logBox
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
