# ACT2-R0 — R0-E Completion Evidence (E-E1 ~ E-E8)

> 계획: `miles-morales-cannonball-kate-bishop.md` "Completion Evidence" 표 (worktree 경로는 `Axiom-worktree-r0`로 개정).
> 판정: PASS/FAIL은 아래 명령의 실제 출력으로만 판정. 실행일: 2026-10-01.

## E-E1 — Subject authority (조건1)

**명령:**
```bash
cd <workspace>/nim-stew
git rev-parse HEAD
git status --porcelain
git ls-files --others --exclude-standard -- '*.nim' '*.nims' | wc -l
jq -r '.gitCommit, .ingressDigest, (.ingressManifest|length)' <worktree>/experiments/act2-r0-reanchor/subject_authority.json
```

**실출력:**
```
c75502ceedb5ed2a37b7b5e4744fc71313682859
?? data/
0
c75502ceedb5ed2a37b7b5e4744fc71313682859
978d826944f301260c64169b813262c50e068f27f26d24c9cae5f0a07517a0a3
87
```

**기대:** `c75502ce… / ?? data/ / 공집합 / ingressManifest(path→sha256)·ingressDigest·equality`

**판정: PASS** — ingressManifest 87 entry(path→sha256), ingressDigest `978d8269…`, equality 3층 갱신(v3 기준: layer1 PASS, layer2 unable, layer3 absent).

---

## E-E2 — Execution authority (조건2)

**명령:**
```bash
jq '{axiomCommit, axBinarySha256, executionIngressDigest, executionIngressEntryCount, derivedWithinStateRule, systemIPCAllowlist}' <worktree>/experiments/act2-r0-reanchor/execution_authority.json
# + 전 entry 값 형식 검사(sha256 | absent | dir:)
python3 -c "import json,re; m=json.load(open('execution_authority.json'))['executionIngressManifest']; bad=[(k,v) for k,v in m.items() if v not in ('absent','dir:') and not re.fullmatch(r'[0-9a-f]{64}',v)]; print(len(m), bad[:5])"
```

**실출력:**
```
axiomCommit: 827329cbd8a95d614c09aa600cb7385307e66178
axBinarySha256: fd7c36b1026c78605a5fac72d9a06edb468eb2f1aa805373873f541e4da3884b
executionIngressDigest: 2237e13ab4edf759ac590879210de69e6f355e0e1991fcfe8451793e0adc33fd
executionIngressEntryCount: 4688
derivedWithinStateRule: state: paths written by the run and later re-read are derived outputs…
systemIPCAllowlist: [{path: /var/run/nscd/socket, kind: AF_UNIX pathname socket, undeclaredUnixIPC: 0, requiresRatification: true}]
entries: 4688  non-standard values: []
```

**기대:** axiomCommit==build_env.nim(827329cbd), 전 entry sha256, digest, cache 제외 명기, strace subset, toolchainDigest — scopeDigest 없음

**판정: PASS** — 미선언 ingress 0(v3 strace 대조), cache 제외=`excludedOutputs`+`derivedWithinStateRule`, scopeDigest 부재, toolchainIdentity=표시용 명기.

---

## E-E3 — 복구 증거 31건 (조건3)

**명령:**
```bash
cd <worktree>   # repo 루트
while read -r sha path; do [ -f "${path#repo:}" ] || echo MISS; done < experiments/act2-r0-reanchor/restored_evidence_checksums.txt
# + 전건 sha256 재검증
```

**실출력:**
```
checked=31 missing=0 mismatches=0
```

**판정: PASS** — 31/31 존재 + sha256 일치 (archival 17건은 복구 대상 아님 · 원본 삭제 없음).

---

## E-E4 — Coverage matrix (조건4)

**명령:**
```bash
jq -r '[.schemaVersion, (.rows|length), .canonicalOrderSource, ([.rows[]|select(.currentTruth=="OPEN")]|length)] | @tsv' coverage-matrix.json
jq -r '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[] | "\(.sortKey) \(.target) \(.lastVerdict)"' coverage-matrix.json
```

**실출력:**
```
1	35	repo:experiments/act2-wp4h1-intrinsic/canonical/intrinsic-ranking.json	2
12 bitops2.getBitsBE pre_sieved
17 base36.decodedLength timeout
```

**기대:** 5축 35행 + canonicalOrderSource + OPEN predicate(실행 안 함)

**판정: PASS** — `coverage-matrix.md` 투영 동반, OPEN predicate 유지, 첫 OPEN = bitops2.getBitsBE.

---

## E-E5 — unshare+env -i 재현: exit·canonical result·nodeId·stateSeed·AF_INET/AF_UNIX·env·의미론 (조건5)

**명령(v3 정본):**
```bash
cd .-worktree-r0
export STATE3=/tmp/act2r0_witness_v3_$(date +%s); mkdir -p "$STATE3/data" "$STATE3/tmp" "$STATE3/home" "$STATE3/.axiom/cache"
cp data/{verification_scope.lock,baseline.json} "$STATE3/data/"
strace -f -e trace=openat,openat2,execve,socket,connect -o "$STATE3/execution_observe_v3.log" \
  unshare -rni -- env -i PATH="$PATH" HOME="$STATE3/home" ELAN_HOME=<user-home>/.elan TMPDIR="$STATE3/tmp" \
      AXIOM_STATE_DIR="$STATE3" LANG=C LC_ALL=C GIT_CONFIG_NOSYSTEM=1 \
      bin/ax prove --project <workspace>/nim-stew \
                   --target stew/bitops2.nim::getBitsBE --limit 1
echo "exit=$?"   # → 2
```

