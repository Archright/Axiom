# WP1 Result — External Symbol Ingress

EXPERIMENT_ID=act2-wp1-external-symbol-ingress / SUBJECT=nim-stew@c75502c / AXIOM=f7dd583ca+WP0
GOLDEN: `stew/endians2.nim::swapBytesNim(x: uint32): uint32` (:65-68, imports 0개, 비-generic 순수 func)

## 1. Question
외부 심볼 하나가 결정론적 canonical identity로 Axiom verification universe까지 ingress되는가?

## 2. Procedure
- Blocking path 전수 추적(wp1-analysis.md §1) → Golden 선정(§2) → 최소변경 1파일
  `tools/wp1_ingress_probe.nim`(생산 함수 재사용 측정 프로브) → RunA/RunB 결정론 스모크.

## 3. Evidence Table

| Predicate | Result | Evidence | Failure/Gap |
|---|---|---|---|
| E1 SourceDiscovery | **PASS** | /tmp/wp1/runA.json E1: targetInFileSet=true, relPath=`stew/endians2.nim`, fileSha256Hex 기록, usedFallback=false, duplicateCount=0; subjectFingerprint(digests 참조) | — |
| E2 ModuleIdentity | **PASS(주석)** | GlobalSymbolGraph(subject root)에 `endians2.swapBytesNim` 엔트리 존재, modulePath=endians2.nim(subject-relative) | 그래프는 오버로드 4개를 단일 qualifiedName으로 수렴(uint32 구분은 소스 정밀분석으로 보완) |
| E3 ImportResolution | **PASS** | 대상 모듈 import 라인 0개 확인, classifications=[]; 생산 resolveModuleName 반환=`unresolvable`(core/-prefix·상대만 해석하는 현행 의미론의 정직 기록) | subject-local import 일반화는 B군 |
| E4 SymbolAdmission | **BLOCKED(taxonomy)** | topology 큐에 endians2.nim 발원 노드 171개 존재하나 admission=false. verdict=`Blocked:S3-registry-static` (S1 kernel-scope Axiom-self lock + S2 isInKernelScope + S3 compileTime registry) | Product limitation — scope semantics 재설계 필요 → §6 BLOCKER |
| E5 ObligationCandidate | **Unsupported(taxonomy)** | AST에서 proc node 발견 성공(parseStringAST+findNodesP)하나 convertFuncDef은 NimNode(ref) 요구—헤드리스 PNode 경계 | `Unsupported(PNode-to-NimNode-boundary)` |

## 4. Determinism Smoke (§8)
- RunA ingressDigest == RunB ingressDigest == `6c3b7c999afa5e3ad3b57adf84179d56f5728e64f5f3930f9bfe8a7e42297e5f`
- 비교 항목(sourceFingerprint/module identity/dependencyFingerprint(=absent-lock 파생)/symbol identity/taxonomy) 전부 동일

## 5. Subject Immutability (§9)
- 두 런 후 `git -C nim-stew status --porcelain` == empty (P4 원칙 유지)

## 6. BLOCKER (mission §6/§12 양식)
- **Blocker**: S1 커널 스코프(`loadKernelScope` on `data/verification_scope.lock`, axiom_engine.nim:636-640 failClosed)를 external subject universe와 공유할 수 없음. S2/S3 게이트가 이 스코프와 컴파일타임 레지스트리를 유일 근거로 삼음.
- **Evidence**: 위 Evidence table E4 행 + analysis §1 trace + loadKernelScope 소비부 일원화.
- **Why minimal change is insufficient**: 진입 허용을 위해선 스코프 합집합/네임스페이스 분리 중 택일이 필수이고 어느 쪽도 lock의 SSOT 의미를 건드리지 않고는 불가 — mission §6이 금지한 재설계 영역.
- **Proposed next WP**: WP1.5 설계 문서 — "Subject-scope projection contract": VerificationRun.scopeProjection{selfScope ∪ subjectScope(subjectFileSet→파생, 별도 파일 subject_scope.lock)} 스키마 확정 → 계약 개정(WP0-a 절차 준용) → S2/S3에 scopeSource 태깅 → 그 후 S4 IR selection의 subject 분기 허용.

## 7. Protected Invariant Audit
변경 파일 = tools/wp1_ingress_probe.nim 1개 신규뿐. 다음 전부 무접촉:
import_encapsulation_gate.nim / config.nims importEncapsulation / ci.yml /
journal schema / KAA 단일경로(+receiptToolchainFingerprint Phase A) / VKD 정의 /
baseline.json / D1~D4 의미론 / WP0 subject-state-workspace 분리.
검증 cmd: git diff --quiet -- <각 파일> (exit 0).

## 8. PASS 판정 (mission §10 문장 적용)
E1/E2/E3은 통과, E4/E5는 생성 불가 사유가 mission §4 taxonomy대로 정확히 분류됨
(Blocked:S3-registry-static / Unsupported(PNode-to-NimNode-boundary)).
subject tree 무변경, D1/D3/D3-b 우회 없음, 반복 실행 간 ingress 결과 동일.

> Partial PASS — E1–E3 deterministic ingress proven; E4/E5 blocked by an explicitly
> reported scope-semantics BLOCKER, not by silent bypass. External symbol NOT claimed verified.

## 9. Next
WP1.5 scope-projection 계약 설계 승인 여부 결정 → 승인 시 WP2(E4 재측정+E5 도달) 착수.
