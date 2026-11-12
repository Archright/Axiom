/*  fork_shim.c — POSIX fork/prctl C shim for Lean 4 Zygote daemon.
 *
 *  Implements the C functions declared via @[extern] in IR.ForkFFI.
 *  Provides:
 *    lean_fork_process  — wraps fork(2), returns child PID to parent
 *    lean_set_pdeathsig — wraps prctl(PR_SET_PDEATHSIG, sig) for child cleanup
 *    lean_reap_children — reaps zombie child processes via waitpid(WNOHANG)
 *
 *  Design notes (AGENTS.md §0.2):
 *    - Ideal: POSIX primitives directly, no wrappers
 *    - Elegant: Same pattern as shm_shim.c
 *    - Fundamental: prctl must be called AFTER fork in child (Linux clears
 *      PDEATHSIG on fork per prctl(2) man page)
 *    - Deterministic: identical input → identical output
 */

#include <lean/lean.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <string.h>

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_fork_process — wraps fork(2)
 *
 *  Returns IO UInt32:
 *    Parent receives child PID (> 0)
 *    Child receives 0
 *    Failure → IO.error
 *
 *  In Lean, the caller checks the return value:
 *    0        → child process
 *    non-zero → parent receives child PID
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_fork_process(void)
{
    pid_t pid = fork();
    if (pid < 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("fork failed")));
    }
    /* Return the PID — parent gets child PID (>0), child gets 0.
     * Both fit in UInt32 on LP64 Linux. */
    return lean_io_result_mk_ok(lean_box((uint32_t)pid));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_set_pdeathsig — wraps prctl(PR_SET_PDEATHSIG, sig)
 *
 *  MUST be called in the child process AFTER fork().
 *  Linux clears PDEATHSIG on fork; the child must re-set it.
 *
 *  Parameters:
 *    sig : UInt32  — signal number (e.g. 9 for SIGKILL)
 *
 *  Returns IO UInt32:
 *    success → 0
 *    failure → IO.error
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_set_pdeathsig(uint32_t sig)
{
    int ret = prctl(PR_SET_PDEATHSIG, (unsigned long)sig);
    if (ret != 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("prctl(PR_SET_PDEATHSIG) failed")));
    }
    return lean_io_result_mk_ok(lean_box(0));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_reap_children — non-blocking reap of zombie child processes
 *
 *  Calls waitpid(-1, &status, WNOHANG) in a loop until no more zombies
 *  remain.  This prevents zombie accumulation in the Zygote daemon
 *  parent process.
 *
 *  Returns IO UInt32:
 *    success → number of children reaped
 *    failure → IO.error (should not happen for WNOHANG waitpid)
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_reap_children(void)
{
    int reaped = 0;
    int status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        reaped++;
    }
    return lean_io_result_mk_ok(lean_box((uint32_t)reaped));
}
