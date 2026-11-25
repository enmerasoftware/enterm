---
title: Move hardcoded UI text into translation keys
summary: "Find user-facing strings written directly in the UI code, move them into the project's translation files with good keys, and check nothing is left."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [i18n, frontend, mobile]
author: enmerasoftware
title_tr: Koda gömülü arayüz metinlerini çeviri anahtarlarına taşı
summary_tr: "Arayüz kodunda doğrudan yazılmış kullanıcı metinlerini bulur, iyi adlandırılmış anahtarlarla çeviri dosyalarına taşır ve geride bir şey kalmadığını kontrol eder."
---
Move the hardcoded user-facing text in this app into the project's translation system.

1. Find the i18n setup (for example `i18next`, `react-intl`, `vue-i18n`, Rails I18n, gettext, `Localizable.strings` or String Catalogs on Apple platforms, `strings.xml` on Android, ARB files in Flutter). If there is none, stop and propose one that fits the stack before writing anything.
2. Find hardcoded strings shown to users: text in components and views, button and menu labels, placeholders, `alt` and accessibility labels, validation and error messages, toasts, email templates, page titles. Skip log messages, test data, CSS classes and identifiers.
3. Move each one to a key that follows the existing naming convention; if there is none, use `screen.element.purpose` (for example `checkout.payButton.label`). Reuse an existing key only when the meaning is the same, not just the words.
4. Do it properly:
   - Use the library's interpolation for values; never build sentences by joining fragments, because word order changes between languages.
   - Use plural rules for counts, not `count === 1 ? ... : ...`.
   - Format dates, numbers and money with the locale's formatter.
   - Add a short note for translators where the meaning is ambiguous (for example "Open" as a verb or as a status).
5. Add the keys to the source-language file. For other existing languages, add the keys and mark them as untranslated in the way the project does; do not machine-translate unless I ask.

Verify: build and run the tests; run the app and check the changed screens still show the same text; search again for hardcoded strings in the files you touched and show the search comes back clean. If the project has a missing-key check or a pseudo-locale, run it. Report the number of strings moved per screen and the ones you deliberately left.
