/* ShareOS wiki: renders the Markdown documents of the repository (copied into the site by build.py) */
(function () {
  'use strict';
  var GH = 'https://github.com/UniqueDroid/ShareOS/blob/main/';
  var RAW = 'https://raw.githubusercontent.com/UniqueDroid/ShareOS/main/';
  var S = window.ShareOSSite;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  // key: { path, title, group, de?: key of the German version, en?: key of the English version }
  var DOCS = [
    { key: 'README', path: 'README.md', title: 'Overview', group: 'Start' },
    { key: 'SWITCHING', path: 'docs/SWITCHING.md', title: 'Install & switch back', group: 'Start', de: 'UMSTIEG' },
    { key: 'DEVICES', path: 'docs/DEVICES.md', title: 'Devices & testers', group: 'Start', de: 'GERAETE' },
    { key: 'TESTING', path: 'docs/TESTING.md', title: 'Testing guide', group: 'Start', de: 'TESTEN' },
    { key: 'MONITORING', path: 'docs/MONITORING.md', title: 'Monitoring with Zabbix', group: 'Using ShareOS', de: 'UEBERWACHUNG' },
    { key: 'TRANSLATING', path: 'docs/TRANSLATING.md', title: 'Translating', group: 'Using ShareOS' },
    { key: 'DEVELOPMENT', path: 'docs/DEVELOPMENT.md', title: 'Development timeline', group: 'Development', de: 'ENTWICKLUNG' },
    { key: 'BUILD', path: 'docs/BUILD.md', title: 'Building', group: 'Development' },
    { key: 'BACKEND', path: 'docs/BACKEND.md', title: 'Backend', group: 'Development' },
    { key: 'FLASH-LAYOUT', path: 'docs/FLASH-LAYOUT.md', title: 'Flash layout & boot', group: 'Development' },
    { key: 'HARDWARE-DNS320L', path: 'docs/HARDWARE-DNS320L.md', title: 'DNS-320L hardware', group: 'Development' },
    { key: 'RELEASE', path: 'docs/RELEASE.md', title: 'Releasing', group: 'Development' },
    { key: 'CHANGELOG', path: 'CHANGELOG.md', title: 'Changelog', group: 'History' },
    // German versions (reachable through the language switch and links)
    { key: 'UMSTIEG', path: 'docs/UMSTIEG.md', title: 'Umstieg', en: 'SWITCHING', hidden: true },
    { key: 'GERAETE', path: 'docs/GERAETE.md', title: 'Geräte', en: 'DEVICES', hidden: true },
    { key: 'TESTEN', path: 'docs/TESTEN.md', title: 'Testen', en: 'TESTING', hidden: true },
    { key: 'UEBERWACHUNG', path: 'docs/UEBERWACHUNG.md', title: 'Überwachung', en: 'MONITORING', hidden: true },
    { key: 'ENTWICKLUNG', path: 'docs/ENTWICKLUNG.md', title: 'Entwicklung', en: 'DEVELOPMENT', hidden: true }
  ];
  var byKey = {}, byPath = {};
  DOCS.forEach(function (d) { byKey[d.key] = d; byPath[d.path] = d; });

  /* ---------- sidebar ---------- */
  var list = $('[data-doclist]'), groups = {};
  DOCS.forEach(function (d) { if (!d.hidden) (groups[d.group] = groups[d.group] || []).push(d); });
  list.innerHTML = Object.keys(groups).map(function (g) {
    return '<h6>' + S.esc(g) + '</h6>' + groups[g].map(function (d) { return '<a href="#' + d.key + '" data-key="' + d.key + '">' + S.esc(d.title) + '</a>'; }).join('');
  }).join('');
  var side = $('[data-side]');
  $('[data-side-toggle]').addEventListener('click', function () { side.classList.toggle('open'); });

  /* ---------- paths and links ---------- */
  function dirname(p) { var i = p.lastIndexOf('/'); return i < 0 ? '' : p.slice(0, i + 1); }
  function normalize(p) {
    var out = [];
    p.split('/').forEach(function (s) { if (s === '..') out.pop(); else if (s !== '.' && s !== '') out.push(s); });
    return out.join('/');
  }
  function slugify(t) { return t.toLowerCase().trim().replace(/<[^>]+>/g, '').replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-'); }
  function rewrite(root, doc) {
    var base = dirname(doc.path);
    $$('a[href]', root).forEach(function (a) {
      var href = a.getAttribute('href');
      if (/^(https?:|mailto:)/i.test(href)) { a.rel = 'noopener'; return; }
      if (href.charAt(0) === '#') { a.setAttribute('href', '#' + doc.key + '/' + href.slice(1)); return; }
      var parts = href.split('#'), target = normalize(base + parts[0]), anchor = parts[1] ? '/' + parts[1] : '';
      if (byPath[target]) a.setAttribute('href', '#' + byPath[target].key + anchor);
      else { a.setAttribute('href', GH + target + (parts[1] ? '#' + parts[1] : '')); a.rel = 'noopener'; }
    });
    $$('img[src]', root).forEach(function (img) {
      var src = img.getAttribute('src');
      if (/^(https?:|data:)/i.test(src)) return;
      var target = normalize(base + src);
      img.setAttribute('src', /^docs\/images\//.test(target) ? target : RAW + target);
      img.loading = 'lazy';
    });
  }

  /* ---------- loading ---------- */
  var cache = {};
  function load(doc) {
    if (!cache[doc.key]) cache[doc.key] = fetch(doc.path).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    }).catch(function () {
      return fetch(RAW + doc.path).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); });
    });
    return cache[doc.key];
  }

  var art = $('[data-doc]'), toc = $('[data-toc]'), lang = $('[data-lang]'), edit = $('[data-edit]'), current = null, spy = null;
  function show(key, anchor) {
    var doc = byKey[key] || byKey.README;
    $$('a[data-key]', list).forEach(function (a) {
      var on = a.dataset.key === doc.key || a.dataset.key === doc.en;
      if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
    side.classList.remove('open');
    edit.href = GH + doc.path;
    var en = doc.en ? byKey[doc.en] : doc, de = doc.de ? byKey[doc.de] : (doc.en ? doc : null);
    if (de) {
      lang.hidden = false;
      lang.innerHTML = '<a href="#' + en.key + '" aria-current="' + (doc === en) + '">English</a><a href="#' + de.key + '" aria-current="' + (doc === de) + '">Deutsch</a>';
    } else lang.hidden = true;
    var go = function () {
      var el = anchor && document.getElementById(decodeURIComponent(anchor));
      if (el) el.scrollIntoView(); else window.scrollTo(0, 0);
    };
    if (current === doc.key) { go(); return; }
    current = doc.key;
    document.title = (byKey[doc.en] || doc).title + ' – ShareOS Wiki';
    art.innerHTML = '<p class="muted">Loading …</p>';
    Promise.all([load(doc), S.markdown()]).then(function (r) {
      if (current !== doc.key) return;
      art.innerHTML = r[1](r[0]);
      var seen = {};
      $$('h1,h2,h3,h4', art).forEach(function (h) {
        var s = slugify(h.textContent), id = s, n = 1;
        while (seen[id]) id = s + '-' + n++;
        seen[id] = 1; h.id = id;
      });
      rewrite(art, doc);
      buildToc();
      go();
    }).catch(function () {
      art.innerHTML = '<p>This document could not be loaded. <a href="' + GH + doc.path + '" rel="noopener">Open it on GitHub ↗</a></p>';
      toc.innerHTML = '';
    });
  }

  function buildToc() {
    var hs = $$('h2,h3', art);
    if (spy) spy.disconnect();
    if (hs.length < 2) { toc.innerHTML = ''; return; }
    toc.innerHTML = '<h6>On this page</h6>' + hs.map(function (h) {
      return '<a class="' + h.tagName.toLowerCase() + '" href="#' + current + '/' + h.id + '" data-to="' + h.id + '">' + S.esc(h.textContent) + '</a>';
    }).join('');
    if ('IntersectionObserver' in window) {
      spy = new IntersectionObserver(function (es) {
        es.forEach(function (e) {
          if (!e.isIntersecting) return;
          $$('a', toc).forEach(function (a) { a.classList.toggle('on', a.dataset.to === e.target.id); });
        });
      }, { rootMargin: '-70px 0px -75% 0px' });
      hs.forEach(function (h) { spy.observe(h); });
    }
  }

  function route() {
    var h = decodeURIComponent(location.hash.slice(1)), i = h.indexOf('/');
    var key = i < 0 ? h : h.slice(0, i), anchor = i < 0 ? '' : h.slice(i + 1);
    show(byKey[key] ? key : 'README', anchor);
  }
  window.addEventListener('hashchange', route);
  route();

  /* ---------- full-text search ---------- */
  var box = $('[data-results]'), timer = null;
  function snippet(line, q) {
    var i = line.toLowerCase().indexOf(q), s = Math.max(0, i - 50), t = line.slice(s, i + q.length + 70);
    var j = t.toLowerCase().indexOf(q);
    return (s ? '…' : '') + S.esc(t.slice(0, j)) + '<mark>' + S.esc(t.slice(j, j + q.length)) + '</mark>' + S.esc(t.slice(j + q.length)) + '…';
  }
  function search(q) {
    q = q.trim().toLowerCase();
    if (q.length < 3) { box.hidden = true; box.innerHTML = ''; return; }
    Promise.all(DOCS.map(function (d) { return load(d).then(function (t) { return [d, t]; }, function () { return [d, '']; }); })).then(function (all) {
      var hits = [];
      all.forEach(function (x) {
        var d = x[0], heading = '', n = 0, seenH = {};
        x[1].split('\n').forEach(function (line) {
          var m = line.match(/^#{1,4}\s+(.*)/);
          if (m) { var s = slugify(m[1].replace(/[*`_]/g, '')), id = s, k = 1; while (seenH[id]) id = s + '-' + k++; seenH[id] = 1; heading = id; }
          if (n < 3 && line.toLowerCase().indexOf(q) >= 0) { n++; hits.push({ d: d, h: heading, s: snippet(line.replace(/[*`#>|]/g, ' ').replace(/\s+/g, ' '), q) }); }
        });
      });
      box.hidden = false;
      box.className = 'results';
      box.innerHTML = '<h4>' + hits.length + (hits.length >= 40 ? '+' : '') + ' results for “' + S.esc(q) + '”</h4>' + hits.slice(0, 40).map(function (h) {
        return '<a href="#' + h.d.key + (h.h ? '/' + h.h : '') + '"><b>' + S.esc((byKey[h.d.en] || h.d).title) + (h.d.en ? ' (Deutsch)' : '') + '</b><span>' + h.s + '</span></a>';
      }).join('');
    });
  }
  $('[data-search]').addEventListener('input', function (e) { clearTimeout(timer); var v = e.target.value; timer = setTimeout(function () { search(v); }, 250); });
  box.addEventListener('click', function (e) { if (e.target.closest('a')) { box.hidden = true; $('[data-search]').value = ''; } });
})();
