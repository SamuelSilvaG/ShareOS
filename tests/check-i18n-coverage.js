#!/usr/bin/env node
// Finds German texts of the web interface that have no translation in
// i18n/en.json (exact, pattern or words). The interface is written in German;
// every visible text needs an entry, otherwise it stays German in all other
// languages.
//
//   node tests/check-i18n-coverage.js [--list]     exit 1 when texts are missing
//
// Candidates: text between tags in html`` templates and string literals that
// look German (umlauts, common German words). ${…} counts as a value "X".
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'src/shareos-core/www');
const src = fs.readFileSync(path.join(ROOT, 'app.js'), 'utf8');
const en = JSON.parse(fs.readFileSync(path.join(ROOT, 'i18n/en.json'), 'utf8'));
const exact = en.exact, patterns = en.patterns.map(([r, x]) => [new RegExp(r), x]), words = en.words.map(([r, x, f]) => [new RegExp(r, f || ''), x]);

const GERMAN = /[äöüÄÖÜß]|\b(der|die|das|und|nicht|mit|für|ist|ein|eine|einen|einem|wird|werden|wurde|auf|von|zu|zum|zur|den|dem|des|bei|aus|noch|nur|oder|wenn|kein|keine|keinen|sich|auch|schon|dann|bitte|jetzt|hier|wie|über|unter|nach|vor|bis|als|im|am|vom|beim|ins|ohne|alle|neu|Neu|gilt|leer|läuft|Datei|Dateien|Ordner|Freigabe|Freigaben|Benutzer|Gruppe|Gruppen|Gerät|Laufwerk|Laufwerke|Platte|Platten|Einstellungen|Speichern|Abbrechen|Löschen|Öffnen|Hinzufügen|Übernehmen|Zurück|Weiter|Passwort|Anmelden|Fehler|gespeichert|gelöscht|Name|Konto|Auftrag|Aufträge|Zeitplan|Sprache|Netzwerk|Adresse|Neustart|Hochladen|Herunterladen|Einspielen|Prüfen|Suchen|Schließen|Aktualisieren|Installieren|Entfernen|Umbenennen|Kopieren|Verschieben|Lade|nie|immer|täglich|stündlich|Minuten|Stunden|Sekunden|Tage)\b|\b[A-ZÄÖÜ]{3,}( [A-ZÄÖÜ&/()-]{2,})*\b/;
const isGerman = (t) => GERMAN.test(t) && /[a-zäöüß]{2}|[A-ZÄÖÜ]{3}/.test(t);

function words_(t) { let r = t; for (const [re, x] of words) r = r.replace(re, x); return r; }
function translate(t) {
  if (exact[t] != null) return exact[t];
  for (const [re, x] of patterns) if (re.test(t)) return words_(t.replace(re, x));
  return words_(t);
}
// English-only text after translation (ignores values and proper names)
const STILL = /[äöüÄÖÜß]|\b(der|die|das|und|nicht|mit|für|ist|ein|eine|wird|auf|von|zu|den|dem|bei|aus|noch|nur|oder|wenn|kein|keine|sich|auch|dann|bitte|jetzt|hier|alle|Datei|Ordner|Freigabe|Benutzer|Gerät|Laufwerk|Platte|Einstellungen|Speichern|Abbrechen|Löschen|Passwort|Fehler|Konto|Auftrag|Zeitplan|Sprache|Adresse|Neustart|Lade)\b/;

const cands = new Map();
const add = (t, line) => {
  // ${svg(…)} and similar are elements, not text: an X glued to a word is one
  t = t.replace(/\s+/g, ' ').trim().replace(/^X(?=[A-ZÄÖÜ])/, '').replace(/([.!?:)…])X$/, '$1').trim();
  if (/^[:'"]|['"];|\}\)|=>/.test(t)) return;     // code, not text
  if (t.length < 2 || !isGerman(t)) return;
  if (/^[\s\W\d]*$/.test(t) || /^(https?:|\/|#|\.[a-z0-9]|[a-z_]+\(|[a-z-]+=)/.test(t)) return;
  if (!cands.has(t)) cands.set(t, line);
};
const lineOf = (i) => src.slice(0, i).split('\n').length;
// 1. template literals: text between tags, ${} -> X
const tpl = /`((?:\\.|\$\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}|[^`\\])*)`/g;
let m;
// templates nested in ${…} of other templates are scanned as well
const bodies = [];
(function scan(text, base) {
  const re = new RegExp(tpl.source, 'g');
  let x;
  while ((x = re.exec(text))) {
    bodies.push([x[1], base + x.index]);
    for (const e of x[1].matchAll(/\$\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}/g)) if (e[1].includes('`')) scan(e[1], base + x.index + 1 + e.index + 2);
  }
})(src, 0);
for (const [body, at] of bodies) {
  m = { 1: body, index: at };
  // nested templates inside ${} are found by the outer loop too (they are separate matches only at top level), so also scan them
  const flat = body.replace(/\$\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/g, 'X');
  if (!/[<>]/.test(flat)) { add(flat, lineOf(m.index)); continue; }
  for (const part of flat.split(/<[^>]*>/)) add(part, lineOf(m.index));
  // attributes
  for (const a of flat.matchAll(/(placeholder|title|aria-label|alt)="([^"]+)"/g)) add(a[2], lineOf(m.index));
}
// 2. quoted strings
const str = /'((?:\\.|[^'\\\n])*)'|"((?:\\.|[^"\\\n])*)"/g;
while ((m = str.exec(src))) {
  const t = (m[1] ?? m[2]).replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\\n/g, ' ');
  if (/[<>]/.test(t) || /^[a-z0-9_.:\/-]*$/.test(t)) continue;
  add(t, lineOf(m.index));
}
// pieces that only exist as part of a longer text at runtime (checked by hand
// in the browser, see tests/i18n-crawl.js)
const PIECES = new Set(JSON.parse(fs.readFileSync(path.join(__dirname, 'i18n-pieces.json'), 'utf8')));
// values for X: a number, a size, a name; a trailing ":" is a prefix of an error message
const variants = (t) => {
  const v = [];
  for (const x of ['5', '1.2 MB', 'fotos']) {
    const s = t.replace(/\bX\b/g, x);
    v.push(/:$/.test(s) ? [s, s + ' not allowed'] : [s]);
  }
  return v;
};
const missing = [];
for (const [t, line] of cands) {
  if (PIECES.has(t)) continue;
  let best = null;
  const vs = variants(t);
  const ok = vs.some((alts) => alts.some((a) => !STILL.test(translate(a).replace(/fotos/g, ''))));
  if (!ok) best = translate(vs[0][0]);
  if (best !== null) missing.push([line, t, best]);
}
missing.sort((a, b) => a[0] - b[0]);
if (process.argv.includes('--list')) for (const [l, t] of missing) console.log(l + '\t' + t);
else for (const [l, t, r] of missing) console.log(`app.js:${l}: ${t}${r !== t ? '  →  ' + r : ''}`);
console.error(`${missing.length} German texts without translation (of ${cands.size} candidates)`);
process.exit(missing.length ? 1 : 0);
