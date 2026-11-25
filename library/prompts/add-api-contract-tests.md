---
title: Add contract tests for an HTTP API
summary: "Write tests that pin down each endpoint's status codes, response shapes and error formats, so an accidental breaking change fails the build."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [testing, backend]
author: enmerasoftware
title_tr: Bir HTTP API için sözleşme testleri ekle
summary_tr: "Her uç noktanın durum kodlarını, yanıt yapısını ve hata biçimini sabitleyen testler yazar; yanlışlıkla yapılan kırıcı bir değişiklik derlemeyi düşürür."
---
Add contract tests for this project's HTTP API, so that a change that would break clients fails the test suite.

1. List the endpoints from the router or the OpenAPI spec if there is one. For each, note the method, path, auth requirement, request body, success responses and error responses. If there is an OpenAPI or JSON Schema document, check it against the code and list where they disagree.
2. Use the project's existing test framework and HTTP test helpers (for example `supertest`, the framework's test client, `httptest`). Run the app in-process against a test database with seeded data, not against a deployed server.
3. For each endpoint, test:
   - the success case: status code, content type, and the full shape of the body (field names, types, required versus optional, nullability), using a schema assertion if the project has one or explicit assertions if not;
   - authentication and authorisation: no credentials, wrong user, and the right user;
   - validation errors: status code and the error body format;
   - not found and conflict cases where they exist;
   - pagination, sorting and filtering parameters, including their limits.
4. Assert on what clients depend on, not on incidental details such as generated IDs, timestamps or field order.
5. If the spec and the code disagree, do not silently pick one: write the test for the current behaviour, mark the disagreement in a comment, and list it in your report.

Run the full suite and make sure the new tests pass. Then prove they guard the contract: rename one response field temporarily, run the tests, see them fail, and restore it. Report endpoints covered, tests added, spec mismatches, and endpoints you could not cover with the reason.
