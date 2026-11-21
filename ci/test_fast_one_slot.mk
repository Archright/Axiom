# ci/test_fast_one_slot.mk — frozen admission-callee output slot (DEBT#552).
#
# admission-check.yml, as pinned by admission-gate-v2.yml, compiles
#   make test-fast-one T=tools/ci/check_evidence_id_contract.nim
# and then executes the produced binary at the slot below:
#   /tmp/opencode/ax-one --self-check
# The pin is an immutable generation (trust-surface; an epoch rotation owns the
# repoint), so a GitHub Actions invocation of the lane must keep publishing to
# this slot until the callee pin rotates to a generation that consumes
# TEST_FAST_ONE_OUT. The Makefile test-fast-one recipe uses a private
# per-invocation directory for every non-CI invocation, so local concurrent
# sessions never share a binary. Retire this file together with the pin
# rotation.
TEST_FAST_ONE_CI_SLOT ?= /tmp/opencode/ax-one
