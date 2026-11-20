# CI Acceptance Contract v2 — report

- contract: `docs/spec/ci_acceptance_contract.md`
- repo: `Archright/Axiom`
- boundary: `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356`
- generated_at: `2026-11-20T06:27:07Z`
- schema: `axiom.ci_acceptance.v3`
- mode: `initial`
- status: **INCOMPLETE**
- window: initial 20 post-boundary entries (observed n=20, shortfall=0, excluded 16 pre-boundary)
- latency (canonical, terminal-attempt job span): n=20, p50=590.5s, mean=609.4s, min=387s, max=941s
- latency (legacy, non-canonical updated_at - run_started_at): n=20, p50=593.5s, mean=612.0s

## Verdict

| field | value |
|---|---|
| mode | initial |
| status | INCOMPLETE |
| accepted | false |
| predicate_holds | false |
| observation_complete | false |
| requested_window | 20 |
| observed_entries | 20 |
| shortfall | 0 |
| unexpected_internal_defects | 0 |
| unclassified | 0 |
| external_dependency_blocked | 7 |
| recovered_degradation (reported, not failed) | 0 |
| legitimate_policy (reported, not failed) | 0 |
| success | 13 |
| cancelled_superseded | 0 |

## Internal defect subtypes

| subtype | count |
|---|---:|
| identity_divergence | 0 |
| soundness_failure | 0 |
| failure_projection | 0 |
| authority_substitution | 0 |

## Entries

| run_id | head_sha | base_sha | PR | conclusion | classification | control_outcome | subtype | detail | wall_s | legacy_s | admission_app_ids | evidence | gap |
|---|---|---|---:|---|---|---|---|---|---:|---:|---|---|---|
| 44519217624 | `2ff9f58a8c9d` | `aa0f78a8d2a6` | 211 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 708 | 710 | 15368,5795152 | `run:44519217624/attempt:1/log:logs/10_attest _ admission-check.txt` | no |
| 44521587339 | `807f38d9fec0` | `aa0f78a8d2a6` | 211 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 763 | 765 | 15368,5795152 | `run:44521587339/attempt:1/log:logs/12_attest _ go-critical-lane (1).txt` | no |
| 44542633420 | `69d2dce090c9` | `aa0f78a8d2a6` | 211 | success | success | accepted | none |  | 430 | 432 | 15368,5795152 | `run:44542633420/attempt:1/conclusion:success` | no |
| 44548437642 | `dd8502f629f7` | `69d2dce090c9` | 212 | success | success | accepted | none |  | 519 | 521 | 15368,5795152 | `run:44548437642/attempt:1/conclusion:success` | no |
| 44553449785 | `a2a863634dd0` | `f943c424e6e0` | 213 | success | success | accepted | none |  | 574 | 578 | 15368,5795152 | `run:44553449785/attempt:1/conclusion:success` | no |
| 44561019095 | `8bbb035a7aca` | `64d0fe2e6230` | 216 | success | success | accepted | none |  | 555 | 556 | 15368,5795152 | `run:44561019095/attempt:1/conclusion:success` | no |
| 44656823351 | `cd7b1deadad1` | `8bbb035a7aca` | 217 | success | success | accepted | none |  | 545 | 547 | 15368,5795152 | `run:44656823351/attempt:1/conclusion:success` | no |
| 44662615542 | `e1a06f5ddc78` | `cd7b1deadad1` | 227 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 387 | 389 | 15368,5795152 | `run:44662615542/attempt:1/log:logs/11_mint-prepare _ prepare.txt` | no |
| 44663622984 | `d49e955895d8` | `cd7b1deadad1` | 227 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 551 | 553 | 15368,5795152 | `run:44663622984/attempt:1/log:logs/10_mint-prepare _ prepare.txt` | no |
| 44665694626 | `4f36457e3675` | `0697e4b1602f` | 231 | success | success | accepted | none |  | 613 | 615 | 15368,5795152 | `run:44665694626/attempt:1/conclusion:success` | no |
| 44667069510 | `abcc12c6f72b` | `4f36457e3675` | 232 | success | success | accepted | none |  | 558 | 562 | 15368,5795152 | `run:44667069510/attempt:1/conclusion:success` | no |
| 44668581737 | `4673ba558b8b` | `abcc12c6f72b` | 227 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 648 | 650 | 15368,5795152 | `run:44668581737/attempt:1/log:logs/11_attest _ admission-check.txt` | no |
| 44669070505 | `aba55ca12b84` | `4673ba558b8b` | 234 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 702 | 704 | 15368,5795152 | `run:44669070505/attempt:1/log:logs/10_attest _ admission-check.txt` | no |
| 44669827441 | `f7d73fd8053f` | `abcc12c6f72b` | 234 | success | success | accepted | none |  | 642 | 644 | 15368,5795152 | `run:44669827441/attempt:1/conclusion:success` | no |
| 44672272126 | `e65efa358341` | `f7d73fd8053f` | 235 | success | success | accepted | none |  | 478 | 482 | 15368,5795152 | `run:44672272126/attempt:1/conclusion:success` | no |
| 44674123967 | `e36677804b5c` | `e65efa358341` | 227 | success | success | accepted | none |  | 448 | 450 | 15368,5795152 | `run:44674123967/attempt:1/conclusion:success` | no |
| 44675885492 | `c8bd3c54ceee` | `cbd87b4a5e01` | 233 | failure | external_dependency | fail_closed | external_supply_unavailable |  | 607 | 609 | 15368,5795152 | `run:44675885492/attempt:1/log:logs/12_attest _ admission-check.txt` | no |
| 44678603060 | `39f0100ed54f` | `f8b35619dc5f` | 242 | success | success | accepted | none |  | 704 | 706 | 15368,5795152 | `run:44678603060/attempt:1/conclusion:success` | no |
| 44680326991 | `0fc1f7fe53cf` | `39f0100ed54f` | 243 | success | success | accepted | none |  | 941 | 948 | 15368,5795152 | `run:44680326991/attempt:1/conclusion:success` | no |
| 44680330023 | `2f0ddbc33979` | `0fc1f7fe53cf` | 244 | success | success | accepted | none |  | 814 | 819 | 15368,5795152 | `run:44680330023/attempt:1/conclusion:success` | no |