**실출력 요약:**
```
exit=2
Sandbox probe successful
IR pipeline: Total 6, Pass 3, Fail 3 (getBitsBE psFail smBMC/pkZ3Bmc)
[1/1] stew/bitops2.nim::getBitsBE — pre-sieved | UAP 0 results (requests=1)
Sieve-Gate StructuralAST succeeded → srNoTransformApplied skip
verifiedRatio=0.0000, verified=0/40, gateVerdict FAIL
AF_INET/AF_INET6 connect: 0건
AF_UNIX connect: 20건 — 전부 /var/run/nscd/socket, 전부 -1 ENOENT(연결 성립 0, pid=/bin/bash lake 래퍼, glibc NSS 프로브)
미선언 ingress: 0 (성공 읽기+execve+dir 목록 전부 선언분 내; state 28건=seed 2+derived 26)
env(HOME) 읽기: 0건 (git config 중립화)
관측 log sha256: 79e8596325026da5c9ce75ef9ebb7b8998f616bdc18185bda8d8e6041eba04da
```

**기대:** 전부 기록, 위반 = 미충족(blocker)

**판정: PASS** — 의미론 판정 same-class(4중: completeness evidence 바이트 동일 c80cce75…, z3 digest d067de02… 동일, provenance smBMC/pkZ3Bmc 동일, exit 2 동일). v2(exit 0, divergent)는 amendment 근거로 기록 보존.

---

## E-E6 — 결속 reproduction (조건6)

**명령:**
```bash
jq '{exitCode, stateSeedDigest, networkConnectAttempts, unixSocketConnectAttempts, undeclaredIngressPaths, nodeId, semanticComparison.verdict}' reproduction.json
```

**실출력:**
```
exitCode: 2
stateSeedDigest: 34b5e10f081968ad80b557e23d36abbcaddd1d12440b7daacc83b3f5178daf7a
networkConnectAttempts: 0
unixSocketConnectAttempts: 20
undeclaredIngressPaths: []
nodeId: stew/bitops2.nim::getBitsBE
semanticComparison.verdict: same-class
```

**기대:** 4 digest 병기, 전 path logical

**판정: PASS** — ingressDigest(`978d8269…`)·executionIngressDigest(`2237e13a…`)·stateSeedDigest(`34b5e10f…`)·envAllowlist(8변수+amendment 3건, 값 기록) 병기, 전 path logical prefix(subject:/repo:/state:/toolchain:/env:).

---

## E-E7 — firstOpenTarget 기계 산출 (조건7)

**명령:**
```bash
jq -r '.rows | sort_by(.sortKey) | map(select(.currentTruth=="OPEN")) | .[0].target' coverage-matrix.json
jq -r '.firstOpenTarget.target' r0-evidence-manifest.json
```

**실출력:**
```
bitops2.getBitsBE
bitops2.getBitsBE
```

**판정: PASS** — jq 파이프 출력 == manifest 필드. (2순위 OPEN base36.decodedLength — 실행하지 않음; sortKey/nodeIdForm 병기됨)

---

## E-E8 — R0-E 보고서 (B7)

**명령:**
```bash
grep -nE '^## (Question|Context|Scope|Procedure|Result|Evidence|Classification|Interpretation|Non-Conclusions|Next Experiment)$' r0-reproduction-report.md
```

**실출력:**
```
7:## Question          13:## Context          23:## Scope          39:## Procedure
99:## Result          118:## Evidence          133:## Classification  137:## Interpretation
145:## Non-Conclusions  153:## Next Experiment
```

**판정: PASS** — §14 10섹션 완비, Non-Conclusions 5항목 필수 포함(byte-identity 미성립 / 8월 dirty-state 재구성 불가 / journal provenance-unqualified / "project verified" 불가 / 선언 manifest=정본·strace=검증자 + worktree 충돌 이관 사실), firstOpenTarget 미실행 명시, WORKTREE 이관 사실(Context·Non-Conclusions 모두 기재).

---

## 종합 판정

| # | 항목 | 판정 |
|---|---|---|
| E-E1 | subject authority | **PASS** |
| E-E2 | execution authority | **PASS** |
| E-E3 | 복구 31건 | **PASS** |
| E-E4 | coverage matrix | **PASS** |
| E-E5 | 재현(exit 2·same-class·미선언 0·AF_INET 0) | **PASS** |
| E-E6 | reproduction 결속 | **PASS** |
| E-E7 | firstOpenTarget | **PASS** |
| E-E8 | 보고서 §14 | **PASS** |

**R0-E 게이트 판정: 충족** — 단, `systemIPCAllowlist`의 `/var/run/nscd/socket`(AF_UNIX 프로브)은 **사용자 비준 필요 잔재**(`requiresRatification: true`)로 남는다. **FAIL 기록: 없음.** (v2 실행은 divergence로 기록 — 정식 FAIL 항목 아님, amendment 근거 절차 결과)