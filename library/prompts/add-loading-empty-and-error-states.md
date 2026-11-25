---
title: Add loading, empty and error states to a screen
summary: "Make a data-driven screen honest about every state it can be in, with clear copy and a way out of each error, and test each state."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [frontend, mobile, design]
author: enmerasoftware
title_tr: Bir ekrana yükleniyor, boş ve hata durumları ekle
summary_tr: "Veriye dayalı bir ekranın girebileceği her durumu açıkça göstermesini sağlar; her hatadan çıkış yolu sunar ve her durumu test eder."
---
Take one screen in this app that loads data and make it handle every state properly. If I did not name the screen, pick the most used list or dashboard screen and say which.

1. Read how the screen loads data and list the states it can actually be in: first load, refreshing, loaded, empty (no data at all), empty because of a filter or search, partial failure, full failure, offline, unauthorised or expired session, and very large data. Note what the screen shows in each today, including blank screens and endless spinners.
2. Implement each state using the project's existing components and patterns (look for existing skeletons, empty-state and error components first):
   - **Loading**: a skeleton or placeholder that matches the layout; do not block content that is already shown during a refresh.
   - **Empty**: say what would be here and offer the action that fills it; for an empty search or filter, say so and offer to clear it.
   - **Error**: plain words about what failed, no raw error text or codes as the main message, and a retry action. Keep data that already loaded.
   - **Offline and session expiry**: handled the same way the rest of the app does.
3. Copy in sentence case, short, and in the translation system if the project has one.
4. Make the states reachable for testing: add tests (component, UI or snapshot tests, whichever the project uses) that render each state with mocked data or a mocked failed request, and assert on the visible text and the action.

Verify by running the tests, and if you can run the app, force each state (for example block the network or return an empty list) and take a screenshot of each. Report the states before and after, the files changed and the tests added.
