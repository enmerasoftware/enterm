---
title: Audit error handling for swallowed failures
summary: "Find errors that are caught and ignored, logged without context or turned into wrong results, and make each failure visible and handled."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [review, backend, observability]
author: enmerasoftware
title_tr: Hata yönetiminde yutulan hataları denetle
summary_tr: "Yakalanıp yok sayılan, bağlamsız kaydedilen ya da yanlış sonuca dönüşen hataları bulur ve her hatayı görünür ve ele alınmış hale getirir."
---
Audit how this project handles errors and fix the places where failures disappear.

1. Search for the patterns that hide failures in this stack, for example: empty `catch` or `except` blocks, `except Exception: pass`, `catch (e) {}` and `.catch(() => {})`, ignored `err` values in Go, `try?` and `_ =` in Swift and Rust, `unwrap_or_default` on results that matter, promises that are never awaited, error callbacks that only `console.log`, and functions that return `null`, `[]` or `false` for "failed" so callers cannot tell failure from empty.
2. For each hit, read the context and classify it: fine as is (an expected, harmless case, ideally with a comment saying so), should be logged with context, should be returned or re-thrown to the caller, or should be shown to the user. Pay most attention to money, data writes, auth, external calls and background jobs.
3. Fix the ones that matter: propagate errors with context (what was being done, with which ID), keep the original error as the cause, use the project's error types and logging, and show the user a useful message where the UI swallowed the error. Do not change behaviour that callers rely on without listing it.
4. Check the top-level handlers: unhandled rejections or panics, the HTTP error middleware, job runner failure hooks. Make sure unexpected errors are logged once with a stack and that clients get a safe message.
5. Add a test for each fix that forces the failure (a mocked dependency that throws or returns an error) and asserts the error is now surfaced.

Run the test suite. Report a table: location, what happened to the error before, what happens now, test added. List the cases you judged harmless and why.
