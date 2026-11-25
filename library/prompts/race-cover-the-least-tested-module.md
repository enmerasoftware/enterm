---
title: Cover the least-tested module with real tests
summary: "Race to raise test coverage of the least-tested important module with tests that fail when the code is broken."
kind: race
programs: [claude, codex, gemini]
tags: [testing]
author: enmerasoftware
title_tr: En az test edilen modülü gerçek testlerle kapsa
summary_tr: "En az test edilen önemli modülün kapsamını, kod bozulduğunda gerçekten kalan testlerle artırma yarışı."
---
Raise the test coverage of the least-tested important module in this repository, with tests that would catch real regressions.

1. Run the test suite with coverage using the project's tool. If coverage is not set up, set it up with the standard tool for the stack, as a dev dependency or a flag, not as a required part of the default test command.
2. Pick the module (a source file or a small package) with the lowest coverage among those that matter: business logic, parsing, money, permissions or data writes. Skip generated code, UI glue and trivial getters. Say which module you picked and its coverage.
3. Write tests in the project's existing style and location. Every test must call real code and assert exact results or side effects; "does not throw" and "is defined" do not count. Cover error branches and boundary values, not only the happy path.
4. Prove your tests have teeth: for at least five of them, break the line they cover (flip a condition, change a constant), run them, see them fail, and restore the code.
5. Do not change production code. If you find a bug, write the test that shows it, mark it as an expected failure with the reason, and mention it.

Finish with the full suite passing. In your final message, give the module, coverage before and after (lines and branches), the tests you added, the mutation checks and their results, and any bugs found. Then commit your work as the instructions below say.
