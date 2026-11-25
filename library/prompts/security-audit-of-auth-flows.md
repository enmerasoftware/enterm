---
title: Security audit of the authentication flows
summary: "Trace sign-up, sign-in, sessions, password reset and authorisation checks, and report exploitable weaknesses with proof and a fix."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [security, review, backend]
author: enmerasoftware
title_tr: Kimlik doğrulama akışlarının güvenlik denetimi
summary_tr: "Kayıt, giriş, oturum, parola sıfırlama ve yetki kontrollerini izler; istismar edilebilir zayıflıkları kanıt ve düzeltmeyle raporlar."
---
Audit the authentication and authorisation code in this project. Report first; change code only for findings I approve afterwards.

Trace each flow in the code, end to end, and check:
1. **Sign-up and sign-in**: password hashing (a slow algorithm such as argon2, bcrypt or scrypt, with a proper cost), constant-time comparison, rate limiting and lockout, user enumeration through different errors or timings, MFA handling if present.
2. **Sessions and tokens**: how they are created, stored and expired; cookie flags (`HttpOnly`, `Secure`, `SameSite`); JWT algorithm pinning, signature verification, expiry and audience checks; rotation on sign-in and privilege change; revocation on sign-out and password change.
3. **Password reset and email change**: token randomness, single use, short expiry, binding to the user, no token in logs or the `Referer`, and no account takeover through a changed email.
4. **Authorisation**: every route or handler that reads or writes data checks that the caller may access that specific record (no IDs trusted from the request without an ownership check), admin routes are protected server-side, and defaults deny.
5. **OAuth or SSO** if present: `state` and PKCE, redirect URI validation, account linking by verified email only.
6. **Surrounding protections**: CSRF for cookie-based sessions, CORS that does not reflect arbitrary origins with credentials, secrets loaded from the environment, not the repository.

For each finding give: `file:line`, the attack in one or two sentences, severity (critical, high, medium, low), how sure you are, and the fix. Where you can, prove it with a test or a request against a local instance; never against a deployed system. Mark guesses as guesses.

Finish with a list of routes or handlers that have no authorisation check at all, and a short summary of what is done well.
