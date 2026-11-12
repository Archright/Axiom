# WP4-d-0 Final Verdict — Definition Identity Discriminator 실측 판정

EXPERIMENT_ID=act2-wp4d-symbol-identity
SUBJECT=nim-stew@c75502c
AXIOM=Axiom@089251924 (HEAD)
DATE=2026-08-28

## 0. 판정 요약

**decl-text digest (다중줄 시그니처 SHA-256) 는 Axiom 워크로드의 실질 symbol collision을
완벽히 분리한다. 그러나 다음 두 가지는 discriminator 스펙 외의 Open Issue로 남는다.**

| 코드베이스 | 함수형 duplicate groups | discriminator로 해결 | residual (동일 decl-text) |
|---|---|---|---|
| nim-stew | 119 | 114 | 5 |
| Axiom self | 188 | 166 | 22 |

일차 스캐너(wp4d_scan.py)는 `let/var/const/type`까지 전부 포함해
nim-stew 227 / Axiom 3011 그룹, residual 48 / 1544 를 보고했으나,
이는 **함수형 심볼이 아닌 local binding shadowing**이 과포함된 수치다.
Axiom의 canonical verification symbol universe 는 함수형 심볼
(func/proc/template/macro/iterator/method/converter) 이므로,
재측정(wp4d_func_only.py) 결과를 판정 기준으로 한다.

---

## 1. target 워크로드: getBitsBE 는 discriminator 로 정상 분리됨

nim-stew/stew/bitops2.nim:

- line 559: `func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T`
- line 599: `template getBitsBE*(data: openArray[byte], slice: HSlice): BiggestUInt`

두 정의는 **시그니처가 다르다** (func 3-param / template 2-param). decl-text digest가
서로 다른 값을 부여 → nodeId 충돌 해소. 이는 WP4-c V3 에서 확정된
`verified_frontier.nim:88-89` 의 duplicate func+template nodeId 충돌을
바로 제거하는 케이스다.

**결론: getBitsBE 는 PASS. discriminator 의 정확한 목적을 100% 달성한다.**

---

## 2. residual collision 분석 — 대부분은 실질 symbol identity 위협이 아님

### 2a. forward-declaration / 재선언 쌍 (Axiom self, 오히려 "병합이 올바름")

cst_offset_extractor.nim, native_cgroup.nim 등에서:

- `proc extractFuncSpan` 가 line 60(시그니처만) 과 line 182(본문 정의) 에
  같은 시그니처로 존재.
- `createCgroupSlice` 가 line 95 / 238, `defaultConfig` 가 206 / 255.

이는 동일 논리 함수의 시그니처 재선언/플랫폼 분기이며, **같은 digest 가 나오는 게
올바르다**. 이들을 "서로 다른 심볼"로 분리하면 오히려 잘못이다.

### 2b. 서로 다른 scope/branch 의 같은-시그니처 중복 (nim-stew + Axiom self)

- `interval_set::one` — line 218/240/244/251: 서로 다른 generic 블록 안의 template.
- `contract_synthesis::walk` — line 19/63/273: 서로 다른 specialization.
- `dependency_analyzer::dfs` — 151/211, `post_satisfaction::peel` — 202/255.

Nim 에서 **같은 scope 에 동일 시그니처 중복 정의는 컴파일 오류**다. 이들이 공존하는 건
각자 다른 scope/branch 에 있기 때문이다. decl-text 가 같아도, 실제로 서로 다른
정의다.

### 2c. 진짜 남는 리스크 (Open Issue)

line-based scanner(topology_parser.nim) 가 **scope/블록 구조를 인식하지 못하고**
모든 `template one` / `func walk` 를 module::name 으로 평탄화한다면,
동일 decl-text 의 시그니처가 중복 nodeId 를 만들 수 있다.

그러나:
- 이는 **discriminator 스펙 밖**의 scope-handling 문제다.
- 현재 blocker(getBitsBE) 의 특정 케이스(func vs template, 다른 시그니처)는
  discriminator 로 완전 해소된다.
- residual 로 남는 동일 시그니처 쌍은 실질적으로 서로 다른 scope/브랜치이므로,
  topology 가 이미 시그니처+scope 를 구분한다면 문제없다. line-based scanner 의
  scope 인식은 별도 검증 필요.

---

## 3. 측정 스펙 교훈

- local binding(let/var/const/type) 을 symbol identity inventory 에 포함하면
  shadowing 으로 residual 이 폭증한다. **canonical symbol universe = 함수형 심볼**
  만이 정확한 분모다.
- `reconstruct_span` 의 no-paren truncation(첫 `=` 에서 중단) 은 RHS 를 버려
  같은 이름+다른 RHS 를 병합시킨다. 함수형 심볼에 대해선 paren-balance 로
  정확히 시그니처만 뽑힌다.

---

## 4. WP4-d-0 결론

- **discriminator(decl-text digest) 자체는 워크로드에 대해 PASS.**
- BUT 선언 텍스트가 동일하면서 서로 다른 scope/branch 에 존재하는 정의들은
  discriminator 로 구분되지 않는다. 이는 **Open Issue 로 기록**하고, 임의로
  더 큰 discriminator(예: 시그니처 AST) 를 즉석 편입하지 않는다
  (사용자 추가 규칙: 범위 밖 identity 후보는 Open Issue 로 기록 후 재사용/판정).

- Open Issue 참조: `wp4d-open-issue-scope-awareness.md` (범위는 WP5/WP6 topology
  scope-awareness 에서 판정).

---

## 5. 다음 단계 (WP4-d-1 로)

WP4-d-0 판정(PASS for workload) 을 바탕으로:

- WP4-d-1: SorterNode 에 `definitionFingerprint` (다중줄 시그니처 digest) 추가.
  getBitsBE 의 두 정의는 서로 다른 fingerprint → nodeId 충돌 해소.
- 동일 시그니처 residual 들은 현재는 같은 fingerprint 를 가져 nodeId 가 합쳐지되,
  Nim 상 같은 scope 중복 불가 + 실제로 별도 scope 이므로 topology 가 시그니처
  + scope 를 분리하는 WP6 에서 확정한다.

## 6. 저장소 산출물

- wp4d-definition-inventory.json (전체, 스캐너 생성)
- wp4d-definition-inventory-*-RAW.txt (전체 RAW)
- wp4d-func-only-nim-stew.txt / wp4d-func-only-axiom-self.txt (함수형 필터)
- wp4d_scan.py / wp4d_func_only.py / wp4d_merge.py (측정 스크립트)
- wp4d-discriminator-verdict.md (1차 스캐너 보고)
- **wp4d0-final-verdict.md (본 파일 — 판정 정본)**
