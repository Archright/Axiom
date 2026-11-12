# WP4-d Open Issue — 호출 사이트 시그니처 기반 semantic resolution 불가

EXPERIMENT_ID=act2-wp4d-symbol-identity
STATUS=OPEN (판정 보류 — rawCallTargets에 시그니처 정보를 담는 후속 작업 필요)
RELATES=topology_dependency.nim resolveCallTarget / WP4-d-2

## 문제

`resolveCallTarget` (topology_dependency.nim:14) 는 WP4-d-2 에서
`ResolutionResult`(rrUnique/rrAmbiguous/rrUnresolved) 로 일반화되어,
같은 `modulePath::functionName` 의 definition 이 여럿(func + template 등)
공존할 때 **임의 선택을 금지하고 rrAmbiguous 로 귀결**시켰다.

그러나 호출 사이트(`TopologySymbol.rawCallTargets`) 는 **이름만** 담고 있다
(topology_symbol_scanner 가 bodyFragment 에서 extractCallTargets 로 이름만 추출).
따라서:

- 호출자가 func `getBitsBE` 를 호출했는지 template `getBitsBE` 를 호출했는지
  정의적 근거가 없다 (시그니처/arity/오버로드 해석 정보 부재).
- 결과적으로 같은 이름 후보가 여럿이면 무조건 rrAmbiguous → 의존성 edge 미추가.
- 이는 **안전하지만** func/template 이 같은 nodeId 를 공유하는 경우
  실제 의도된 정의로의 dependency edge 가 **누락**될 수 있다.

## 왜 즉석 수정하지 않는가 (사용자 추가 규칙 준수)

> "구현 과정에서 새로운 identity 후보가 발견되면:
> 현재 계약에 이미 포함됨? → yes 재사용 / no → Open Issue 로 기록, 임의 편입 금지"

정확한 semantic resolution 은 **AST 기반 sem (overload resolution)** 이 필요하다.
현재는 line-based topology scanner + decl-text digest 만 존재하며:

- `definitionFingerprint` (WP4-d-1) 는 **definition 식별자**일 뿐,
  호출 site 가 어느 fingerprint 를 의도하는지는 담지 않는다.
- 호출 site 에 시그니처를 담으려면 scanner 가 call expression 의
  인자 arity/타입을 캡처해야 하는데, 이는 scan-time 파싱 범위를 넘어선다.

따라서 임의로 새 identity/signature 를 즉석 편입하지 않고 Open Issue 로 기록한다.

## 안전성은 확보됨 (WP4-d-2 로 이미 방어)

- 같은 module::name 의 func/template 공존 시 rrAmbiguous → **어느 쪽에도 edge 추가 안 함**.
- false self-dependency(호출자가 자기 자신 nodeId 참조) 가 차단됨.
- rrUnique(rrUnresolved) 시에만 의존성 추가.

즉 **블로커(크래시)는 없고, 정확성은 보존되며, 완성도(edge 누락)만 남는다.**

## 판정 포인트 (후속 WP)

1. rawCallTargets 에 호출 인자 arity/타입 혹은 호출 대상 definitionFingerprint 를
   추가로 캡처하는가?
   - 캡처한다 → resolveCallTarget 이 시그니처로 유일 결정 가능 (rrAmbiguous 감소).
   - 캡처하지 않는다 → func/template 공존 시 rrAmbiguous 로 유지 (안전 보존).
2. 이 결정은 WP4-d 진행(8-stage ladder 재실행)을 막지 않는다:
   getBitsBE 의 func/template 이 같은 nodeId 를 공유하는 상황은
   dependency graph 에러를 유발하지 않고 단순히 edge 미추가로 끝난다.

## 현재 blocker 와의 관계

operators/frontier 단계의 크래시 문제(axis engine 719, WP4-c)와는 무관.
identity 분리(WP4-d-1)와 dependency 안전 방어(WP4-d-2)는 이미 완료.
이 Open Issue 는 "edge 누락에 따른 coverage 정확성" 만 다룬다.
