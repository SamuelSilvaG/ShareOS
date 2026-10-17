# Translating the ShareOS web interface

*Kurz auf Deutsch: Neue Sprache = eine JSON-Datei in `src/shareos-core/www/i18n/`
plus ein Eintrag in `languages.json`. Details unten.*

The interface is written in German, the source language. Every other language
is one JSON file that maps the German texts to that language. No code changes
are needed.

## Add a language

1. Copy `src/shareos-core/www/i18n/en.json` to `<code>.json`, using an ISO
   639-1 code: `fr.json`, `es.json`, `nl.json` …
2. Set `"language"` and `"name"` (the name in that language, for example
   `"Français"`).
3. Translate the values. The **keys stay German**, because they are the texts
   as they appear in the code:
   ```json
   "exact": {
     "Speichern": "Enregistrer",
     "Neu starten?": "Redémarrer ?"
   }
   ```
4. Add the language to `i18n/languages.json`:
   ```json
   { "code": "fr", "name": "Français" }
   ```
5. Choose it under **System → Appearance → Language**. The setting applies to
   the whole box, including the login page.

You can try a translation without building the firmware:
```sh
python3 tests/mock-ubus.py        # http://127.0.0.1:8200/  (root / shareos)
```
To test directly on a box, copy the file to `/www/i18n/` and add it to
`/www/i18n/languages.json` there. Both files live in the overlay, so they
survive a reboot.

## The three sections

| Section | Used for | Example |
|---|---|---|
| `exact` | Whole texts | `"Aushängen": "Unmount"` |
| `patterns` | Texts that contain values (sizes, names, versions). A regular expression on the whole text; `$1`, `$2` … insert the captured parts | `["^Kanal (\\S+)$", "Channel $1"]` |
| `words` | Words left over in composed texts, applied in order after the other two | `["\\bläuft\\b", "running", "g"]` |

Order of evaluation: `exact`, then the first matching `pattern` (whose result
also goes through `words`), then `words` alone. Anything that matches nothing
stays German. That makes a missing translation easy to spot, and it never
breaks the page.

## Finding untranslated texts

`tests/mock-ubus.py` together with a browser is the quickest check: click
through all pages, the wizard and the dialogs in your language and look for
German words. Log contents and release notes are shown as they are and are
never translated.

## Numbers and dates

They follow the language automatically (`LOCALES` in `app.js`). For a
language that is not listed there, the language code itself is used as the
locale, which works for most languages.
