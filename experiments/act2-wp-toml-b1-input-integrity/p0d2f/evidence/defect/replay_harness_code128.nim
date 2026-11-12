# nim-check: skip — 보존 아티팩트(증거): 주체 핀(@4aa8e22)의 d2kernels 모듈과만
# 컴파일되는 재생 하니스 원본이다. Axiom3 트리의 번역 단위가 아니므로 nim-check
# 게이트 코퍼스에서 제외한다(.githooks/pre-commit Part 1 스킵 계약). 보존 사유와
# 출처: evidence/README.md · state_v3/.axiom/tmp/replay/1fc955b3a2036d50/.
import d2kernels
echo "AXIOM_REPLAY_BEGIN"
echo $d2HexEscapeAppendLen(128)
echo "AXIOM_REPLAY_END"
