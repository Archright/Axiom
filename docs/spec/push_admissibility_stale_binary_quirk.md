# Push-Admissibility Stale-Binary Quirk (레시피 직접 호출 × prerequisite 미선언)

> AGENTS.md §0.5 Quirk Mandate — 2026-11-02 실측(Q9 문서 슬라이스, PR #1216
> pre-push dry-run). 측정·운영 기록이며 코드·레지스트리 변경을 수반하지 않는다.

## Symptom

pre-push dry-run(`git push --dry-run`)에서 epoch transaction gate가
`manifest implementedSlices unknown slice id: SL-19` +
`catalog↔manifest implemented mismatch` + `manifest↔engine firing mismatch`
3건으로 **fail-closed**한다. 그런데 `config/policy/epoch_manifest.json`·
`src/gate/slice_catalog.nim`·엔진 파일은 전부 일관(SL-19이 양쪽에 존재)하고
diff는 docs-only다 — repo에는 불일치가 없다.

## Root cause

`make push-admissibility`의 레시피가 `bin/epoch_transaction_gate --diff … HEAD`를
**prerequisite 선언 없이 직접 호출**한다(타깃 선언부의 prerequisite은
`bin/effect_contract_projection bin/nimtry`뿐). `bin/epoch_transaction_gate`는
미추적 로컬 빌드 산출물이고, Makefile 규칙
(`bin/epoch_transaction_gate: tools/ci/epoch_transaction_gate.nim src/gate/slice_catalog.nim`)이
존재하지만 레시피 직접 호출 경로에서는 평가되지 않는다. 결과: 디스크의 스테일
바이너리(본 실측: 2026-11-02 03:22 빌드, SL-19 catalog 항목 추가는 09:58 커밋)가
재빌드 없이 판정에 사용되고, 임베디드 `SliceCatalog`에 없는 SL-19을
"unknown slice id"로 위양(誤判)한다.

## Measured evidence (2026-11-02)

- dry-run 1회차: epoch gate EXIT 1 — 위 3건 위양(MODE `--diff 9381cb3a5… HEAD`,
  "no epoch binding target changed" NOTE 포함 — 즉 diff 자체는 무죄).
- `make bin/epoch_transaction_gate` 재빌드(03:22 → 18:07 빌드) 후 동일 dry-run:
  `check-epoch-transaction` green 포함 13 게이트 전부 PASS, 실제 push 1회 성공.
- `git ls-files bin/ | grep -c epoch` → 0(미추적 확인).

## Sanctioned workaround (운영 규범)

1. pre-push dry-run에서 epoch gate가 "unknown slice id"를 보고하면 **repo 결함으로
   성급히 결론짓지 않는다** — 먼저 `ls -la bin/epoch_transaction_gate`의 mtime을
   최신 catalog/manifest 커밋과 비교한다.
2. 스테일이 확인되면 `make bin/epoch_transaction_gate`로 재빌드 후 dry-run을
   **같은 HEAD에서** 재실행한다(바이너리만 바뀌었으므로 커밋 증분 불필요).
3. 정착 방향(별도 계획 필요 — 이 문서는 회피만 기록): push-admissibility가 해당
   바이너리를 prerequisite로 선언하는 것은 Makefile 실행 경계 변경(§2.5)이므로
   본 슬라이스에서 수정하지 않는다. ④ 게이트 최적화 트랙의 과제다.

## Official documentation basis / UNKNOWN

- make의 prerequisite 미선언 시 레시피 내 직접 호출이 스테일 산출물을 쓰는 것은
  make의 문서화된 의미론 그 자체(GNU make 매뉴얼 — 레시피는 선언된 prerequisite의
  갱신만 보장받는다)이며, 이를 "버그"가 아닌 **호출 계약의 공백**으로 기록한다.
