---
title: Harden input validation at the edges
summary: "Find every place outside input enters the system, validate it at that boundary with clear errors, and add tests for hostile inputs."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [security, backend]
author: enmerasoftware
title_tr: Sınırlarda girdi doğrulamasını sıkılaştır
summary_tr: "Dışarıdan gelen girdinin sisteme girdiği her yeri bulur, o sınırda açık hata mesajlarıyla doğrular ve kötü niyetli girdiler için test ekler."
---
Harden how this project validates input that comes from outside: HTTP requests, CLI arguments, files, environment variables, queue messages and webhooks.

1. Inventory the entry points. List each one with the file, the fields it accepts, and what validation exists today. Note where a value travels unchecked into a database query, a shell command, a file path, a template, a redirect URL, a regex or an allocation size.
2. Find the project's validation approach (a schema library, framework validators, hand-written checks) and use it. Do not introduce a new library if one is already in use.
3. At each boundary, validate type, required fields, length and size limits, numeric ranges, allowed values, formats (email, URL, ID), and reject unknown fields where that is safe. Normalise before checking (trim, Unicode normalisation) where the project expects it. Validation belongs at the edge; inner code should be able to trust its inputs.
4. Errors must be clear to the caller (which field, what was wrong), must use the project's existing error format and status codes, and must not echo secrets or stack traces.
5. For each boundary you change, add tests with hostile inputs: missing and extra fields, wrong types, empty strings, very long strings, negative and huge numbers, path traversal (`../`), SQL and shell metacharacters, Unicode lookalikes, and null bytes. Each test asserts the exact rejection.
6. Be careful not to break valid clients: if a new limit could reject data that real users send today, say so and pick a generous limit, or ask.

Run the full suite at the end. Report a table: entry point, what was unchecked, what is validated now, tests added. List risky sinks you found but did not fix.
