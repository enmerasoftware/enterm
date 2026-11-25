---
title: Find and fix N+1 database queries
summary: "Count the queries each main endpoint makes, find loops that query once per row, batch them, and prove the counts dropped."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [performance, data, backend]
author: enmerasoftware
title_tr: N+1 veritabanı sorgularını bul ve düzelt
summary_tr: "Her ana uç noktanın kaç sorgu yaptığını sayar, satır başına sorgu atan döngüleri bulur, toplu hale getirir ve sayıların düştüğünü kanıtlar."
---
Find and fix N+1 query problems in this application.

1. Turn on query logging or counting for the test or development environment (for example Django's `assertNumQueries` or `django-debug-toolbar`, Rails' `bullet` or the log, Prisma or Sequelize query events, SQLAlchemy echo, an ORM hook). Do not change production configuration.
2. List the endpoints, pages or jobs that load lists of records. For each, make a request with realistic data (at least 20 parent rows with children) and record the number of queries and the time.
3. Look for queries inside loops, lazy-loaded relations accessed per item in templates or serializers, and per-item calls to a helper that queries. Confirm each one in the query log.
4. Fix each with the ORM's eager loading (`select_related`/`prefetch_related`, `includes`, `include`, `joinedload`/`selectinload`), a single batched query with `IN`, or a data loader. Load only the columns and relations that are used. Add an index if the new query needs one, as a migration.
5. Lock the fix in: add a test that asserts the query count for the endpoint does not grow with the number of rows (for example the same count for 2 and for 20 parents).
6. Run the full test suite.

Report a table: endpoint, queries before and after, time before and after, and the change. Mention queries that are slow for other reasons (missing index, large scans) and that you did not change.
