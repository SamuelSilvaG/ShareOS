/*
 * ShareOS web interface
 *
 * Plain JavaScript, no framework (fits 256 MB RAM and a 5 MB system image).
 * Talks only to the rpcd JSON-RPC endpoint /ubus (sessions + ACLs from rpcd);
 * the look comes from shareos.css (derived from the Skynet intranet).
 */
'use strict';

/* ---------- helpers --------------------------------------------------------- */

const $ = (sel, el = document) => el.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
const raw = (s) => new Raw(s);
const part = (v) => (v instanceof Raw ? v.s : Array.isArray(v) ? v.map(part).join('') : v === false || v == null ? '' : esc(v));
function html(strings, ...vals) {
	let out = '';
	strings.forEach((s, i) => { out += s + (i < vals.length ? part(vals[i]) : ''); });
	return raw(out);
}

const fmtBytes = (b, d = 1) => {
	if (b == null) return '–';
	const u = ['B', 'KB', 'MB', 'GB', 'TB'];
	let i = 0;
	while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
	return b.toLocaleString('de-DE', { maximumFractionDigits: i ? d : 0 }) + ' ' + u[i];
};
const fmtRate = (b) => (b == null ? '–' : fmtBytes(b, 1) + '/s');
const fmtUptime = (s) => {
	s = Math.floor(s || 0);
	const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
	return d ? `${d} T ${h} h` : h ? `${h} h ${m} min` : `${m} min`;
};
const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('de-DE') : '–');
const pct = (a, b) => (b ? Math.max(0, Math.min(100, (a / b) * 100)) : 0);

const store = {
	get(k) { try { return localStorage.getItem('shareos.' + k) ?? sessionStorage.getItem('shareos.' + k); } catch (e) { return null; } },
	set(k, v, persist = true) {
		try {
			(persist ? localStorage : sessionStorage).setItem('shareos.' + k, v);
			(persist ? sessionStorage : localStorage).removeItem('shareos.' + k);
		} catch (e) { }
	},
	del(k) { try { localStorage.removeItem('shareos.' + k); sessionStorage.removeItem('shareos.' + k); } catch (e) { } }
};

/* ---------- icons ----------------------------------------------------------- */

const svg = (d, cls = '') => raw(`<svg ${cls ? `class="${cls}" ` : ''}viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`);
const I = {
	moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
	power: '<path d="M12 3v9"/><path d="M6.3 6.3a8 8 0 1 0 11.4 0"/>',
	disk: '<rect x="3" y="13" width="18" height="8" rx="2"/><path d="M5 13 7.5 4h9L19 13"/><path d="M7 17h.01M11 17h6"/>',
	usb: '<path d="M7 3h10v6H7z"/><path d="M5 9h14v10a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2z"/><path d="M10 6h.01M14 6h.01"/>',
	chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
	term: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3M13 15h4"/>',
	globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
	bus: '<rect x="3" y="3" width="18" height="8" rx="2"/><rect x="3" y="13" width="18" height="8" rx="2"/><path d="M7 7h.01M7 17h.01"/>',
	fan: '<circle cx="12" cy="12" r="2"/><path d="M12 10c0-4 1-7 4-7s2 4-2 7M14 12c4 0 7 1 7 4s-4 2-7-2M12 14c0 4-1 7-4 7s-2-4 2-7M10 12c-4 0-7-1-7-4s4-2 7 2"/>',
	dl: '<path d="M12 3v12M7 10l5 5 5-5M4 20h16"/>',
	info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/>',
	warn: '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>',
	ok: '<path d="m5 12 5 5 9-10"/>',
	reboot: '<path d="M20 11a8 8 0 0 0-14.9-3M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4"/>',
	folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
	cloud: '<path d="M7 18a4.5 4.5 0 0 1-.5-9 6 6 0 0 1 11.5 1.5A3.75 3.75 0 0 1 17.5 18z"/>',
	doc: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/>',
	box: '<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5M12 13v8"/>'
};
const SVC_ICON = { dropbear: I.term, uhttpd: I.globe, ntpd: I.clock, crond: I.clock, rpcd: I.bus, ubus: I.bus, syslogd: I.list, board: I.fan };

/* ---------- RPC ------------------------------------------------------------- */

const ZERO_SID = '00000000000000000000000000000000';
let rpcId = 0;

class RpcError extends Error { constructor(msg, code) { super(msg); this.code = code; } }

async function rpc(obj, method, args = {}, sid = S.sid) {
	let res;
	try {
		res = await fetch('/ubus', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method: 'call', params: [sid || ZERO_SID, obj, method, args] })
		});
	} catch (e) {
		throw new RpcError('Box nicht erreichbar', 'offline');
	}
	if (!res.ok) throw new RpcError('HTTP ' + res.status, res.status);
	const j = await res.json();
	if (j.error) {
		if (j.error.code === -32002) { sessionExpired(); throw new RpcError('Sitzung abgelaufen', 'auth'); }
		throw new RpcError(j.error.message, j.error.code);
	}
	const [code, data] = j.result;
	if (code === 6) { sessionExpired(); throw new RpcError('Keine Berechtigung', 'auth'); }
	if (code !== 0) throw new RpcError('ubus-Fehler ' + code, code);
	if (data && data.error) throw new RpcError(data.error, 'app');
	return data ?? {};
}

/* ---------- state ----------------------------------------------------------- */

const S = {
	sid: store.get('sid'),
	user: store.get('user') || 'root',
	route: { tab: 'uebersicht', sub: '' },
	info: null, prev: null,
	cpu: null, rxRate: null, txRate: null,
	rxHist: [], txHist: [],
	services: null,
	upd: null, check: null, checking: false,
	timer: null, updTimer: null,
	theme: store.get('theme') || 'dark',
	accent: store.get('accent') || 'green',
	scan: store.get('scan') !== '0'
};

const TABS = [
	['uebersicht', 'ÜBERSICHT'], ['speicher', 'SPEICHER'], ['freigaben', 'FREIGABEN'], ['dienste', 'DIENSTE'],
	['apps', 'APPS'], ['cloud', 'CLOUD', true], ['paperless', 'PAPERLESS', true], ['system', 'SYSTEM']
];
const SYS_SUBS = [['firmware', 'FIRMWARE'], ['allgemein', 'ALLGEMEIN'], ['energie', 'ENERGIE & RESET'], ['protokolle', 'PROTOKOLLE'], ['darstellung', 'DARSTELLUNG'], ['ueber', 'ÜBER']];

function applyTheme() {
	const app = $('#app');
	app.className = 'sos acc-' + S.accent + (S.theme === 'light' ? ' light' : '');
	$('.scan', app).hidden = !S.scan;
	document.body.style.background = getComputedStyle(app).getPropertyValue('--bg');
}

/* ---------- UI primitives --------------------------------------------------- */

function toast(msg, bad = false) {
	const el = document.createElement('div');
	if (bad) el.className = 'bad';
	el.textContent = msg;
	$('#toast').append(el);
	setTimeout(() => el.remove(), bad ? 7000 : 4000);
}

function confirmDlg(title, text, okLabel, danger = false) {
	return new Promise((resolve) => {
		const d = document.createElement('dialog');
		d.className = 'dlg';
		d.innerHTML = html`<h3>${title}</h3><p>${text}</p><div class="acts">
			<button class="btn ghost" type="button" value="no">Abbrechen</button>
			<button class="btn ${danger ? 'danger' : 'primary'}" type="button" value="yes">${okLabel}</button></div>`.s;
		$('#app').append(d);
		d.addEventListener('click', (e) => {
			const v = e.target.closest('button')?.value;
			if (v) { d.close(); resolve(v === 'yes'); }
		});
		d.addEventListener('cancel', () => resolve(false));
		d.addEventListener('close', () => d.remove());
		d.showModal();
		$('button[value=no]', d).focus();
	});
}

function promptDlg(title, text, value, okLabel) {
	return new Promise((resolve) => {
		const d = document.createElement('dialog');
		d.className = 'dlg';
		d.innerHTML = html`<form method="dialog"><h3>${title}</h3><p>${text}</p>
			<label class="f" style="margin-bottom:16px"><input name="v" value="${value}" maxlength="16" required></label>
			<div class="acts"><button class="btn ghost" type="button" value="no">Abbrechen</button>
			<button class="btn primary" type="submit" value="yes">${okLabel}</button></div></form>`.s;
		$('#app').append(d);
		let result = null;
		$('button[value=no]', d).addEventListener('click', () => d.close());
		$('form', d).addEventListener('submit', () => { result = $('input', d).value.trim(); });
		d.addEventListener('close', () => { d.remove(); resolve(result); });
		d.showModal();
		$('input', d).select();
	});
}

let coverEl = null;
function cover(title, text) {
	uncover();
	coverEl = document.createElement('div');
	coverEl.className = 'cover';
	coverEl.innerHTML = html`<div class="panel"><div class="spin"></div><b class="name">${title}</b><span class="mut" id="cover-text">${text}</span></div>`.s;
	$('#app').append(coverEl);
}
function uncover() { coverEl?.remove(); coverEl = null; }

