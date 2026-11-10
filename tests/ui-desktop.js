// Desktop view (module "desktop") in Chromium with Playwright, against the
// mock box (tests/mock-ubus.py): login choice, icons, windows (iframes in
// frame mode), moving, snapping, resizing, maximising, minimising, control
// panel, start menu search, wallpaper, theme to all windows, layout saved per
// account, switching views, plain users, module removed.
//
//   node tests/ui-desktop.js        (needs playwright and python3)
//   SHOTS=/tmp/desk node tests/ui-desktop.js   also writes screenshots
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path'), fs = require('fs');

const TOP = path.resolve(__dirname, '..');
const PORT = 18200 + Math.floor(Math.random() * 700);
const URL0 = `http://127.0.0.1:${PORT}/`;
const SID = 'c0ffee00c0ffee00c0ffee00c0ffee00';
const srv = spawn('python3', [path.join(TOP, 'tests/mock-ubus.py'), String(PORT)], { stdio: 'ignore' });
const SHOTS = process.env.SHOTS;
if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });

let pass = 0, fail = 0;
function check(name, ok, info = '') { console.log((ok ? 'PASS  ' : 'FAIL  ') + name + (ok || !info ? '' : '  (' + info + ')')); ok ? pass++ : fail++; }
const rpc = (obj, method, args = {}) => fetch(URL0 + 'ubus', { method: 'POST', headers: { 'Content-Type': 'application/json' },
	body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'call', params: [SID, obj, method, args] }) }).then((r) => r.json());
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
	for (let i = 0; i < 40; i++) { try { await fetch(URL0); break; } catch (e) { await sleep(150); } }
	await rpc('shareos.setup', 'apply', {});   // no first-run wizard
	const b = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
	const ctx = await b.newContext({ viewport: { width: 1440, height: 900 } });
	const p = await ctx.newPage();
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	const shot = async (n) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, n + '.png') }); };
	const rect = (sel) => p.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
	const win = (id) => `.dk-win[data-id="${id}"]`;
	const drag = async (sel, dx, dy, to) => {
		const r = await rect(sel);
		const x = r.x + Math.min(120, r.w / 3), y = r.y + r.h / 2;
		await p.mouse.move(x, y); await p.mouse.down();
		await p.mouse.move(x + 10, y + 5, { steps: 2 });
		if (to) await p.mouse.move(to[0], to[1], { steps: 8 }); else await p.mouse.move(x + dx, y + dy, { steps: 8 });
		await p.mouse.up();
	};

	// login page: both views offered, desktop chosen
	await p.goto(URL0);
	await p.waitForSelector('#login-form');
	check('login: view choice shown (module installed)', await p.locator('.viewpick [data-view]').count() === 2);
	check('login: desktop preselected', await p.locator('.vbtn.on[data-view="desktop"]').count() === 1);
	await shot('01-login');
	await p.click('[data-view="classic"]');
	check('login: choice switches', await p.locator('.vbtn.on[data-view="classic"]').count() === 1);
	await p.click('[data-view="desktop"]');
	await p.fill('input[name=user]', 'root');
	await p.fill('input[name=pass]', 'shareos');
	await p.click('#login-form button[type=submit]');
	await p.waitForSelector('#dk .dk-ico');
	await sleep(400);
	const labels = await p.$$eval('.dk-ico .dk-il', (l) => l.map((x) => x.textContent));
	const ids = await p.$$eval('.dk-ico', (l) => l.map((x) => x.dataset.open));
	check('desktop: icons of the areas', ['files', 'storage', 'shares', 'services', 'panel', 'store', 'task', 'logs', 'term'].every((x) => ids.includes(x)), ids.join(','));
	check('desktop: module icons (cloud, paperless, dns filter)', labels.some((x) => /Cloud/.test(x)) && labels.some((x) => /Paperless/.test(x)) && labels.some((x) => /DNS/.test(x)), labels.join(','));
	check('desktop: web app icon (Webpad)', labels.includes('Webpad'));
	check('desktop: no page header', await p.locator('#hd').count() === 0);

	// a window with the storage page in frame mode
	await p.click('.dk-ico[data-open="storage"]');
	await p.waitForSelector(win('storage') + ' iframe');
	const fr = p.frameLocator(win('storage') + ' iframe');
	await fr.locator('#main .subtabs').waitFor();
	check('window: page inside (frame mode)', await fr.locator('#main .subtabs a').count() > 0);
	check('window: no header and tabs inside', !(await fr.locator('#hd').isVisible()) && !(await fr.locator('#tabs').isVisible()));
	check('taskbar: window listed', await p.locator('.dk-tw[data-task="storage"]').count() === 1);

	// move
	const r0 = await rect(win('storage'));
	await drag(win('storage') + ' .dk-wt', 140, 60);
	const r1 = await rect(win('storage'));
	check('window: moved by the title bar', Math.abs(r1.x - r0.x - 140) < 3 && Math.abs(r1.y - r0.y - 60) < 3, JSON.stringify([r0, r1]));
	// resize
	const rs = await rect(win('storage') + ' [data-rs=se]');
	await p.mouse.move(rs.x + 5, rs.y + 5); await p.mouse.down();
	await p.mouse.move(rs.x + 60, rs.y + 45, { steps: 6 }); await p.mouse.up();
	const r2 = await rect(win('storage'));
	check('window: resized at the corner', r2.w > r1.w + 40 && r2.h > r1.h + 30, JSON.stringify([r1, r2]));
	// snap left
	await drag(win('storage') + ' .dk-wt', 0, 0, [1, 300]);
	const r3 = await rect(win('storage'));
	check('window: snapped to the left half', r3.x === 0 && Math.abs(r3.w - 720) < 2 && r3.y === 56, JSON.stringify(r3));
	// pulled off the edge: back in its own size
	await drag(win('storage') + ' .dk-wt', 300, 120);
	const r4 = await rect(win('storage'));
	check('window: own size again after leaving the half', Math.abs(r4.w - r2.w) < 2, JSON.stringify([r2, r4]));
	// maximise by double click
	await p.dblclick(win('storage') + ' .dk-wt h2');
	const r5 = await rect(win('storage'));
	check('window: maximised by double click', r5.x === 0 && r5.w === 1440 && r5.y === 56 && r5.h === 844, JSON.stringify(r5));
	await p.dblclick(win('storage') + ' .dk-wt h2');
	check('window: restored', Math.abs((await rect(win('storage'))).w - r4.w) < 2);

	// control panel -> network page in a window
	await p.click('.dk-ico[data-open="panel"]');
	await p.waitForSelector(win('panel') + ' .dk-cat');
	check('control panel: categories', await p.locator(win('panel') + ' .dk-ch').count() >= 4);
	await p.fill('#dk-pq', 'netz');
	const hits = await p.$$eval(win('panel') + ' .dk-cat span', (l) => l.map((x) => x.textContent));
	check('control panel: search', hits.length >= 1 && hits.length < 4, hits.join(','));
	await p.click(win('panel') + ' .dk-cat[data-id="r:#/system/network"]');
	await p.waitForSelector(win('r:#/system/network') + ' iframe');
	check('control panel: setting opens in its own window', await p.locator('.dk-win').count() === 3);
	check('focus: newest window on top', await p.$eval(win('r:#/system/network'), (e) => e.classList.contains('on')));
	await p.frameLocator(win('r:#/system/network') + ' iframe').locator('#main form, #main .panel').first().waitFor();
	await sleep(600);
	await shot('02-windows');

	// minimise and back from the taskbar
	await p.click('.dk-tw[data-task="panel"]');   // to the front (the network window covers it)
	await p.click(win('panel') + ' [data-w=min]');
	check('window: minimised', !(await p.locator(win('panel')).isVisible()));
	await p.click('.dk-tw[data-task="panel"]');
	check('taskbar: brings it back', await p.locator(win('panel')).isVisible());
	await p.click(win('panel') + ' [data-w=close]');
	check('window: closed', await p.locator(win('panel')).count() === 0 && await p.locator('.dk-tw[data-task="panel"]').count() === 0);

	// start menu search
	await p.click('[data-dk=start]');
	await p.waitForSelector('#dk-start:not([hidden]) .dk-st');
	await shot('03-start');
	await p.fill('#dk-q', 'proto');
	const sh = await p.$$eval('#dk-sl .dk-st span', (l) => l.map((x) => x.textContent));
	check('start menu: search finds the logs', sh.length >= 1 && sh.some((x) => /Log|Proto/.test(x)), sh.join(','));
	await p.keyboard.press('Escape');
	check('start menu: Esc closes it', await p.locator('#dk-start').isHidden());

	// wallpaper from the box
	await p.click('#dk-av');
	await p.click('#dk-menu [data-dk=wall]');
	await p.waitForSelector('dialog.dk-wd .fb-item');
	await p.click('dialog.dk-wd [data-place="0"]');
	await p.click('dialog.dk-wd [data-dir="Fotos"]');
	await p.click('dialog.dk-wd [data-img="Urlaub_Ostsee_001.jpg"]');
	await p.waitForFunction(() => document.querySelector('#dk-wall').classList.contains('img'));
	check('wallpaper: image of the box shown', (await p.$eval('#dk-wall', (e) => e.style.backgroundImage)).startsWith('url("blob:'));
	await p.selectOption('#dk-fit', 'contain');
	check('wallpaper: fit', await p.waitForFunction(() => document.querySelector('#dk-wall').classList.contains('fit-contain')).then(() => true, () => false));
	await p.click('dialog.dk-wd button[value=no]');
	await shot('04-wallpaper');

	// theme: desktop and every window
	await p.click('#dk-av');
	await p.click('#dk-menu [data-dk=theme]');
	await sleep(300);
	check('theme: desktop light', await p.$eval('#app', (e) => e.classList.contains('light')));
	check('theme: window light too', await p.frameLocator(win('storage') + ' iframe').locator('#app.light').count() === 1);
	await shot('05-light');

	// a theme change inside a window reaches the desktop
	const nf = p.frameLocator(win('r:#/system/network') + ' iframe');
	await nf.locator('#app').evaluate(() => { S.theme = 'dark'; applyTheme(); });
	await sleep(300);
	check('theme: from a window to the desktop', !(await p.$eval('#app', (e) => e.classList.contains('light'))));
	check('theme: and to the other windows', await p.frameLocator(win('storage') + ' iframe').locator('#app.light').count() === 0);

	// icons can be moved (and are saved)
	const i0 = await rect('.dk-ico[data-open="term"]');
	await p.mouse.move(i0.x + 40, i0.y + 30); await p.mouse.down();
	await p.mouse.move(i0.x + 400, i0.y + 30, { steps: 8 }); await p.mouse.up();
	const i1 = await rect('.dk-ico[data-open="term"]');
	check('icons: moved to another cell', i1.x - i0.x > 300 && Math.abs(i1.y - i0.y) < 2, JSON.stringify([i0, i1]));
	check('icons: a drag does not open a window', await p.locator(win('term')).count() === 0);

	// layout saved on the box, back after a reload
	await sleep(1200);
	const saved = await rpc('shareos.me', 'desk_get');
	const d = saved.result?.[1]?.desk || {};
	check('saved: open windows, places, icons, wallpaper', (d.open || []).length === 2 && d.geo?.storage && d.icons?.term && d.wall?.name === 'Urlaub_Ostsee_001.jpg', JSON.stringify(d).slice(0, 200));
	await p.reload();
	await p.waitForSelector(win('storage'));
	await sleep(500);
	check('reload: windows come back', await p.locator('.dk-win').count() === 2);
	check('reload: icon place kept', Math.abs((await rect('.dk-ico[data-open="term"]')).x - i1.x) < 2);
	check('reload: wallpaper kept', await p.waitForFunction(() => document.querySelector('#dk-wall').classList.contains('img')).then(() => true, () => false));

	// classic view and back
	await p.click('#dk-av');
	await p.click('#dk-menu [data-dk=classic]');
	await p.waitForSelector('#hd .clock');
	check('classic: page with header', await p.locator('#tabs .tab').count() > 3);
	check('classic: button to the desktop', await p.locator('[data-act="desk-view"]').count() === 1);
	await shot('06-classic');
	await p.click('[data-act="desk-view"]');
	await p.waitForSelector('#dk .dk-ico');
	check('desktop again', await p.locator('.dk-win').count() === 2);

	// log out
	await p.click('[data-dk=start]');
	await p.click('#dk-start [data-dk=logout]');
	await p.waitForSelector('#login-form');
	check('logout: login page', await p.locator('#dk').count() === 0);

	// a plain user: own areas only
	await p.fill('input[name=user]', 'anna');
	await p.fill('input[name=pass]', 'anna123');
	await p.click('#login-form button[type=submit]');
	await p.waitForSelector('#dk .dk-ico');
	const ul = await p.$$eval('.dk-ico', (l) => l.map((x) => x.dataset.open));
	check('user: own icons', ul.includes('me') && ul.includes('settings') && !ul.includes('panel') && !ul.includes('storage'), ul.join(','));
	await p.click('.dk-ico[data-open="me"]');
	await p.waitForSelector(win('me') + ' iframe');
	await p.frameLocator(win('me') + ' iframe').locator('#main').waitFor();
	check('user: window with My ShareOS', await p.frameLocator(win('me') + ' iframe').locator('#main section').count() > 0);
	await shot('07-user');
	await p.click('[data-dk=start]');
	await p.click('#dk-start [data-dk=logout]');
	await p.waitForSelector('#login-form');

	// module removed: no choice on the login page, classic page after login
	await rpc('shareos.apps', 'remove', { id: 'desktop' });
	await p.reload();
	await p.waitForSelector('#login-form');
	check('without module: no view choice', await p.locator('.viewpick').count() === 0);
	await p.fill('input[name=user]', 'root');
	await p.fill('input[name=pass]', 'shareos');
	await p.click('#login-form button[type=submit]');
	await p.waitForSelector('#hd .clock');
	check('without module: classic page', await p.locator('#dk').count() === 0 && await p.locator('[data-act="desk-view"]').count() === 0);
	const g = await rpc('shareos.me', 'desk_get');
	check('without module: desk_get refused', g.result?.[1]?.error === 'not installed');

	check('no script errors', errors.length === 0, errors.join(' | '));
	await b.close();
	srv.kill();
	console.log(`\n${pass} passed, ${fail} failed`);
	process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); srv.kill(); process.exit(1); });
