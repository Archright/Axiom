# jq 1.7 IN($array) membership trap (single-array argument is not a membership test)

Status: documented 2026-11-03 (discovered during the node24 merge-queue
critical-path census sweep — `docs/evidence/node24_merge_queue_critical_path_census_2026-11-03.md`
§10; cost: one silently-empty intermediate result in a run-classification
filter, caught by the sweep's completeness reconciliation).

## 1. Symptom

A filter intended to test array membership returned `false` for a value
that IS an element of the array:

    $ jq -n --argjson arr '["a","b"]' '"b" | IN($arr)'
    false

The same trap with a literal array:

    $ jq -n '"b" | IN(["a","b"])'
    false

Scalar enumeration works, which makes the failure look like an array-form
bug:

    $ jq -n '"b" | IN("a","b")'
    true

## 2. Root Cause

This is **documented semantics, not a jq bug** — jq manual (jqlang.org,
SQL-style operators): `IN(s)` "outputs `true` if `.` appears in the given
**stream**, otherwise it outputs `false`". The argument `s` is a
stream/generator of candidate values, not an array to search.

When a single array `$arr` is passed, that array **itself** becomes the one
and only element of the candidate stream, so the filter degenerates to
`$arr == .` — comparing the input against the whole array. Any scalar input
yields `false` regardless of membership. No error or warning is emitted.
(`in()` is a different operator — object keys / string indices only.)

## 3. Correct patterns

Verified on jq 1.7:

    $ jq -n --argjson arr '["a","b"]' '"b" | IN($arr[])'   # spread array as stream
    true
    $ jq -n --argjson arr '[]' '"b" | IN($arr[])'           # empty array → false
    false
    $ jq -n --argjson arr '["a",null,"b"]' 'null | IN($arr[])'
    true

- Array membership: `x | IN($arr[])` (note the `[]` spread) or
  `($arr | index($x)) != null` — the census sweep used the `index()` form.
- Scalar candidates: `x | IN("a","b")`.
- Object key membership: `in($obj)`.

## 4. Why it matters here

GET-only observation sweeps classify API listings with jq before counting
completeness (e.g. "every merge_group run is classified"). A filter like
`.name | IN($required)` silently classifies **nothing** instead of erroring
— the failure mode is an empty or all-false result, which a downstream
count may then read as "zero observations" rather than "broken filter".
Guard: when a jq predicate is expected to produce at least one `true`, a
zero-true result must be treated as a filter defect, not as an empty
population (fail-closed on observation completeness).
