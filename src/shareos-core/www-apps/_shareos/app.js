/*
 * ShareOS app SDK – served by the apps web server, works offline.
 *   <link rel="stylesheet" href="/_shareos/theme.css">
 *   <script src="/_shareos/app.js"></script>
 *
 * ShareOS.app                 id of this app (first part of the path)
 * ShareOS.theme               { theme: 'dark'|'light', accent } – applied to <html>
 * ShareOS.onTheme(fn)         called when the user changes the look
 * ShareOS.file                the file the app was opened with, or null:
 *   .name, .mode ('view'|'edit')   (after await ShareOS.file.info())
 *   await .text() / .blob()        content
 *   await .save(textOrBlob)        write back (mode 'edit' only)
 *   .url                           address of the content (byte ranges work,
 *                                  e.g. <audio>/<video src> for seeking)
 * ShareOS.menu(el, spec)      classic menu bar (File | Edit | View …):
 *   spec = [{ label: 'Datei', items: [{ label: 'Speichern', kbd: 'Ctrl+S',
 *            action: fn, disabled: bool, checked: bool }, '-', …] }, …]
 * ShareOS.on(type, fn) / ShareOS.emit(type, data)
 *                             messages between the apps (BroadcastChannel
 *                             'shareos'; every app hears them – no secrets)
 * ShareOS.embedded            true when shown inside the ShareOS interface
 * ShareOS.fs                  folders of the user, for apps with the permission
 *                             "files" (null otherwise); all calls return promises:
 *   .roots()                       [{name, home, usb}]
 *   .list(root, path, hidden)      {entries: [{name, type, size, mtime}], free, size}
 *   .mkdir(root, path, name)   .rename(root, path, name, to)
 *   .copy(root, path, names, destRoot, dest)   .move(…same…)
 *   .remove(root, path, names)
 *   .open(root, path, name, {write, create})   a file like ShareOS.file
 *
 * URL parameters set by ShareOS: theme, accent, file (ticket), name, origin,
 * fs (grant for ShareOS.fs).
 */
