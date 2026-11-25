---
title: "Kata: a correct CSV parser in JavaScript"
summary: "Race to write an RFC 4180 CSV parser and writer that handles quotes, newlines in fields and clear errors, verified by a fixed acceptance test."
kind: race
test: node --test kata/csv/*.test.mjs
programs: [claude, codex, gemini]
tags: [data, testing]
author: enmerasoftware
title_tr: "Kata: JavaScript ile doğru bir CSV ayrıştırıcı"
summary_tr: "Tırnakları, alan içindeki satır sonlarını ve anlaşılır hataları ele alan, sabit bir kabul testiyle doğrulanan RFC 4180 CSV ayrıştırıcı ve yazıcı yarışı."
---
Write a CSV parser and writer as a standalone JavaScript module. This task is self-contained: it works in any git repository, an empty one included, and needs only Node.js 20 or later.

Create `kata/csv/csv.mjs` exporting two functions, with no dependencies:

- `parseCSV(text, { delimiter = ",", header = false } = {})` follows RFC 4180:
  - Rows end with `\n`, `\r\n` or a lone `\r`. A final line ending does not create an extra row; an empty string gives `[]`. An empty line in the middle is a row with one empty field.
  - Fields may be quoted with `"`. Inside quotes, `""` is a literal quote, and delimiters and line endings are data.
  - Whitespace is kept as data. A leading byte order mark is dropped.
  - Errors are `SyntaxError`s whose message names the line number (1-based, counting physical lines): an unterminated quote names the line where the quoted field started; a quote inside an unquoted field and characters after a closing quote are errors too.
  - Without `header`, return an array of arrays of strings. With `header: true`, use the first row as keys and return an array of objects; a row with a different number of fields is a `SyntaxError` that names its line.
  - It must run in linear time: no re-scanning, no quadratic string building.
- `stringifyCSV(rows, { delimiter = "," } = {})` writes rows of values, ending every row with `\r\n`. `null` and `undefined` become empty fields; other values go through `String`. Quote a field only when it contains the delimiter, a quote, `\r` or `\n`, doubling the quotes inside.

Create `kata/csv/acceptance.test.mjs` with exactly the content below and do not change it. You may add more tests in other files in the same folder, for example `kata/csv/extra.test.mjs`.

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseCSV, stringifyCSV } from "./csv.mjs";

test("plain rows", () => {
  assert.deepEqual(parseCSV("a,b,c\n1,2,3"), [["a", "b", "c"], ["1", "2", "3"]]);
});

test("a trailing newline does not add a row; an empty input has no rows", () => {
  assert.deepEqual(parseCSV("a,b\n1,2\n"), [["a", "b"], ["1", "2"]]);
  assert.deepEqual(parseCSV(""), []);
});

test("CRLF and lone CR line endings", () => {
  assert.deepEqual(parseCSV("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]]);
  assert.deepEqual(parseCSV("a,b\r1,2"), [["a", "b"], ["1", "2"]]);
});

test("empty fields are kept", () => {
  assert.deepEqual(parseCSV(",a,,\n"), [["", "a", "", ""]]);
  assert.deepEqual(parseCSV("a\n\nb"), [["a"], [""], ["b"]]);
});

test("quoted fields with delimiters, doubled quotes and newlines", () => {
  const text = 'name,quote\n"Smith, J.","He said ""hi"""\n"multi\nline",x\n';
  assert.deepEqual(parseCSV(text), [
    ["name", "quote"],
    ["Smith, J.", 'He said "hi"'],
    ["multi\nline", "x"],
  ]);
});

test("whitespace is data, not trimmed", () => {
  assert.deepEqual(parseCSV(" a , b "), [[" a ", " b "]]);
});

test("custom delimiter", () => {
  assert.deepEqual(parseCSV('a;"b;c"\n1;2', { delimiter: ";" }), [["a", "b;c"], ["1", "2"]]);
  assert.deepEqual(parseCSV("a\tb", { delimiter: "\t" }), [["a", "b"]]);
});

test("header mode returns objects", () => {
  assert.deepEqual(parseCSV("id,name\n1,Ada\n2,Linus\n", { header: true }), [
    { id: "1", name: "Ada" },
    { id: "2", name: "Linus" },
  ]);
});

test("header mode rejects rows with the wrong number of fields", () => {
  assert.throws(() => parseCSV("id,name\n1\n", { header: true }), (err) => err instanceof SyntaxError && /line 2/.test(err.message));
});

test("an unterminated quote is a SyntaxError that names the line it started on", () => {
  assert.throws(() => parseCSV('a,b\n1,"oops\n2,3\n'), (err) => err instanceof SyntaxError && /line 2/.test(err.message));
});

test("a quote in the middle of an unquoted field is a SyntaxError", () => {
  assert.throws(() => parseCSV('a,b"c\n'), SyntaxError);
});

test("characters after a closing quote are a SyntaxError", () => {
  assert.throws(() => parseCSV('"a"b,c\n'), SyntaxError);
});

test("unicode is preserved", () => {
  assert.deepEqual(parseCSV("şehir,emoji\nİstanbul,🚀"), [["şehir", "emoji"], ["İstanbul", "🚀"]]);
});

test("a byte order mark at the start is dropped", () => {
  assert.deepEqual(parseCSV("﻿a,b"), [["a", "b"]]);
});

test("stringify quotes only when needed and ends every row with CRLF", () => {
  assert.equal(stringifyCSV([["a", "b,c"], ['say "hi"', "line\nbreak"], ["", "plain"]]), 'a,"b,c"\r\n"say ""hi""","line\nbreak"\r\n,plain\r\n');
});

test("stringify accepts numbers, booleans and null", () => {
  assert.equal(stringifyCSV([[1, true, null, undefined, 2.5]]), "1,true,,,2.5\r\n");
});

test("round trip", () => {
  const rows = [["id", "note"], ["1", 'a "quoted", multi\r\nline value'], ["2", ""], ["3", " spaced "]];
  assert.deepEqual(parseCSV(stringifyCSV(rows)), rows);
  assert.deepEqual(parseCSV(stringifyCSV(rows, { delimiter: ";" }), { delimiter: ";" }), rows);
});

test("parses a large file in linear time", () => {
  const line = '1,"two, with comma",three,"four ""quoted"""\n';
  const text = line.repeat(100_000);
  const start = performance.now();
  const rows = parseCSV(text);
  assert.equal(rows.length, 100_000);
  assert.deepEqual(rows[99_999], ["1", "two, with comma", "three", 'four "quoted"']);
  assert.ok(performance.now() - start < 3000, "100k rows should parse well under 3 seconds");
});
```

Done means `node --test kata/csv/*.test.mjs` passes. Run it, and include the output summary in your final message together with any edge case you handled beyond the tests. Then commit your work as the instructions below say.
