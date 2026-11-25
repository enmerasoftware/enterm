---
title: Add structured logging to a service
summary: "Replace ad hoc print and log calls on the main paths with structured, levelled logs that carry a request ID and never leak secrets."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [observability, backend]
author: enmerasoftware
title_tr: Bir servise yapılandırılmış günlük ekle
summary_tr: "Ana yollardaki rastgele print ve log çağrılarını, istek kimliği taşıyan, seviyeli ve sır sızdırmayan yapılandırılmış kayıtlarla değiştirir."
---
Add structured logging to this service so that a failed request can be traced from its log lines alone.

1. Survey what exists: the logging library and config, how logs are written today (print statements, string-formatted lines), where logs go in production if you can tell (stdout, a file, a collector). Prefer the library already in use, or the standard one for the stack (for example `pino`, `structlog`, `slog`, `tracing`, `os.Logger`, `zap`). Ask before adding a new dependency if there is a reasonable built-in option.
2. Set up one logger configured in one place: JSON output in production, readable output in development, level from an environment variable, and a timestamp, level, message and service name on every line.
3. Add a request or job ID: take it from an incoming header (for example `X-Request-ID` or the trace context) or create one, attach it to every log line for that request through the framework's context mechanism, and return it in the response header.
4. Log at the boundaries, with fields instead of interpolated strings: request start and end (method, route template, status, duration), outgoing calls (target, duration, status), job start, end and failure, and every caught error with its type and stack at `error` level. Use `debug` for detail, `info` for business events, `warn` for recoverable trouble.
5. Never log secrets or personal data: add redaction for fields such as `password`, `token`, `authorization`, `cookie`, `secret`, `apiKey`, card numbers and email addresses where the project treats them as personal. Write a test that proves a password in a request body does not appear in the output.
6. Replace the old print and log calls on the paths you touched; leave the rest and list them.

Verify by running the service, making a successful request and a failing one, and showing the log lines they produce. Run the test suite. Report the setup, the fields, the redaction rules and the sample output.
