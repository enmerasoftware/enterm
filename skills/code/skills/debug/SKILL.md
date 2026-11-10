---
name: debug
description: Find the cause of a bug before changing code: reproduce, narrow down, prove, then fix. Use when something fails, crashes, gives a wrong result or a test is red.
---

# Debug

1. Reproduce first. Get the exact command, input and error text. If you cannot reproduce it, say so and ask for what is missing instead of guessing.
2. Read the error and the stack trace from the top of the project's own code, not the library frames.
3. Form one hypothesis at a time and test it with the cheapest check: a log line, a print, a small script, `git bisect` when it used to work.
4. When a check disproves the idea, drop it. Do not stack fixes for causes you have not proven.
5. Fix the cause, not the symptom. Add a test that fails without the fix when the project has tests.
6. Report: cause in one sentence, the proof, the fix, and how you verified it.
