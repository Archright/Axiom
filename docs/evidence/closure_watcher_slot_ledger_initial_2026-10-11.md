# closure-watcher slot ledger — 2026-10-09T21:20:31Z .. 2026-10-11T09:21:18Z

| metric | value |
|---|---|
| expected_slots | 6 |
| observed_slots | 4 |
| on_time | 1 |
| late | 3 |
| missed | 1 |
| pending | 1 |
| cancelled | 0 |
| hollow | 0 |
| runs_cancelled | 0 |
| skipped_jobs_in_green_runs | 0 |
| unattributed_runs | 0 |

| slot (UTC) | state | run | started (UTC) | delay (min) | conclusion |
|---|---|---|---|---|---|
| 2026-10-10T00:17:00Z | late | 38028948066 | 2026-10-10T05:51:50Z | 334.8 | success |
| 2026-10-10T06:17:00Z | missed | - | - | - | - |
| 2026-10-10T12:17:00Z | on_time | 38052214094 | 2026-10-10T12:30:34Z | 13.6 | failure |
| 2026-10-10T18:17:00Z | late | 38088676610 | 2026-10-10T21:42:55Z | 205.9 | success |
| 2026-10-11T00:17:00Z | late | 38115808935 | 2026-10-11T05:45:18Z | 328.3 | success |
| 2026-10-11T06:17:00Z | pending | - | - | - | - |

NOTE: rule of three: 0-miss claim at 95% confidence requires N >= 60 slots (15 days at 4 slots/day); below that this ledger is a window-in-progress, not a proof
