---
title: Accessibility pass on a screen
summary: "Check one screen for keyboard use, screen reader names, focus, contrast and text size, fix what fails, and verify each fix."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [accessibility, frontend, mobile]
author: enmerasoftware
title_tr: Bir ekranda erişilebilirlik geçişi
summary_tr: "Bir ekranı klavye kullanımı, ekran okuyucu adları, odak, kontrast ve yazı boyutu açısından kontrol eder, sorunları düzeltir ve her düzeltmeyi doğrular."
---
Do an accessibility pass on one screen of this app and fix what fails. If I did not name the screen, pick the most used one (the main page, the sign-in, or the primary list) and say which.

Check, against WCAG 2.2 AA for web or the platform's guidelines for iOS and Android:
1. **Names and roles**: every control has an accessible name (icon-only buttons included), images have alt text or are marked decorative, form fields have labels tied to them, headings form a real outline, landmarks exist.
2. **Keyboard and focus**: every action works with the keyboard alone, tab order follows the visual order, focus is always visible, dialogs trap and then return focus, nothing is reachable only on hover.
3. **Contrast and size**: text and meaningful icons meet contrast ratios (4.5:1 for body text, 3:1 for large text and UI parts), touch targets are at least 24 px on web and 44 pt on iOS, and the screen works at 200% zoom or the largest Dynamic Type size without clipping.
4. **State and change**: errors are announced and linked to their field, loading and empty states are announced, colour is never the only signal, motion respects reduced-motion settings.

How to work:
- Use the tools the project has; on web run axe (`npx @axe-core/cli <url>`) or Lighthouse's accessibility audit if available; on iOS use Accessibility Inspector, on Android the Accessibility Scanner or `adb shell uiautomator dump`. Automated tools find about a third of problems, so also read the code and walk through it by keyboard or screen reader logic.
- Fix in shared components when the problem is in a component, so every screen benefits. Keep the visual design unless a fix needs it to change (for example contrast).
- Add tests where the project has a way to (for example `jest-axe`, Testing Library queries by role, UI tests that query by accessibility label).

Report a table: issue, where, rule, fix, how verified. Include the automated tool's result before and after, and list issues you found but left because they need a design decision.