## Attempts per entry

- `2ff9f58a8c9d` run 44519217624: 44519217624:1
  - run:44519217624/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `807f38d9fec0` run 44521587339: 44521587339:1
  - run:44521587339/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `69d2dce090c9` run 44542633420: 44542633420:1
  - run:44542633420/attempt:1=success control=accepted
- `dd8502f629f7` run 44548437642: 44548437642:1
  - run:44548437642/attempt:1=success control=accepted
- `a2a863634dd0` run 44553449785: 44553449785:1
  - run:44553449785/attempt:1=success control=accepted
- `8bbb035a7aca` run 44561019095: 44561019095:1
  - run:44561019095/attempt:1=success control=accepted
- `cd7b1deadad1` run 44656823351: 44656823351:1
  - run:44656823351/attempt:1=success control=accepted
- `e1a06f5ddc78` run 44662615542: 44662615542:1
  - run:44662615542/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `d49e955895d8` run 44663622984: 44663622984:1
  - run:44663622984/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `4f36457e3675` run 44665694626: 44665694626:1
  - run:44665694626/attempt:1=success control=accepted
- `abcc12c6f72b` run 44667069510: 44667069510:1
  - run:44667069510/attempt:1=success control=accepted
- `4673ba558b8b` run 44668581737: 44668581737:1
  - run:44668581737/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `aba55ca12b84` run 44669070505: 44669070505:1
  - run:44669070505/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `f7d73fd8053f` run 44669827441: 44669827441:1
  - run:44669827441/attempt:1=success control=accepted
- `e65efa358341` run 44672272126: 44672272126:1
  - run:44672272126/attempt:1=success control=accepted
- `e36677804b5c` run 44674123967: 44674123967:1
  - run:44674123967/attempt:1=success control=accepted
- `c8bd3c54ceee` run 44675885492: 44675885492:1
  - run:44675885492/attempt:1=external_dependency/external_supply_unavailable control=fail_closed
- `39f0100ed54f` run 44678603060: 44678603060:1
  - run:44678603060/attempt:1=success control=accepted
- `0fc1f7fe53cf` run 44680326991: 44680326991:1
  - run:44680326991/attempt:1=success control=accepted
- `2f0ddbc33979` run 44680330023: 44680330023:1
  - run:44680330023/attempt:1=success control=accepted

## Gaps

- run 44687078141/attempt 1: no artifact/log evidence available (artifacts: gh api repos/Archright/Axiom/actions/runs/44687078141/attempts/1/artifacts?per_page=100 exited 1: {; logs: gh api download repos/Archright/Axiom/actions/runs/44687078141/attempts/1/logs exited 1)