// after reboot / restart: wait until the box answers again, then reload
async function waitForBox(title, text, minDown = true) {
	cover(title, text);
	let wasDown = !minDown;
	const t0 = Date.now();
	for (;;) {
		await new Promise((r) => setTimeout(r, 3000));
		try {
			const r = await fetch('/ubus', { method: 'POST', body: '{"jsonrpc":"2.0","id":0,"method":"list","params":["session"]}' });
			if (r.ok && wasDown) { location.reload(); return; }
		} catch (e) { wasDown = true; }
		if (!wasDown && Date.now() - t0 > 90000) wasDown = true;  // reboot faster than our polling
		const s = Math.round((Date.now() - t0) / 1000);
		const el = $('#cover-text');
		if (el) el.textContent = `${text} (${s} s)`;
	}
}

/* ---------- session --------------------------------------------------------- */

function sessionExpired() {
	if (!S.sid) return;
	S.sid = null;
	store.del('sid');
	stopPolling();
	renderLogin('Sitzung abgelaufen – bitte neu anmelden.');
}

async function login(user, pass, keep) {
	const r = await rpc('session', 'login', { username: user, password: pass, timeout: keep ? 7 * 86400 : 3600 }, ZERO_SID);
	S.sid = r.ubus_rpc_session;
	S.user = user;
	store.set('sid', S.sid, keep);
	store.set('user', user, true);
}

async function logout() {
	try { await rpc('session', 'destroy', { ubus_rpc_session: S.sid }); } catch (e) { }
	S.sid = null;
	store.del('sid');
	stopPolling();
	renderLogin();
}

/* ---------- polling --------------------------------------------------------- */

async function tick() {
	try {
		const info = await rpc('shareos.system', 'info');
		const prev = S.info;
		if (prev?.cpu && info.cpu) {
			const dt = info.cpu.total - prev.cpu.total, di = info.cpu.idle - prev.cpu.idle;
			S.cpu = dt > 0 ? pct(dt - di, dt) : S.cpu;
		}
		const n = info.network?.eth0, p = prev?.network?.eth0;
		const dts = prev ? info.uptime - prev.uptime : 0;
		if (n && p && dts > 0) {
			S.rxRate = Math.max(0, (n.rx_bytes - p.rx_bytes) / dts);
			S.txRate = Math.max(0, (n.tx_bytes - p.tx_bytes) / dts);
			S.rxHist.push(S.rxRate); S.txHist.push(S.txRate);
			if (S.rxHist.length > 120) { S.rxHist.shift(); S.txHist.shift(); }
		}
		S.info = info;
		renderHeader();
		if (S.route.tab === 'uebersicht') renderMain();
	} catch (e) {
		if (e.code === 'offline') renderHeader(true);
	}
}

function startPolling() {
	stopPolling();
	tick();
	S.timer = setInterval(tick, 5000);
	refreshUpdateStatus();
}
function stopPolling() {
	clearInterval(S.timer); S.timer = null;
	clearTimeout(S.updTimer); S.updTimer = null;
}

/* ---------- layout ---------------------------------------------------------- */

function renderLogin(msg = '') {
	$('#root').innerHTML = html`
	<div class="login">
		<form class="panel" id="login-form" autocomplete="on">
			<h1 class="brand">SHAREOS</h1>
			<p class="prompt">Verwaltung – bitte anmelden.</p>
			<p class="prompt"><b>root@shareos</b>:~$ login<span class="cursor"></span></p>
			<label class="f"><span>BENUTZER</span><input name="user" type="text" value="${S.user}" autocomplete="username" required></label>
			<label class="f"><span>PASSWORT</span><input name="pass" type="password" autocomplete="current-password" required autofocus></label>
			<label class="chk"><input name="keep" type="checkbox">Angemeldet bleiben (7 Tage)</label>
			<p class="err" id="login-err">${msg}</p>
			<button class="btn primary" type="submit" style="min-height:44px">Anmelden</button>
		</form>
	</div>`.s;
	$('#login-form').addEventListener('submit', async (e) => {
		e.preventDefault();
		const f = e.target;
		const btn = $('button[type=submit]', f);
		btn.disabled = true;
		$('#login-err').textContent = '';
		try {
			await login(f.user.value.trim(), f.pass.value, f.keep.checked);
			renderShell();
		} catch (err) {
			$('#login-err').textContent = err.code === 'offline' ? 'Box nicht erreichbar.' : 'Benutzer oder Passwort falsch.';
			btn.disabled = false;
			f.pass.select();
		}
	});
	setTimeout(() => $('#login-form input[name=pass]')?.focus(), 0);
}

function renderShell() {
	$('#root').innerHTML = html`
		<header class="hd" id="hd"></header>
		<nav class="tabs" id="tabs" aria-label="Hauptmenü"></nav>
		<main id="main"></main>
		<footer class="ft" id="ft"></footer>`.s;
	parseRoute();
	renderHeader();
	renderTabs();
	renderMain();
	startPolling();
}

function renderHeader(offline = false) {
	const hd = $('#hd');
	if (!hd) return;
	const i = S.info || {}, r = i.release || {}, ip = i.network?.eth0?.ipv4?.address;
	const now = new Date();
	const upd = S.check?.update_available ? S.check.latest : null;
	hd.innerHTML = html`
		<div>
			<h1 class="brand">SHAREOS</h1>
			<div class="sub"><b>${i.hostname || '…'}</b>${[(i.model || '').replace(/ NAS$/, ''), 'ShareOS ' + (r.version || '…'), ip].filter(Boolean).map((x) => ' · ' + x).join('')}</div>
		</div>
		<div class="side">
			<div class="row">
				${upd ? html`<a class="chip warn" href="#/system/firmware"><i></i>UPDATE ${upd.replace(/^v/, '')} <small>verfügbar</small></a>` : ''}
				${offline ? html`<span class="chip warn"><i></i>OFFLINE</span>`
					: html`<span class="chip"><i></i>ONLINE <small>seit ${fmtUptime(i.uptime)}</small></span>`}
				<button class="ib" type="button" data-act="theme" aria-label="Hell/Dunkel umschalten">${svg(I.moon)}</button>
				<button class="ib" type="button" data-act="logout" aria-label="Abmelden">${svg(I.power)}</button>
			</div>
			<div class="clock">${now.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}</div>
			<div class="meta">${now.toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</div>
		</div>`.s;
	const ft = $('#ft');
	if (ft) ft.innerHTML = html`<span><b>ShareOS</b> ${r.version || ''} · Linux ${i.kernel || ''} · GPLv2</span>
		<span>Last ${(i.load || []).map((x) => x.toFixed(2)).join(' ')} · <a href="https://github.com/UniqueDroid/ShareOS" target="_blank" rel="noopener">github.com/UniqueDroid/ShareOS</a></span>`.s;
}

function renderTabs() {
	$('#tabs').innerHTML = TABS.map(([id, label, isNew]) =>
		html`<a class="tab${S.route.tab === id ? ' on' : ''}" href="#/${id}"${S.route.tab === id ? raw(' aria-current="page"') : ''}>${label}${isNew ? html` <span class="nb">NEU</span>` : ''}</a>`.s).join('');
}

