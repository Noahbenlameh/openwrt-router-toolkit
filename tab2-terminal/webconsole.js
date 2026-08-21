'use strict';
'require view';
'require ui';
'require rpc';
'require poll';

var callStatus = rpc.declare({
	object: 'luci.webconsole',
	method: 'status'
});

var callAction = rpc.declare({
	object: 'luci.webconsole',
	method: 'action',
	params: [ 'name' ]
});

return view.extend({
	load: function () {
		return callStatus();
	},

	render: function (initialStatus) {
		var statusBadge = E('span', { 'class': 'label' }, '');
		var enabledBadge = E('span', { 'class': 'label' }, '');
		var authBadge = E('span', { 'class': 'label' }, '');
		var lastRunning = null;

		var iframe = E('iframe', {
			'style': 'width:100%; height:520px; border:1px solid #888; background:#111;',
			'src': 'about:blank'
		});

		function updateIframe(st) {
			if (st.running === lastRunning)
				return;
			lastRunning = st.running;
			iframe.src = st.running
				? ('http://' + window.location.hostname + ':' + st.port + '/')
				: 'about:blank';
		}

		function paintStatus(st) {
			statusBadge.textContent = st.running ? _('running') : _('stopped');
			statusBadge.className = 'label ' + (st.running ? 'label-success' : 'label-danger');

			enabledBadge.textContent = st.enabled ? _('autostart: on') : _('autostart: off');
			enabledBadge.className = 'label ' + (st.enabled ? 'label-success' : 'label-warning');

			authBadge.textContent = st.has_auth ? _('password: set') : _('password: NOT SET');
			authBadge.className = 'label ' + (st.has_auth ? 'label-success' : 'label-danger');

			updateIframe(st);
		}

		function doAction(name) {
			return callAction(name).then(function () {
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

		var fileInput = E('input', { 'type': 'file', 'id': 'wc_file' });
		var uploadStatus = E('span', { 'style': 'margin-left:8px;' }, '');

		// Fixed destination path: LuCI's upload ACL (cgi-io) only allows
		// paths explicitly whitelisted in acl.d, so this can't be a
		// per-filename dynamic path -- see luci-app-webconsole.acl.json.
		var UPLOAD_DEST = '/tmp/webconsole_upload';

		var uploadBtn = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, function () {
				var f = fileInput.files && fileInput.files[0];
				if (!f) {
					uploadStatus.textContent = _('choose a file first');
					return;
				}
				uploadStatus.textContent = _('uploading...');
				return ui.uploadFile(UPLOAD_DEST, f).then(function () {
					uploadStatus.textContent = _('done: ') + UPLOAD_DEST + _(' (was: ') + f.name + ')';
				}).catch(function (err) {
					uploadStatus.textContent = _('upload failed: ') + err;
				});
			})
		}, _('Upload to router'));

		paintStatus(initialStatus);

		poll.add(function () {
			return callStatus().then(paintStatus);
		}, 5);

		return E('div', {}, [
			E('h2', {}, _('Терминал')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ statusBadge, ' ', enabledBadge, ' ', authBadge ]),
				E('div', { 'class': 'cbi-page-actions' }, [ startBtn, ' ', stopBtn, ' ', enableBtn, ' ', disableBtn ]),
				E('p', { 'class': 'cbi-value-description' }, _(
					'If "password: NOT SET" is shown, the service will not start. ' +
					'Set your own credential once over SSH: printf "root:YOUR_PASSWORD\\n" > /etc/webconsole.auth ; chmod 600 /etc/webconsole.auth'
				))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Upload file / archive')),
				E('p', {}, [ fileInput, ' ', uploadBtn, uploadStatus ]),
				E('p', { 'class': 'cbi-value-description' }, _('Every upload lands at the SAME fixed path, /tmp/webconsole_upload, overwriting whatever was there before - use that path in the terminal below.'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Terminal')),
				E('p', { 'class': 'cbi-value-description' }, _('The terminal asks for its OWN login the first time you open it - that is the credential from /etc/webconsole.auth, not your LuCI password.')),
				iframe
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