(function () {
	'use strict';
	var q = new URLSearchParams(location.search);
	var root = document.documentElement;
	var appId = location.pathname.split('/')[1] || '';
	var adminOrigin = q.get('origin') || '';
	var embedded = window.parent !== window;
	var themeFns = [];

	function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }

	function applyTheme(theme, accent) {
		if (theme !== 'light' && theme !== 'dark')
			theme = window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
		if (['blue', 'green', 'red', 'white'].indexOf(accent) < 0) accent = 'blue';
		root.setAttribute('data-theme', theme);
		root.setAttribute('data-accent', accent);
		api.theme = { theme: theme, accent: accent };
		themeFns.forEach(function (fn) { try { fn(api.theme); } catch (e) { } });
	}

	/* messages between apps */
	var chan = 'BroadcastChannel' in window ? new BroadcastChannel('shareos') : null;
	var handlers = {};
	if (chan) chan.onmessage = function (ev) {
		var m = ev.data || {};
		(handlers[m.type] || []).forEach(function (fn) { try { fn(m.data, m.from); } catch (e) { } });
	};

	/* messages from the ShareOS interface (look changed) */
	window.addEventListener('message', function (ev) {
		if (!adminOrigin || ev.origin !== adminOrigin) return;
		var m = ev.data || {};
		if (m.sos === 'theme') {
			store('sos-theme', m.theme); store('sos-accent', m.accent);
			applyTheme(m.theme, m.accent);
		}
	});
	function toAdmin(msg) {
		if (!adminOrigin) return;
		var target = embedded ? window.parent : window.opener;
		try { if (target) target.postMessage(msg, adminOrigin); } catch (e) { }
	}

	/* the opened file */
	function check(r) {
		if (r.ok) return r;
		return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.error || ('HTTP ' + r.status)); });
	}
	function makeFile(ticket, name, mode) {
		var fileUrl = '/_shareos/cgi/file?t=' + ticket;
		var file = {
		name: name || '',
		url: fileUrl,
		mode: mode || null,
		info: function () {
			return fetch(fileUrl + '&info=1', { cache: 'no-store' }).then(check).then(function (r) { return r.json(); }).then(function (j) {
				file.name = decodeURIComponent(j.name); file.mode = j.mode; file.size = j.size;
				return j;
			});
		},
		text: function () { return fetch(fileUrl, { cache: 'no-store' }).then(check).then(function (r) { return r.text(); }); },
		blob: function () { return fetch(fileUrl, { cache: 'no-store' }).then(check).then(function (r) { return r.blob(); }); },
		save: function (data) {
			return fetch(fileUrl, { method: 'PUT', body: data }).then(check).then(function (r) { return r.json(); }).then(function (j) {
				toAdmin({ sos: 'file-saved', app: appId, name: file.name });
				return j;
			});
		}
		};
		return file;
	}
	var ticket = q.get('file');
	var file = ticket && /^[0-9a-f]{32}$/.test(ticket) ? makeFile(ticket, q.get('name')) : null;

	/* the user's folders (permission "files"); the grant survives a reload */
	var grant = q.get('fs');
	try {
		if (grant && /^[0-9a-f]{32}$/.test(grant)) sessionStorage.setItem('sos-fs-' + appId, grant);
		else grant = sessionStorage.getItem('sos-fs-' + appId);
	} catch (e) { }
	function fsCall(op, args) {
		args = args || {}; args.op = op;
		return fetch('/_shareos/cgi/fs?g=' + grant, { method: 'POST', body: JSON.stringify(args), cache: 'no-store' })
			.then(function (r) { return r.json().catch(function () { return { error: 'HTTP ' + r.status }; }); })
			.then(function (j) { if (j.error) throw new Error(j.error); return j; });
	}
	var fs = grant && /^[0-9a-f]{32}$/.test(grant) ? {
		roots: function () { return fsCall('roots').then(function (j) { return j.roots; }); },
		list: function (root, path, hidden) { return fsCall('list', { root: root, path: path || '', hidden: !!hidden }); },
		mkdir: function (root, path, name) { return fsCall('mkdir', { root: root, path: path || '', name: name }); },
		rename: function (root, path, name, to) { return fsCall('rename', { root: root, path: path || '', name: name, to: to }); },
		copy: function (root, path, names, destRoot, dest) { return fsCall('move', { root: root, path: path || '', names: names, dest_root: destRoot || root, dest: dest || '', copy: true }); },
		move: function (root, path, names, destRoot, dest) { return fsCall('move', { root: root, path: path || '', names: names, dest_root: destRoot || root, dest: dest || '' }); },
		remove: function (root, path, names) { return fsCall('delete', { root: root, path: path || '', names: names }); },
		open: function (root, path, name, o) {
			o = o || {};
			return fsCall('open', { root: root, path: path || '', name: name, write: !!o.write, create: !!o.create }).then(function (j) {
				var f = makeFile(j.ticket, j.name, j.mode); f.size = j.size; f.exists = j.exists; return f;
			});
		}
	} : null;

	/* classic menu bar */
	function keyOf(ev) {
		var k = ev.key.length === 1 ? ev.key.toUpperCase() : ev.key;
		return (ev.ctrlKey || ev.metaKey ? 'Ctrl+' : '') + (ev.altKey ? 'Alt+' : '') + (ev.shiftKey ? 'Shift+' : '') + k;
	}
	function menu(el, spec) {
		var shortcuts = {};
		el.classList.add('sos-menubar');
		el.setAttribute('role', 'menubar');
		el.innerHTML = '';
		var openOne = null;
		function close() { if (openOne) { openOne.classList.remove('open'); openOne = null; } }
		spec.forEach(function (m) {
			var li = document.createElement('div');
			li.className = 'sos-menuitem';
			var b = document.createElement('button');
			b.type = 'button'; b.textContent = m.label; b.setAttribute('aria-haspopup', 'true');
			var ul = document.createElement('div');
			ul.className = 'sos-menu'; ul.setAttribute('role', 'menu');
			(m.items || []).forEach(function (it) {
				if (it === '-') { ul.appendChild(document.createElement('hr')); return; }
				var ib = document.createElement('button');
				ib.type = 'button'; ib.setAttribute('role', 'menuitem');
				var span = document.createElement('span'); span.textContent = it.label;
				if (it.checked) span.className = 'sos-check';
				ib.appendChild(span);
				if (it.kbd) { var k = document.createElement('kbd'); k.textContent = it.kbd; ib.appendChild(k); shortcuts[it.kbd] = it; }
				ib.disabled = !!it.disabled;
				ib.addEventListener('click', function () { close(); if (it.action) it.action(); });
				ul.appendChild(ib);
			});
			b.addEventListener('click', function () {
				var was = openOne === li; close();
				if (!was) { li.classList.add('open'); openOne = li; var first = ul.querySelector('button:not(:disabled)'); if (first) first.focus(); }
			});
			b.addEventListener('mouseenter', function () { if (openOne && openOne !== li) { close(); li.classList.add('open'); openOne = li; } });
			li.appendChild(b); li.appendChild(ul); el.appendChild(li);
		});
		document.addEventListener('click', function (ev) { if (!el.contains(ev.target)) close(); });
		document.addEventListener('keydown', function (ev) {
			if (ev.key === 'Escape') { close(); return; }
			var it = shortcuts[keyOf(ev)];
			if (it && !it.disabled && it.action) { ev.preventDefault(); close(); it.action(); }
		});
		return { close: close };
	}

	var api = {
		app: appId,
		embedded: embedded,
		theme: null,
		onTheme: function (fn) { themeFns.push(fn); if (api.theme) fn(api.theme); },
		file: file,
		fs: fs,
		menu: menu,
		on: function (type, fn) { (handlers[type] = handlers[type] || []).push(fn); },
		emit: function (type, data) { if (chan) chan.postMessage({ type: type, data: data, from: appId }); },
		resize: function () { if (embedded) toAdmin({ sos: 'resize', app: appId, height: document.documentElement.scrollHeight }); }
	};
	window.ShareOS = api;

	if (q.get('theme')) { store('sos-theme', q.get('theme')); store('sos-accent', q.get('accent') || ''); }
	applyTheme(q.get('theme') || store('sos-theme'), q.get('accent') || store('sos-accent'));
	if (embedded) {
		root.setAttribute('data-embedded', '');
		if ('ResizeObserver' in window)
			addEventListener('DOMContentLoaded', function () { new ResizeObserver(api.resize).observe(document.documentElement); });
	}
})();
