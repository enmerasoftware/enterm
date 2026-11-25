---
title: Write a database migration with a rollback
summary: "Write a schema or data migration that runs safely on a live database, with a tested rollback and a plan for existing rows."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [data, backend]
author: enmerasoftware
title_tr: Geri alınabilir bir veritabanı göçü yaz
summary_tr: "Canlı veritabanında güvenle çalışan, geri alma adımı test edilmiş ve mevcut satırlar için planı olan bir şema veya veri göçü yazar."
---
Write a database migration for the change I describe, with a rollback, using the project's migration tool and conventions. If I have not described the change yet, ask for it before you start.

1. Find the migration tool and how migrations are named, generated and run (for example Rails, Django, Alembic, Prisma, Knex, Flyway, golang-migrate, plain SQL files). Read the two most recent migrations and follow their style.
2. Plan it for a live database with real data, and write the plan in the migration's comment header:
   - What existing rows look like and how they are handled (defaults, backfill, nulls, duplicates that would break a new unique constraint).
   - Locking: avoid long table locks. Add columns as nullable first, backfill in batches, then add the constraint; create indexes concurrently where the database supports it.
   - Whether old and new code can run against the schema at the same time during a deploy. If not, split it into expand and contract steps.
3. Write the `up` and the `down`. The rollback must restore the previous schema, and data where that is possible; if a step cannot be undone without losing data, say so in the code and in your report.
4. Update models, types and queries that depend on the change. Add or update tests for the new behaviour.
5. Verify on a local or test database: run up, check the schema, run down, check the schema is back to before, run up again. Do it against a copy with sample data that includes edge cases (nulls, duplicates, large rows). Run the test suite.

Never run a migration against a production or shared database. Report: the files, the plan, the exact commands you ran for up, down and up again with their output, and the risks for the real deploy (time, locks, order relative to the code deploy).
