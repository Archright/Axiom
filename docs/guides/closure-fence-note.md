# 클로저 펜스 안내 (Closure Fence Note)

> 이 문서는 **C1 픽스처**다 — 무해 문서 한 장이 bypass 없이 정상 PR 경로로
> 착지하는 것을 관측하기 위한 실측 대상(계획: 신뢰 루트 재베이스 S3', 2026-10-10).
> 착지 관측 절차와 판정 기준은
> [신뢰 루트 소급 감사 기록](../evidence/trust_root_reaudit_2026-10-10.md) §7.1에 있다.

## 클로저 펜스란

Axiom의 착지 판정은 검증기 자신의 정합을 전제로 한다: `bin/ax`가 컴파일·실행에
참여하는 파일들의 전이 closure(`trustedCheckerTreeClosure` 핀)이 **판정 시점
트리에서 유도된 closure과 정확히 일치**해야 한정 자격이 성립한다.

- **유도 authority**: `tools/ci/derive_checker_closure.nim` — `--ref <git-ref>`로
  트리 객체만 분석한다(워킹 트리 무관). 재구현·손편집은 없다.
- **핀**: `config/trusted_writer_set.json`의 `trustedCheckerTreeClosure` —
  판정식(`src/cli/merge_cli.nim`)이 `<mode> <type> <sha>\t<path>` 라인셋으로
  대조한다.
- **펜스 안**: checker 빌드에 참여하는 파일들(2026-10-10 H0 실측 857 멤버).
  이 안의 내용 변경은 클로저 불일치를 만들고, 착지는 회전(rotation) 자격
  심사로 넘어간다 — pin@H 재앵커가 ④(새 앵커 = set(H))를 충족해야만 한다.
- **펜스 밖**: docs/**, tests/**, 본 파일처럼 검증기 빌드에 참여하지 않는
  파일들. 이들은 클로저 등식에 영향이 없으므로 정상(NORMAL) 경로로 흐른다.

## 이 문서가 증명하는 것

docs/ 한 장의 추가가 (1) 클로저 등식을 깨지 않고(Δ=∅), (2) bypass·ruleset
예외 없이, (3) 일반 PR → required checks → merge 경로로 착지함을 실측하는
것. 착지 후 `tools/ci/landing_observe.sh` 관측과 ruleset bypass_actors 공집합
확인이 짝이 된다(재감사 문서 §7.1).

## C1 실측 프로브

> 2026-10-10 — 본 줄 추가만으로 Δ=∅가 유지되고, bypass·ruleset 예외 없이
> PR → required checks → merge queue 경로로 착지함을 관측한다
> (`tools/ci/landing_observe.sh` + audit log bypass 부재가 짝이다).

> A2-2 양성 픽스처 (2026-10-10): A1(④ 전 경로 평가) 세대 착지 후 본 무해
> 변경이 NORMAL/GO로 흐르고, 판정 로그의 `judge.source`(SHA-256) 존재와
> verdict 로그 아티팩트 실존이 함께 실측되는 기록 대상.

## 감시

이 등식은 상시 감시된다 — `.github/workflows/closure-watcher.yml`이 6시간
주기로 main HEAD에서 유도↔핀 대조를 재실행하고, 불일치 시 fail-closed로
적색이 되어 추적 이슈를 남긴다. 수리 절차는 재감사 문서 §6.4(긴급: main 직접
푸시 재앵커 / 구조: NORMAL에서도 ④를 평가하는 후속 회전 PR)를 따른다.

<!-- VS-1 control fixture: docs-only append; no closure member changes, so pin@H still anchors derived(H) and the PR-head preflight must pass. -->

<!-- VS-2 control fixture: docs-only. Proves the enforced B/M-split generation (admission-check@793c5af) runs EXECUTED+PASS and lands through the queue. -->

<!-- VS-2 acceptance v3: docs-only under the five-repair generation (callee 34f34a86). Expect lane green + attest cross-check green + landing. -->
