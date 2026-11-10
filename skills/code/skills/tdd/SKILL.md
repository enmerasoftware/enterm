---
name: tdd
description: Work test-first: write a failing test, make it pass with the smallest change, then clean up. Use when adding a feature or fixing a bug in a codebase that has tests.
---

# Test first

1. Find how this project runs tests (README, package scripts, Makefile, CI config). Run the suite once and note what already fails, so you do not blame yourself for it.
2. Write one test that describes the behaviour the user wants. Run it and see it fail for the right reason. A test that passes before the change proves nothing.
3. Make the smallest change that turns it green. No extra features.
4. Run the whole suite. Fix anything you broke.
5. Clean up names and duplication with the tests green. Run again.
6. Report: the test you added, what changed, and the suite result with numbers. If something could not be tested, say exactly what and why.