function parseRoute() {
	const [tab, sub] = location.hash.replace(/^#\/?/, '').split('/');
	S.route = { tab: TABS.some((t) => t[0] === tab) ? tab : 'uebersicht', sub: sub || '' };
	if (S.route.tab === 'system' && !SYS_SUBS.some((x) => x[0] === S.route.sub)) S.route.sub = 'firmware';
}

function renderMain() {
	const main = $('#main');
	if (!main) return;
	const v = VIEWS[S.route.tab] || VIEWS.uebersicht;
	main.innerHTML = v().s;
	VIEWS_AFTER[S.route.tab]?.();
}

/* ---------- views ----------------------------------------------------------- */

function mrow(label, p, value, cls = '') {
	return html`<div class="mrow"><span class="kk">${label}</span><div class="bar"><i class="${cls}" style="width:${p.toFixed(0)}%"></i></div><span class="vv">${value}</span></div>`;
}

function spark() {
	const n = 120, rx = S.rxHist, tx = S.txHist;
	if (rx.length < 2) return html`<div class="spark" style="display:grid;place-items:center;font-size:12px;color:var(--muted)">sammle Messwerte …</div>`;
	const max = Math.max(1024, ...rx, ...tx);
	const pts = (arr) => arr.map((v, k) => `${((k + n - arr.length) / (n - 1) * 300).toFixed(1)},${(68 - (v / max) * 62).toFixed(1)}`).join(' ');
	const first = ((n - rx.length) / (n - 1) * 300).toFixed(1);
	return raw(`<svg class="spark" viewBox="0 0 300 70" preserveAspectRatio="none" role="img" aria-label="Netzwerkverkehr der letzten 10 Minuten">
		<polyline style="fill:rgba(var(--rgb),.12);stroke:none" points="${first},70 ${pts(rx)} 300,70"></polyline>
		<polyline style="fill:none;stroke:var(--accent);stroke-width:1.5" points="${pts(rx)}"></polyline>
		<polyline style="fill:none;stroke:var(--amber);stroke-width:1.5" points="${pts(tx)}"></polyline></svg>`);
}

function diskCards(i) {
	const disks = i.disks || [];
	if (!disks.length)
		return html`<div class="panel"><div class="empty">${svg(I.info)}<span>Keine Festplatte und kein USB-Speicher erkannt. ShareOS läuft vollständig aus dem internen Flash – Laufwerke erscheinen hier, sobald sie eingesteckt sind.</span></div></div>`;
	return html`<div class="grid">${disks.map((d) => html`
		<div class="card">
			<div class="icon">${svg(d.removable ? I.usb : I.disk)}<span class="dot up"></span></div>
			<div class="info"><div class="name">${d.removable ? 'USB' : 'Festplatte'} · ${d.name}</div>
				<div class="desc">${d.model || 'unbekanntes Modell'} · ${fmtBytes(d.size)}</div>
				<div class="ip">/dev/${d.name}</div></div>
		</div>`)}</div>`;
}

const fsLabel = { '/overlay': 'Einstellungen & Pakete', '/rom': 'System (nur lesbar)', '/tmp': 'Arbeitsspeicher (tmp)' };

const VIEWS = {
	uebersicht() {
		const i = S.info;
		if (!i) return html`<div class="panel"><div class="empty"><div class="spin" style="margin:0"></div><span>Lade Systemdaten …</span></div></div>`;
		const m = i.memory || {}, used = (m.memtotal || 0) - (m.memavailable || 0);
		const t = i.temperature != null ? i.temperature / 1000 : null;
		const ov = (i.filesystems || []).find((f) => f.mount === '/overlay');
		const e = i.network?.eth0 || {};
		const bootTxt = { flash: 'Flash (UBI)', netroot: 'Netzwerk (RAM)', ram: 'RAM' }[i.boot] || i.boot;
		const svcUp = S.services ? S.services.filter((x) => x.running).length : null;
		return html`
		<section class="sec">
			<h2 class="gh">SYSTEM <span>live · alle 5 s</span></h2>
			<div class="g2">
				<div class="panel">
					<div class="ph"><span class="pt">AUSLASTUNG</span><span class="tag ml ${i.fan_pwm != null ? 'ok' : ''}">${i.fan_pwm != null ? 'Gerätesteuerung aktiv' : 'keine MCU-Daten'}</span></div>
					<div class="mbars">
						${mrow('CPU', S.cpu ?? 0, S.cpu == null ? '…' : S.cpu.toFixed(0) + ' %')}
						${mrow('RAM', pct(used, m.memtotal), fmtBytes(used, 0))}
						${mrow('TEMP', t == null ? 0 : pct(t, 65), t == null ? '–' : t.toFixed(0) + ' °C', t >= 50 ? 'warn' : '')}
						${mrow('LÜFTER', i.fan_pwm == null ? 0 : pct(i.fan_pwm, 255), i.fan_pwm == null ? '–' : i.fan_pwm === 0 ? 'aus' : i.fan_pwm < 200 ? 'halb' : 'voll')}
						${ov ? mrow('FLASH', pct(ov.used, ov.size), fmtBytes(ov.used, 0)) : ''}
					</div>
					<p class="note">${i.model ? i.model + ' · ' : ''}Linux ${i.kernel} · Last ${(i.load || []).map((x) => x.toFixed(2)).join(' ')}</p>
				</div>
				<div class="panel">
					<div class="ph"><span class="pt">NETZWERK · eth0</span><span class="tag ml">${e.speed ? e.speed + ' Mbit/s' : 'kein Link'}</span></div>
					${spark()}
					<div class="rates"><span class="rx">↓ <b>${fmtRate(S.rxRate)}</b> rx</span><span class="mut">letzte 10 min</span><span class="tx">↑ <b>${fmtRate(S.txRate)}</b> tx</span></div>
					<dl class="kv" style="margin-top:14px">
						<dt>IPv4</dt><dd>${e.ipv4 ? `${e.ipv4.address} / ${e.ipv4.prefix}` : '–'}</dd>
						<dt>Gateway · DNS</dt><dd>${e.gateway || '–'} · ${(e.dns || []).join(', ') || '–'}</dd>
						<dt>MAC</dt><dd>${e.mac || '–'}</dd>
					</dl>
				</div>
			</div>
		</section>
		<section class="sec">
			<div class="tiles">
				<div class="tile"><div class="k">Firmware</div><div class="v">${i.release?.version || '–'}</div><div class="s">${S.check?.update_available ? 'Update ' + S.check.latest + ' verfügbar' : 'Kanal ' + (S.check?.channel || 'stable')}</div></div>
				<div class="tile"><div class="k">Start aus</div><div class="v">${bootTxt}</div><div class="s">${i.boot === 'flash' ? 'Einstellungen bleiben erhalten' : 'Änderungen gehen beim Neustart verloren'}</div></div>
				<div class="tile"><div class="k">Laufzeit</div><div class="v">${fmtUptime(i.uptime)}</div><div class="s">seit dem letzten Start</div></div>
				<div class="tile"><div class="k">Dienste</div><div class="v">${svcUp == null ? '…' : `${svcUp} / ${S.services.length}`}</div><div class="s">laufen</div></div>
				<div class="tile"><div class="k">Flash frei</div><div class="v">${ov ? fmtBytes(ov.avail, 0) : '–'}</div><div class="s">für Einstellungen & Pakete</div></div>
				<div class="tile"><div class="k">Laufwerke</div><div class="v">${(i.disks || []).length}</div><div class="s">${(i.disks || []).length ? 'erkannt' : 'keine eingesteckt'}</div></div>
			</div>
		</section>
		<section class="sec">
			<h2 class="gh">LAUFWERKE <span>${(i.disks || []).length} erkannt</span></h2>
			${diskCards(i)}
		</section>
		<section class="sec">
			<h2 class="gh">DIENSTE <span><a href="#/dienste">alle verwalten</a></span></h2>
			${serviceCards(false)}
		</section>`;
	},

	speicher: () => storageView(),

	freigaben: () => planned('Freigaben, Benutzer & Gruppen', 'Phase 4', ['Freigaben je Ordner mit Schaltern für SMB, NFS, FTP und DLNA', 'Benutzer & Gruppen mit Rechten pro Freigabe', 'Netzlaufwerke einbinden (CIFS/NFS)', 'Backup-Jobs (rsync)'], I.folder),
	apps: () => planned('Apps & Pakete', 'Phase 4', ['Paketquelle (opkg-Feed) über GitHub', 'Katalog mit Kategorien, Installieren/Entfernen mit Warteschlange', 'Pakete landen in den Einstellungen & Paketen (Flash) oder auf der Platte'], I.box),
	cloud: () => planned('Cloud-Speicher', 'Phase 5', ['Konten über rclone: Nextcloud/WebDAV, Google Drive, OneDrive, Dropbox, S3, SFTP', 'Sync-Jobs: kopieren, spiegeln, bidirektional', 'Verschlüsselung (crypt), Bandbreite und Zeitplan'], I.cloud),
	paperless: () => planned('Paperless-ngx', 'Phase 5', ['Eingangsordner auf dem NAS → Upload über die Paperless-REST-API (Token)', 'Status der Übertragungen über /api/tasks/', 'Tags und Korrespondent je Ordner, Export-Backup aufs NAS'], I.doc),

	dienste() {
		return html`<section class="sec"><h2 class="gh">DIENSTE <span>Start, Stopp, Neustart</span></h2>${serviceCards(true)}</section>`;
	},

	system() {
		const sub = S.route.sub;
		return html`
		<nav class="subtabs" aria-label="System">${SYS_SUBS.map(([id, label]) => html`<a class="st${sub === id ? ' on' : ''}" href="#/system/${id}">${label}</a>`)}</nav>
		${(SYS[sub] || SYS.firmware)()}`;
	}
};

function planned(title, phase, items, icon = I.info) {
	return html`<section class="sec"><h2 class="gh">${title.toUpperCase()} <span>geplant · ${phase}</span></h2>
		<div class="panel"><div class="empty">${svg(icon)}<div><span>Dieser Bereich ist noch nicht gebaut. Geplant:</span>
		<ul class="plan">${items.map((x) => html`<li>${x}</li>`)}</ul></div></div></div></section>`;
}

function serviceCards(withActions) {
	if (!S.services) return html`<div class="panel"><div class="empty"><div class="spin" style="margin:0"></div><span>Lade Dienste …</span></div></div>`;
	return html`<div class="grid">${S.services.map((s) => html`
		<div class="card${s.running ? '' : ' off'}">
			<div class="icon">${svg(SVC_ICON[s.name] || I.chip)}<span class="dot ${s.running ? 'up' : 'down'}"></span></div>
			<div class="info"><div class="name">${s.label}</div><div class="desc">${s.desc}</div>
				<div class="ip">${s.name} · ${s.running ? 'läuft' : 'gestoppt'}</div>
				${withActions ? html`<div class="acts" style="margin-top:12px">
					${s.running ? html`<button class="btn sm" type="button" data-act="svc" data-name="${s.name}" data-op="restart">${svg(I.reboot)}Neustart</button>
						${s.essential ? '' : html`<button class="btn sm danger" type="button" data-act="svc" data-name="${s.name}" data-op="stop">Stopp</button>`}`
						: html`<button class="btn sm" type="button" data-act="svc" data-name="${s.name}" data-op="start">Starten</button>`}
				</div>` : ''}
			</div>
		</div>`)}</div>`;
}

async function loadServices() {
	try {
		S.services = (await rpc('shareos.service', 'list')).services;
		if (S.route.tab === 'dienste' || S.route.tab === 'uebersicht') renderMain();
	} catch (e) { if (e.code !== 'auth') toast('Dienste: ' + e.message, true); }
}


/* ---------- storage (Speicher) ---------------------------------------------- */

const LAYOUT_TXT = { mirror: 'Spiegel (RAID 1)', single: 'Einzelnes Laufwerk' };
const SPINDOWN = [[0, 'nie'], [10, '10 Minuten'], [20, '20 Minuten'], [30, '30 Minuten'], [60, '1 Stunde'], [120, '2 Stunden']];

function arrayOf(st, dev) {
	const name = (dev || '').replace('/dev/', '');
	return st?.arrays?.[name] || null;
}

function diskUse(st, d) {
	// what is on a disk: ShareOS volume / RAID member / foreign file system / empty
	const parts = d.children || [];
	if (!parts.length && !d.fstype) return { empty: true, txt: 'leer' };
	const txt = parts.map((p) => {
		if (p.fstype === 'linux_raid_member') {
			const md = (p.children || [])[0];
			return `RAID-Mitglied${md ? ' von ' + md.name : ''}${p.label ? ' (' + p.label.replace(/^.*:/, '') + ')' : ''}`;
		}
		return [p.name, p.fstype || 'ohne Dateisystem', p.label, p.mountpoint ? '→ ' + p.mountpoint : ''].filter(Boolean).join(' · ');
	});
	return { empty: false, txt: txt.join(' | ') || d.fstype };
}

function smartLine(sm) {
	if (!sm) return html`<span class="mut">SMART noch nicht gelesen</span>`;
	if (sm.standby) return html`<span class="mut">schläft (SMART beim nächsten Aufwachen)</span>`;
	if (sm.error) return html`<span class="mut">${sm.error}</span>`;
	const bad = (sm.reallocated || 0) + (sm.pending || 0) + (sm.uncorrectable || 0);
	return html`<span class="tag ${sm.passed === false || bad ? 'err' : 'ok'}">SMART ${sm.passed === false ? 'FEHLER' : bad ? 'WARNUNG' : 'OK'}</span>
		${sm.temperature != null ? html` · ${sm.temperature} °C` : ''}
		${sm.power_on_hours != null ? html` · ${Math.round(sm.power_on_hours / 24)} Tage Laufzeit` : ''}
		${bad ? html` · <span style="color:var(--red)">${sm.reallocated || 0} umgelagert, ${sm.pending || 0} schwebend</span>` : ''}`;
}

function storageView() {
	const st = S.storage, i = S.info || {};
	if (!st) return html`<div class="panel"><div class="empty"><div class="spin" style="margin:0"></div><span>Lade Laufwerke …</span></div></div>`;
	const job = st.job;
	const running = job?.state === 'running';
	return html`
	${running ? html`<div class="banner" style="border-color:var(--dim)"><div class="spin" style="margin:0;width:20px;height:20px"></div><span><b>Einrichtung läuft</b> – ${job.step || ''}. Box nicht ausschalten.</span></div>` : ''}
	${job?.state === 'error' ? html`<div class="banner">${svg(I.warn)}<span><b>Einrichtung fehlgeschlagen:</b> ${job.error}</span></div>` : ''}
	${S.wiz ? wizardView(st) : ''}
	<section class="sec">
		<h2 class="gh">VOLUMES <span>${st.volumes.length ? st.volumes.length + ' eingerichtet' : 'noch keine'}</span></h2>
		${st.volumes.length ? html`<div class="grid">${st.volumes.map((v) => volumeCard(st, v, running))}</div>`
			: html`<div class="panel"><div class="empty">${svg(I.info)}<div><span>Noch kein Speicher eingerichtet. Der Assistent richtet die Platten in wenigen Schritten ein – als Spiegel (beide Platten mit denselben Daten) oder als getrennte Laufwerke.</span>
				<div class="acts" style="margin-top:12px">${S.wiz ? '' : html`<button class="btn primary" type="button" data-act="wiz-start" ${running || !st.disks.length ? 'disabled' : ''}>Speicher einrichten</button>`}</div></div></div></div>`}
	</section>
	<section class="sec">
		<h2 class="gh">LAUFWERKE <span>${st.disks.length} erkannt</span></h2>
		${st.disks.length ? html`<div class="grid">${st.disks.map((d) => diskCard(st, d, running))}</div>` : diskCards(i)}
	</section>
	<section class="sec">
		<h2 class="gh">EINSTELLUNGEN</h2>
		<div class="g2">
			<div class="panel">
				<div class="ph"><span class="pt">RUHEZUSTAND</span></div>
				<div class="fields" style="grid-template-columns:1fr"><label class="f"><span>PLATTEN ABSCHALTEN NACH</span><select id="spindown">
					${SPINDOWN.map(([m, t]) => html`<option value="${m}"${st.spindown === m ? raw(' selected') : ''}>${t}</option>`)}
					${SPINDOWN.some(([m]) => m === st.spindown) ? '' : html`<option value="${st.spindown}" selected>${st.spindown} Minuten</option>`}
				</select></label></div>
				<p class="note">Spart Strom und schont die Platten. Beim ersten Zugriff laufen sie wieder an (einige Sekunden).</p>
			</div>
			<div class="panel">
				<div class="ph"><span class="pt">NEU EINRICHTEN</span></div>
				<p class="mut" style="margin:0 0 12px;font-size:13px">Der Assistent löscht die ausgewählten Platten und richtet sie neu ein. Einzelne Platten lassen sich auch direkt an der Platte unter „Laufwerke“ formatieren.</p>
				<button class="btn" type="button" data-act="wiz-start" ${running || !st.disks.length || S.wiz ? 'disabled' : ''}>Assistent starten</button>
			</div>
		</div>
	</section>
	<section class="sec">
		<h2 class="gh">INTERNER FLASH <span>128 MB NAND · UBI</span></h2>
		<div class="tw"><table class="t" style="min-width:560px">
			<thead><tr><th>BEREICH</th><th>EINGEHÄNGT</th><th>BELEGT</th><th style="width:30%">AUSLASTUNG</th></tr></thead>
			<tbody>${(i.filesystems || []).map((f) => html`<tr>
				<td><b>${fsLabel[f.mount] || f.mount}</b><div class="mut" style="font-size:12px">${f.source}</div></td>
				<td><code>${f.mount}</code></td>
				<td>${fmtBytes(f.used)} / ${fmtBytes(f.size)}</td>
				<td><div class="bar"><i class="${pct(f.used, f.size) > 90 ? 'crit' : pct(f.used, f.size) > 75 ? 'warn' : ''}" style="width:${pct(f.used, f.size).toFixed(0)}%"></i></div></td></tr>`)}
			</tbody></table></div>
	</section>`;
}

function volumeCard(st, v, running) {
	const md = arrayOf(st, v.device);
	const degraded = md && md.health && md.health.includes('_');
	const p = pct(v.used, v.size);
	return html`<div class="card${v.mounted ? '' : ' off'}">
		<div class="icon">${svg(I.disk)}<span class="dot ${!v.mounted ? 'down' : degraded ? 'warn' : 'up'}"></span></div>
		<div class="info">
			<div class="name">${v.name}</div>
			<div class="desc">${LAYOUT_TXT[v.layout] || v.layout || ''}${v.mounted ? html` · ${fmtBytes(v.avail)} frei von ${fmtBytes(v.size)}` : ' · nicht eingehängt'}</div>
			${v.mounted ? html`<div class="bar" style="margin-top:10px"><i class="${p > 90 ? 'crit' : p > 80 ? 'warn' : ''}" style="width:${p.toFixed(0)}%"></i></div>` : ''}
			${md ? html`<div class="desc" style="margin-top:8px">${md.name}: ${degraded ? html`<span style="color:var(--amber)">eine Platte fehlt (${md.health})</span>` : html`beide Platten aktiv (${md.health || '?'})`}</div>` : ''}
			${md?.sync ? html`<div class="desc" style="margin-top:6px">${md.sync.action === 'resync' ? 'Erst-Synchronisierung' : md.sync.action === 'recovery' ? 'Wiederherstellung' : 'Prüfung'}: ${md.sync.delayed ? 'wartet' : md.sync.percent.toFixed(1) + ' %' + (md.sync.finish ? ' · noch ' + fmtMin(md.sync.finish) : '')}</div>
				<div class="bar" style="margin-top:6px"><i class="warn" style="width:${md.sync.percent}%"></i></div>` : ''}
			<div class="ip">${v.mountpoint}${v.device ? ' · ' + v.device : ' · Dateisystem nicht gefunden'}</div>
			<div class="acts" style="margin-top:12px">
				${v.mounted ? html`<button class="btn sm" type="button" data-act="vol" data-name="${v.name}" data-op="umount" ${running ? 'disabled' : ''}>Aushängen</button>`
					: html`<button class="btn sm" type="button" data-act="vol" data-name="${v.name}" data-op="mount" ${running || !v.device ? 'disabled' : ''}>Einhängen</button>`}
				<button class="btn sm ghost" type="button" data-act="vol" data-name="${v.name}" data-op="forget" ${running ? 'disabled' : ''}>Entfernen</button>
			</div>
		</div></div>`;
}

function fmtMin(s) {
	const m = parseFloat(s);
	if (!(m >= 0)) return s;
	return m >= 90 ? `${(m / 60).toFixed(1).replace('.', ',')} h` : `${Math.round(m)} min`;
}

function diskCard(st, d, running) {
	const use = diskUse(st, d);
	const sm = d.smart;
	return html`<div class="card">
		<div class="icon">${svg(d.rm || d.tran === 'usb' ? I.usb : I.disk)}<span class="dot ${sm && !sm.standby && !sm.error && (sm.passed === false || sm.reallocated || sm.pending) ? 'warn' : 'up'}"></span></div>
		<div class="info">
			<div class="name">${d.tran === 'usb' ? 'USB' : 'Schacht'} · ${d.name}</div>
			<div class="desc">${d.model || 'unbekanntes Modell'} · ${fmtBytes(d.size)}${d.serial ? ' · ' + d.serial : ''}</div>
			<div class="desc" style="margin-top:8px">${smartLine(sm)}</div>
			<div class="ip">${use.txt}</div>
			<div class="acts" style="margin-top:12px">
				<button class="btn sm" type="button" data-act="smart" data-disk="${d.name}">SMART lesen</button>
				<button class="btn sm danger" type="button" data-act="format" data-disk="${d.name}" ${running || S.wiz ? 'disabled' : ''}>Löschen & formatieren</button>
			</div>
		</div></div>`;
}

/* --- setup wizard --- */

function wizardView(st) {
	const w = S.wiz;
	const disks = st.disks.filter((d) => !d.rm && d.tran !== 'usb');
	const chosen = st.disks.filter((d) => w.disks.includes(d.name));
	const steps = ['Platten', 'Aufbau', 'Name', 'Bestätigen'];
	const smallest = Math.min(...chosen.map((d) => d.size));
	let body;
	if (w.step === 0) {
		body = html`<p class="mut" style="margin:0 0 12px;font-size:13px">Welche Platten sollen eingerichtet werden? <b style="color:var(--amber)">Alles auf diesen Platten wird gelöscht.</b></p>
			<div style="display:grid;gap:8px">${(disks.length ? disks : st.disks).map((d) => { const u = diskUse(st, d); return html`
				<label class="chk" style="align-items:flex-start"><input type="checkbox" class="wiz-disk" value="${d.name}"${w.disks.includes(d.name) ? raw(' checked') : ''}>
				<span><b>${d.name}</b> · ${d.model || ''} · ${fmtBytes(d.size)}<br><span class="mut" style="font-size:12px">${u.empty ? 'leer' : 'enthält: ' + u.txt}</span></span></label>`; })}</div>`;
	} else if (w.step === 1) {
		const two = chosen.length === 2;
		const opts = two
			? [['mirror', 'Spiegel (RAID 1) – empfohlen', `Beide Platten enthalten dieselben Daten. Fällt eine aus, ist nichts verloren. Nutzbar: ${fmtBytes(smallest)}.`],
				['single', 'Zwei getrennte Laufwerke', `Doppelter Platz (${fmtBytes(chosen.reduce((a, d) => a + d.size, 0))}), aber keine Ausfallsicherheit – jede Platte ist ein eigenes Laufwerk.`]]
			: [['single', 'Einzelnes Laufwerk', `Die Platte wird ein Laufwerk mit ${fmtBytes(chosen[0]?.size)}. Für Ausfallsicherheit später eine zweite Platte als Spiegel einrichten.`]];
		if (!opts.some((o) => o[0] === w.layout)) w.layout = opts[0][0];
		body = html`<div style="display:grid;gap:10px">${opts.map(([id, t, d]) => html`
			<label class="panel" style="cursor:pointer;display:flex;gap:12px;align-items:flex-start;${w.layout === id ? 'border-color:var(--accent);box-shadow:var(--glow)' : ''}">
				<input type="radio" name="wiz-layout" value="${id}"${w.layout === id ? raw(' checked') : ''} style="margin-top:4px;accent-color:var(--accent)">
				<span><b class="name" style="font-size:14px">${t}</b><br><span class="mut" style="font-size:12px">${d}</span></span></label>`)}</div>`;
	} else if (w.step === 2) {
		const fields = w.layout === 'mirror' ? [['__mirror', 'NAME DES SPIEGELS']] : chosen.map((d) => [d.name, `NAME FÜR ${d.name.toUpperCase()} (${fmtBytes(d.size)})`]);
		body = html`<div class="fields">${fields.map(([k, l]) => html`<label class="f"><span>${l}</span><input class="wiz-name" data-k="${k}" value="${w.names[k] || ''}" maxlength="16" pattern="[a-z0-9][a-z0-9_-]{0,15}" required></label>`)}</div>
			<p class="note">Kleinbuchstaben, Ziffern, - und _ (max. 16 Zeichen). Das Laufwerk erscheint als <code>/mnt/&lt;name&gt;</code>; Freigaben legst du später darauf an.</p>`;
	} else {
		const vols = w.layout === 'mirror' ? [[w.names.__mirror, chosen.map((d) => d.name).join(' + '), fmtBytes(smallest)]]
			: chosen.map((d) => [w.names[d.name], d.name, fmtBytes(d.size)]);
		body = html`<div class="tw"><table class="t" style="min-width:420px"><thead><tr><th>LAUFWERK</th><th>PLATTEN</th><th>GRÖSSE</th><th>AUFBAU</th></tr></thead>
			<tbody>${vols.map(([n, ds, sz]) => html`<tr><td><b>${n}</b></td><td>${ds}</td><td>${sz}</td><td>${LAYOUT_TXT[w.layout]}</td></tr>`)}</tbody></table></div>
			<p class="note" style="color:var(--amber)">Beim Klick auf „Einrichten“ werden ${chosen.map((d) => d.name).join(' und ')} vollständig gelöscht.${w.layout === 'mirror' ? ' Die Erst-Synchronisierung läuft danach im Hintergrund (bei großen Platten mehrere Stunden); das Laufwerk ist sofort nutzbar.' : ''}</p>`;
	}
	return html`<section class="sec"><div class="panel" style="border-color:var(--dim);box-shadow:var(--glow)">
		<div class="ph"><span class="pt">SPEICHER EINRICHTEN · ASSISTENT</span><button class="btn sm ghost ml" type="button" data-act="wiz-cancel">Abbrechen</button></div>
		<div class="steps" style="margin-bottom:16px">${steps.map((n, k) => html`<div class="step ${k < w.step ? 'done' : k === w.step ? 'act' : ''}"><div class="n">${k + 1}${k < w.step ? ' ✓' : ''}</div>${n}</div>`)}</div>
		${body}
		<div class="acts" style="margin-top:16px;justify-content:space-between">
			<button class="btn ghost" type="button" data-act="wiz-back" ${w.step === 0 ? 'disabled' : ''}>Zurück</button>
			${w.step < 3 ? html`<button class="btn primary" type="button" data-act="wiz-next">Weiter</button>`
				: html`<button class="btn danger" type="button" data-act="wiz-run">Einrichten</button>`}
		</div></div></section>`;
}

function wizardCollect() {
	const w = S.wiz;
	if (!w) return;
	if (w.step === 0) w.disks = [...document.querySelectorAll('.wiz-disk:checked')].map((x) => x.value);
	if (w.step === 1) w.layout = $('input[name=wiz-layout]:checked')?.value || w.layout;
	if (w.step === 2) document.querySelectorAll('.wiz-name').forEach((x) => { w.names[x.dataset.k] = x.value.trim().toLowerCase(); });
}

const NAME_RE = /^[a-z0-9][a-z0-9_-]{0,15}$/;

function wizardCheck() {
	const w = S.wiz, st = S.storage;
	if (w.step === 0) {
		if (!w.disks.length) return 'Bitte mindestens eine Platte auswählen.';
		if (w.disks.length > 2) return 'Höchstens zwei Platten.';
	}
	if (w.step === 2) {
		const keys = w.layout === 'mirror' ? ['__mirror'] : w.disks;
		const names = keys.map((k) => w.names[k] || '');
		if (names.some((n) => !NAME_RE.test(n))) return 'Ungültiger Name: nur a–z, 0–9, - und _, max. 16 Zeichen.';
		if (new Set(names).size !== names.length) return 'Die Namen müssen verschieden sein.';
		const taken = st.volumes.filter((v) => !(v.device || '').match(new RegExp('/dev/(' + w.disks.join('|') + ')|/dev/md'))).map((v) => v.name);
		const clash = names.find((n) => taken.includes(n));
		if (clash) return `Der Name „${clash}“ ist schon vergeben.`;
	}
	return null;
}

async function loadStorage() {
	clearTimeout(S.stTimer);
	S.stActive = true;
	try {
		S.storage = await rpc('shareos.storage', 'status');
		if (S.route.tab === 'speicher' && !(S.wiz && S.wiz.step === 2) && !document.activeElement?.matches('select')) renderMain();
		const busy = S.storage.job?.state === 'running' || Object.values(S.storage.arrays || {}).some((a) => a.sync);
		if (S.route.tab === 'speicher') S.stTimer = setTimeout(loadStorage, busy ? 3000 : 15000);
	} catch (e) {
		if (e.code !== 'auth') { toast('Speicher: ' + e.message, true); S.stTimer = setTimeout(loadStorage, 15000); }
	}
}

/* ---------- system sub pages ------------------------------------------------ */

const STEP_NAMES = ['Herunterladen', 'Prüfen', 'Bereit', 'Schreiben', 'Neustart'];
function stepIndex(state) {
	return { downloading: 0, verifying: 1, ready: 2, flashing: 3, flashed: 4 }[state] ?? -1;
}

const SYS = {
	firmware() {
		const i = S.info || {}, u = S.upd || {}, c = S.check;
		const cur = i.release?.version || u.current || '–';
		const latest = c?.releases?.[0];
		const busy = ['downloading', 'verifying', 'flashing'].includes(u.state);
		const si = stepIndex(u.state);
		const prog = u.state === 'downloading' && u.progress?.total ? pct(u.progress.bytes, u.progress.total) : null;
		const bootOk = i.boot === 'flash';
		return html`
		${u.pending_reboot || u.state === 'flashed' ? html`<div class="banner">${svg(I.reboot)}<span style="flex:1;min-width:240px"><b>Neustart nötig</b> – das neue System wird beim nächsten Start installiert (ca. 1 Minute, Box nicht ausschalten).</span><button class="btn primary" type="button" data-act="reboot">Jetzt neu starten</button></div>` : ''}
		${u.last_upgrade ? html`<div class="banner" style="${u.last_upgrade.startsWith('ok') ? 'border-color:var(--dim)' : ''}">${svg(u.last_upgrade.startsWith('ok') ? I.ok : I.warn)}<span>Letztes Update: <b>${u.last_upgrade.startsWith('ok') ? 'erfolgreich installiert (' + u.last_upgrade.slice(3) + ')' : u.last_upgrade}</b></span></div>` : ''}
		${!bootOk && i.boot ? html`<div class="banner">${svg(I.warn)}<span>Die Box läuft gerade nicht aus dem Flash (<b>${i.boot}</b>). Updates über diese Seite gehen nur beim normalen Start aus dem Flash.</span></div>` : ''}
		<div class="split">
			<section class="main">
				<div class="panel">
					<div class="ph"><span class="pt">FIRMWARE-UPDATE</span><span class="tag ml">Quelle: GitHub Releases · ${c?.repo || 'UniqueDroid/ShareOS'}</span></div>
					<div class="ver">
						<div class="tile"><div class="k">Installiert</div><div class="v">${cur}</div><div class="s">Kernel, Startsystem und System</div></div>
						<span class="arrow" aria-hidden="true">→</span>
						<div class="tile"${c?.update_available ? raw(' style="border-color:color-mix(in srgb,var(--amber) 45%,transparent)"') : ''}>
							<div class="k">Neueste · ${c ? (c.channel === 'beta' ? 'Beta' : 'Stabil') : '–'}</div>
							<div class="v ${c?.update_available ? 'warn' : ''}">${latest ? latest.version : c ? 'keine' : '?'}</div>
							<div class="s">${c ? (c.update_available ? 'Update verfügbar' : latest ? 'aktuell' : 'noch kein Release für dieses Gerät') : 'noch nicht geprüft'}</div></div>
					</div>
					${si >= 0 ? html`
						<div class="pt" style="margin:18px 0 8px">ABLAUF · ${u.release?.version || ''}</div>
						<div class="steps">${STEP_NAMES.map((n, k) => html`<div class="step ${k < si || u.state === 'flashed' ? 'done' : k === si ? 'act' : ''}"><div class="n">${k + 1}${k < si || (u.state === 'flashed' && k <= si) ? ' ✓' : k === si ? ' · LÄUFT' : ''}</div>${n}</div>`)}</div>
						${prog != null ? html`<div class="bar big" style="margin-top:12px"><i style="width:${prog.toFixed(0)}%"></i></div><p class="note">${fmtBytes(u.progress.bytes)} von ${fmtBytes(u.progress.total)}</p>` : ''}
						${u.state === 'flashing' ? html`<p class="note">${u.step || ''} – <b>nicht ausschalten</b>.</p>` : ''}
						${u.state === 'ready' ? html`<div class="acts" style="margin-top:14px"><button class="btn primary" type="button" data-act="apply" data-tag="${u.release.tag}" ${bootOk ? '' : 'disabled'}>${svg(I.dl)}${u.release.version} installieren</button><button class="btn ghost" type="button" data-act="cancel">Verwerfen</button></div>
							<p class="note">Geprüft: SHA-256, Prüfsummen aller Teile, passend für dieses Gerät. Einstellungen und Pakete bleiben erhalten.</p>` : ''}`
					: ''}
					${u.state === 'error' ? html`<div class="banner" style="margin:16px 0 0">${svg(I.warn)}<span><b>Fehler:</b> ${u.error}</span><button class="btn sm ghost" type="button" data-act="cancel">OK</button></div>` : ''}
					<div class="fields" style="margin-top:18px">
						<label class="f"><span>UPDATE-KANAL</span><select id="channel">
							<option value="stable"${(c?.channel || 'stable') === 'stable' ? raw(' selected') : ''}>Stabil (Releases)</option>
							<option value="beta"${c?.channel === 'beta' ? raw(' selected') : ''}>Beta (auch Pre-Releases)</option></select></label>
					</div>
					<div class="acts" style="margin-top:14px"><button class="btn" type="button" data-act="check" ${S.checking || busy ? 'disabled' : ''}>${S.checking ? 'Prüfe …' : 'Jetzt prüfen'}</button></div>
				</div>
				${c?.releases?.length ? html`<div>
					<h2 class="gh">VERSIONEN <span>von GitHub</span></h2>
					<div class="tw"><table class="t" style="min-width:600px">
						<thead><tr><th>VERSION</th><th>DATUM</th><th>KANAL</th><th>GRÖSSE</th><th></th></tr></thead>
						<tbody>${c.releases.map((r) => html`<tr>
							<td><b>${r.version}</b></td><td>${fmtDate(r.date)}</td>
							<td><span class="tag">${r.prerelease ? 'BETA' : 'STABIL'}</span></td><td class="mut">${fmtBytes(r.size)}</td>
							<td>${r.version === cur ? html`<span class="tag ok">installiert</span>`
								: html`<button class="btn sm${r.tag === latest?.tag ? '' : ' ghost'}" type="button" data-act="download" data-tag="${r.tag}" ${busy || !bootOk ? 'disabled' : ''}>Laden</button>`}
								<a class="btn sm ghost" href="${r.url}" target="_blank" rel="noopener">Notes ↗</a></td></tr>`)}
						</tbody></table></div></div>` : ''}
				${latest?.notes ? html`<div class="panel"><div class="ph"><span class="pt">ÄNDERUNGEN IN ${latest.version}</span></div><pre class="notes">${latest.notes}</pre></div>` : ''}
			</section>
			<aside class="aside">
				<div class="panel">
					<div class="ph"><span class="pt">SO LÄUFT EIN UPDATE</span></div>
					<ol class="plan" style="padding-left:20px">
						<li>Paket von GitHub laden und prüfen (SHA-256, Gerät, Größen)</li>
						<li>Kernel und Startsystem in den Flash schreiben und zurücklesen</li>
						<li>Neues System bereitlegen</li>
						<li>Neustart: das Startsystem installiert das System, dann startet ShareOS neu</li>
					</ol>
					<p class="note">Einstellungen und installierte Pakete bleiben erhalten. Bei einem Abbruch wird die Installation beim nächsten Start wiederholt.</p>
				</div>
			</aside>
		</div>`;
	},

	allgemein() {
		const i = S.info || {};
		return html`<div class="g2">
			<form class="panel" id="f-host">
				<div class="ph"><span class="pt">GERÄTENAME</span></div>
				<div class="fields" style="grid-template-columns:1fr"><label class="f"><span>HOSTNAME</span><input name="hostname" value="${i.hostname || ''}" pattern="[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?" required></label></div>
				<p class="note">Buchstaben, Ziffern und Bindestrich. Gilt sofort, der DHCP-Server sieht ihn bei der nächsten Verlängerung.</p>
				<div class="acts" style="margin-top:14px"><button class="btn primary" type="submit">Speichern</button></div>
			</form>
			<form class="panel" id="f-pass">
				<div class="ph"><span class="pt">ZUGANG · ${S.user}</span></div>
				<div class="fields" style="grid-template-columns:1fr">
					<label class="f"><span>NEUES PASSWORT</span><input name="p1" type="password" minlength="6" autocomplete="new-password" required></label>
					<label class="f"><span>WIEDERHOLEN</span><input name="p2" type="password" minlength="6" autocomplete="new-password" required></label>
				</div>
				<p class="note">Gilt für die Weboberfläche und SSH. Mindestens 6 Zeichen.</p>
				<div class="acts" style="margin-top:14px"><button class="btn primary" type="submit">Passwort ändern</button></div>
			</form>
		</div>`;
	},

	energie() {
		return html`<div class="g2">
			<div class="panel">
				<div class="ph"><span class="pt">ENERGIE</span></div>
				<div class="acts"><button class="btn" type="button" data-act="reboot">${svg(I.reboot)}Neustart</button>
					<button class="btn danger" type="button" data-act="poweroff">${svg(I.power)}Ausschalten</button></div>
				<p class="note">Beim Ausschalten fährt ShareOS herunter und die Gerätesteuerung schaltet den Strom ab. Einschalten über den Power-Taster.</p>
			</div>
			<div class="panel">
				<div class="ph"><span class="pt">WERKSEINSTELLUNGEN</span><span class="tag err ml">löscht Einstellungen</span></div>
				<p class="mut" style="margin:0 0 12px;font-size:13px">Entfernt alle Einstellungen und installierten Pakete aus dem Flash und startet neu. Das System selbst und die Firmware-Version bleiben. Danach gilt wieder das Passwort <code>shareos</code>.</p>
				<button class="btn danger" type="button" data-act="factory">Auf Werkseinstellungen zurücksetzen</button>
			</div>
		</div>`;
	},

	protokolle() {
		return html`<div class="panel">
			<div class="ph"><span class="pt">PROTOKOLL</span>
				<div class="acts ml"><select id="log-src" class="btn sm ghost" aria-label="Quelle"><option value="system">System (syslog)</option><option value="kernel">Kernel (dmesg)</option></select>
				<button class="btn sm" type="button" data-act="log">Aktualisieren</button></div></div>
			<pre class="logbox" id="logbox">lade …</pre>
		</div>`;
	},

	darstellung() {
		const names = { green: 'Grün', red: 'Rot', blue: 'Blau', white: 'Weiß' };
		return html`<div class="panel" style="max-width:560px">
			<div class="ph"><span class="pt">DARSTELLUNG</span><span class="tag ml">nur in diesem Browser</span></div>
			<div class="row">${Object.keys(names).map((c) => html`<button class="sw c-${c}${S.accent === c ? ' on' : ''}" type="button" data-act="accent" data-c="${c}" aria-label="Akzentfarbe ${names[c]}" aria-pressed="${S.accent === c}"><i></i></button>`)}</div>
			<div style="display:grid;gap:6px;margin-top:14px">
				<label class="chk"><input type="checkbox" id="opt-light"${S.theme === 'light' ? raw(' checked') : ''}>Helles Design</label>
				<label class="chk"><input type="checkbox" id="opt-scan"${S.scan ? raw(' checked') : ''}>Scanlines</label>
			</div>
		</div>`;
	},

	ueber() {
		const i = S.info || {}, r = i.release || {};
		return html`<div class="g2">
			<div class="panel">
				<div class="ph"><span class="pt">SHAREOS</span></div>
				<dl class="kv">
					<dt>Version</dt><dd>${r.version || '–'}</dd>
					<dt>Stufe</dt><dd>${r.stage || '–'}</dd>
					<dt>Gerät</dt><dd>${i.model || '–'}</dd>
					<dt>Firmware-Name</dt><dd>${r.fwname || '–'}</dd>
					<dt>Kernel</dt><dd>Linux ${i.kernel || '–'}</dd>
					<dt>Start aus</dt><dd>${i.boot || '–'}</dd>
				</dl>
			</div>
			<div class="panel">
				<div class="ph"><span class="pt">PROJEKT</span></div>
				<p class="mut" style="margin:0;font-size:13px;line-height:1.6">ShareOS ist eine freie Firmware für D-Link-NAS, hervorgegangen aus Alt-F. Basis: buildroot, Linux, BusyBox; Bedienkonzept nach OpenWrt (UCI, ubus, rpcd, ucode). Lizenz GPLv2.</p>
				<p class="note"><a href="https://github.com/UniqueDroid/ShareOS" target="_blank" rel="noopener">github.com/UniqueDroid/ShareOS ↗</a></p>
			</div>
		</div>`;
	}
};

/* ---------- per-view setup after render ------------------------------------- */

const VIEWS_AFTER = {
	system() {
		const sub = S.route.sub;
		if (sub === 'protokolle') loadLog();
		if (sub === 'allgemein') {
			$('#f-host').addEventListener('submit', async (e) => {
				e.preventDefault();
				try { await rpc('shareos.system', 'set_hostname', { hostname: e.target.hostname.value.trim() }); toast('Hostname gespeichert.'); tick(); }
				catch (err) { toast('Hostname: ' + err.message, true); }
			});
			$('#f-pass').addEventListener('submit', async (e) => {
				e.preventDefault();
				const f = e.target;
				if (f.p1.value !== f.p2.value) { toast('Die Passwörter stimmen nicht überein.', true); return; }
				try { await rpc('shareos.system', 'set_password', { password: f.p1.value }); f.reset(); toast('Passwort geändert.'); }
				catch (err) { toast('Passwort: ' + err.message, true); }
			});
		}
		if (sub === 'darstellung') {
			$('#opt-light').addEventListener('change', (e) => { S.theme = e.target.checked ? 'light' : 'dark'; store.set('theme', S.theme); applyTheme(); });
			$('#opt-scan').addEventListener('change', (e) => { S.scan = e.target.checked; store.set('scan', S.scan ? '1' : '0'); applyTheme(); });
		}
		if (sub === 'firmware') {
			$('#channel')?.addEventListener('change', async (e) => {
				try {
					await rpc('uci', 'set', { config: 'shareos', section: 'update', values: { channel: e.target.value } });
					await rpc('uci', 'commit', { config: 'shareos' });
					checkUpdates();
				} catch (err) { toast('Kanal: ' + err.message, true); }
			});
		}
	},
	speicher() {
		if (!S.stActive) loadStorage();
		$('#spindown')?.addEventListener('change', async (e) => {
			try { await rpc('shareos.storage', 'spindown', { minutes: +e.target.value }); toast('Ruhezustand gespeichert.'); }
			catch (err) { toast('Ruhezustand: ' + err.message, true); }
		});
	},
	dienste() { if (!S.services) loadServices(); },
	uebersicht() { if (!S.services) loadServices(); }
};

async function loadLog() {
	const box = $('#logbox');
	if (!box) return;
	try {
		const r = await rpc('shareos.system', 'log', { lines: 300, source: $('#log-src')?.value || 'system' });
		box.textContent = (r.lines || []).join('\n') || '(leer)';
		box.scrollTop = box.scrollHeight;
	} catch (e) { box.textContent = 'Fehler: ' + e.message; }
}

/* ---------- update flow ----------------------------------------------------- */

async function checkUpdates(quiet = false) {
	S.checking = true;
	if (S.route.sub === 'firmware') renderMain();
	try {
		S.check = await rpc('shareos.update', 'check');
		if (!quiet) toast(S.check.update_available ? `Update ${S.check.latest} verfügbar.` : 'ShareOS ist aktuell.');
	} catch (e) {
		if (!quiet && e.code !== 'auth') toast('Prüfen fehlgeschlagen: ' + e.message, true);
	}
	S.checking = false;
	renderHeader();
	if (S.route.tab === 'system' && S.route.sub === 'firmware') renderMain();
}

async function refreshUpdateStatus() {
	clearTimeout(S.updTimer);
	try {
		const prev = S.upd?.state;
		S.upd = await rpc('shareos.update', 'status');
		if (S.upd.check && !S.check) S.check = { ...S.upd.check, current: S.upd.current };
		// look for updates now and then (GitHub allows 60 anonymous API calls per hour)
		if (!prev && !S.checking && (!S.upd.check || Date.now() / 1000 - S.upd.check.time > 6 * 3600)) checkUpdates(true);
		if (S.route.tab === 'system' && S.route.sub === 'firmware' && !document.activeElement?.matches('select')) renderMain();
		if (prev && prev !== S.upd.state && S.upd.state === 'ready') toast('Update geladen und geprüft.');
		if (prev && prev !== S.upd.state && S.upd.state === 'flashed') toast('Update geschrieben – bitte neu starten.');
		const busy = ['downloading', 'verifying', 'flashing'].includes(S.upd.state);
		S.updTimer = setTimeout(refreshUpdateStatus, busy ? 1000 : 30000);
	} catch (e) {
		if (e.code !== 'auth') S.updTimer = setTimeout(refreshUpdateStatus, 10000);
	}
}

/* ---------- actions (delegated clicks) -------------------------------------- */

const ACTIONS = {
	theme() { S.theme = S.theme === 'light' ? 'dark' : 'light'; store.set('theme', S.theme); applyTheme(); },
	logout,
	accent(el) { S.accent = el.dataset.c; store.set('accent', S.accent); applyTheme(); renderMain(); },
	check() { checkUpdates(); },
	'wiz-start'() {
		const disks = (S.storage?.disks || []).filter((d) => !d.rm && d.tran !== 'usb').map((d) => d.name);
		S.wiz = { step: 0, disks: disks.slice(0, 2), layout: disks.length >= 2 ? 'mirror' : 'single', names: { __mirror: 'daten' } };
		renderMain();
		window.scrollTo(0, 0);
	},
	'wiz-cancel'() { S.wiz = null; renderMain(); },
	'wiz-back'() { wizardCollect(); S.wiz.step--; renderMain(); },
	'wiz-next'() {
		wizardCollect();
		const err = wizardCheck();
		if (err) { toast(err, true); return; }
		const w = S.wiz;
		if (w.step === 1 && w.layout === 'single') w.disks.forEach((d, k) => { if (!w.names[d]) w.names[d] = k ? 'daten' + (k + 1) : 'daten'; });
		w.step++;
		renderMain();
	},
	async 'wiz-run'() {
		const w = S.wiz;
		if (!await confirmDlg('Platten löschen und einrichten?', `${w.disks.join(' und ')} werden vollständig gelöscht. Das lässt sich nicht rückgängig machen.`, 'Löschen & einrichten', true)) return;
		const args = w.layout === 'mirror'
			? { layout: 'mirror', name: w.names.__mirror, disks: w.disks, confirm: true }
			: { layout: 'single', volumes: w.disks.map((d) => ({ name: w.names[d], disk: d })), confirm: true };
		try { await rpc('shareos.storage', 'setup', args); S.wiz = null; toast('Einrichtung gestartet.'); setTimeout(loadStorage, 1000); }
		catch (e) { toast('Einrichten: ' + e.message, true); }
	},
	async format(el) {
		const disk = el.dataset.disk;
		const d = S.storage.disks.find((x) => x.name === disk);
		const name = ((await promptDlg(`${disk} formatieren`, 'Name des neuen Laufwerks (a–z, 0–9, - und _, max. 16 Zeichen):', 'daten', 'Weiter')) || '').toLowerCase();
		if (!name) return;
		if (!NAME_RE.test(name)) { toast('Ungültiger Name.', true); return; }
		if (!await confirmDlg(`${disk} löschen?`, `${disk} (${d?.model || ''}, ${fmtBytes(d?.size)}) wird vollständig gelöscht und als Laufwerk „${name}“ neu eingerichtet.`, 'Löschen & formatieren', true)) return;
		try { await rpc('shareos.storage', 'setup', { layout: 'single', volumes: [{ name, disk }], confirm: true }); toast('Formatieren gestartet.'); setTimeout(loadStorage, 1000); }
		catch (e) { toast('Formatieren: ' + e.message, true); }
	},
	async smart(el) {
		el.disabled = true;
		try { await rpc('shareos.storage', 'smart', { disk: el.dataset.disk }); } catch (e) { toast('SMART: ' + e.message, true); }
		loadStorage();
	},
	async vol(el) {
		const { name, op } = el.dataset;
		if (op === 'forget' && !await confirmDlg(`„${name}“ entfernen?`, 'Das Laufwerk wird ausgehängt und aus der Konfiguration genommen. Die Daten auf der Platte bleiben erhalten, bis sie neu eingerichtet wird.', 'Entfernen')) return;
		try { await rpc('shareos.storage', 'volume', { name, action: op }); toast(`${name}: ${op === 'mount' ? 'eingehängt' : op === 'umount' ? 'ausgehängt' : 'entfernt'}`); }
		catch (e) { toast(`${name}: ${e.message}`, true); }
		loadStorage();
	},

	log() { loadLog(); },

	async svc(el) {
		const { name, op } = el.dataset;
		el.disabled = true;
		try {
			const r = await rpc('shareos.service', 'action', { name, action: op });
			if (r.delayed) { waitForBox('Dienst wird neu gestartet', 'warte auf die Box', false); return; }
			toast(`${name}: ${op === 'start' ? 'gestartet' : op === 'stop' ? 'gestoppt' : 'neu gestartet'}`);
		} catch (e) { toast(`${name}: ${e.message}`, true); }
		loadServices();
	},

	async download(el) {
		try { await rpc('shareos.update', 'download', { tag: el.dataset.tag }); S.upd = { ...S.upd, state: 'downloading' }; refreshUpdateStatus(); }
		catch (e) { toast('Download: ' + e.message, true); }
	},

	async apply(el) {
		const tag = el.dataset.tag;
		if (!await confirmDlg('Update installieren?', `ShareOS ${tag.replace(/^v/, '')} wird in den Flash geschrieben. Danach ist ein Neustart nötig, bei dem das neue System installiert wird. Während des Schreibens die Box nicht ausschalten.`, 'Installieren')) return;
		try { await rpc('shareos.update', 'apply', { tag, confirm: true }); S.upd = { ...S.upd, state: 'flashing' }; refreshUpdateStatus(); }
		catch (e) { toast('Installieren: ' + e.message, true); }
	},

	async cancel() {
		try { S.upd = await rpc('shareos.update', 'cancel'); renderMain(); } catch (e) { toast(e.message, true); }
	},

	async reboot() {
		if (!await confirmDlg('Neu starten?', 'Die Box startet neu. Die Seite verbindet sich danach von selbst wieder (ca. 1–2 Minuten).', 'Neu starten')) return;
		try { await rpc('shareos.system', 'reboot'); } catch (e) { }
		stopPolling();
		waitForBox('Neustart läuft', 'ShareOS startet neu');
	},

	async poweroff() {
		if (!await confirmDlg('Ausschalten?', 'ShareOS fährt herunter und die Box schaltet sich aus. Einschalten danach nur am Gerät.', 'Ausschalten', true)) return;
		try { await rpc('shareos.system', 'poweroff', { confirm: true }); } catch (e) { toast(e.message, true); return; }
		stopPolling();
		cover('Box wird ausgeschaltet', 'Du kannst dieses Fenster schließen.');
	},

	async factory() {
		if (!await confirmDlg('Werkseinstellungen?', 'Alle Einstellungen und installierten Pakete werden gelöscht, danach startet die Box neu. Das Passwort ist dann wieder „shareos“.', 'Zurücksetzen', true)) return;
		try { await rpc('shareos.system', 'factory_reset', { confirm: true }); } catch (e) { toast(e.message, true); return; }
		stopPolling();
		store.del('sid');
		waitForBox('Werkseinstellungen', 'ShareOS startet neu');
	}
};

document.addEventListener('click', (e) => {
	const el = e.target.closest('[data-act]');
	if (!el || el.disabled) return;
	const fn = ACTIONS[el.dataset.act];
	if (fn) { e.preventDefault(); fn(el); }
});

document.addEventListener('change', (e) => {
	if (e.target.name === 'wiz-layout' && S.wiz) { wizardCollect(); renderMain(); }
});

window.addEventListener('hashchange', () => {
	if (!S.sid || !$('#main')) return;
	parseRoute();
	if (S.route.tab !== 'speicher') { clearTimeout(S.stTimer); S.stTimer = null; S.stActive = false; }
	renderTabs();
	renderMain();
	window.scrollTo(0, 0);
});

// clock in the header without waiting for the next poll
setInterval(() => {
	const c = $('.clock');
	if (c) c.textContent = new Date().toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}, 10000);

/* ---------- start ----------------------------------------------------------- */

(async function start() {
	applyTheme();
	if (S.sid) {
		try {
			await rpc('session', 'access', { scope: 'ubus', object: 'shareos.system', function: 'info' });
			renderShell();
			return;
		} catch (e) { S.sid = null; store.del('sid'); }
	}
	renderLogin();
})();
