/*  ShmFFI.c — POSIX shared-memory C shim for Lean 4 worker IPC.
 *
 *  Implements the C functions declared via @[extern] in IR.ShmFFI.
 *  Mirrors the memory layout defined in src/infrastructure/shared_ir_buffer.nim:
 *
 *    SharedIRHeader (64 bytes, packed):
 *      magic       uint32   offset  0   0x41584952 ("AXIR")
 *      version     uint32   offset  4   1
 *      headerSize  uint32   offset  8   64
 *      status      int32    offset 12   0/1/2/3
 *      irOffset    uint64   offset 16
 *      irSize      uint64   offset 24
 *      resultOffset uint64  offset 32
 *      resultSize  uint64   offset 40
 *      padding     16 bytes offset 48
 *
 *  Result slot (at resultOffset):
 *      status      int32    +0
 *      resultLen   int32    +4
 *      resultBytes uint8[]  +8
 */

#include <lean/lean.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

/* Compile-time layout guard — catches C compiler padding mismatches.
 * Mirrors the Nim {.packed.} object in src/infrastructure/shared_ir_buffer.nim
 * and the Lean structure in proofs/Generated/SharedIRHeader.lean. */
#include <stddef.h>
#include <assert.h>

struct __attribute__((packed)) axiom_SharedIRHeader {
    uint32_t magic; uint32_t version; uint32_t headerSize; int32_t status;
    uint64_t irOffset; uint64_t irSize; uint64_t resultOffset; uint64_t resultSize;
    uint8_t padding[16];
};

_Static_assert(sizeof(struct axiom_SharedIRHeader) == 64, "SharedIRHeader must be exactly 64 bytes");
_Static_assert(offsetof(struct axiom_SharedIRHeader, magic) == 0, "magic offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, version) == 4, "version offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, headerSize) == 8, "headerSize offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, status) == 12, "status offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, irOffset) == 16, "irOffset offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, irSize) == 24, "irSize offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, resultOffset) == 32, "resultOffset offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, resultSize) == 40, "resultSize offset");
_Static_assert(offsetof(struct axiom_SharedIRHeader, padding) == 48, "padding offset");

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_open — wraps shm_open(2)
 *
 *  Parameters (Lean FFI convention):
 *    name  : @& String   → b_lean_obj_arg  (borrowed)
 *    oflag : UInt32      → uint32_t        (unboxed scalar)
 *    mode  : UInt32      → uint32_t        (unboxed scalar)
 *
 *  Returns IO Int32:
 *    success → IO.ok fd   (fd ≥ 0)
 *    failure → IO.error
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_open(b_lean_obj_arg name, uint32_t oflag, uint32_t mode)
{
    int fd = shm_open(lean_string_cstr(name), (int)oflag, (mode_t)mode);
    if (fd < 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("shm_open failed")));
    }
    return lean_io_result_mk_ok(lean_box((uint32_t)fd));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_mmap — wraps mmap(2) with PROT_READ|PROT_WRITE, MAP_SHARED
 *
 *  Returns IO UInt64: base address of mapped region (as uint64).
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_mmap(uint64_t size, int32_t fd)
{
    void *ptr = mmap(NULL, (size_t)size,
                     PROT_READ | PROT_WRITE,
                     MAP_SHARED, (int)fd, 0);
    if (ptr == MAP_FAILED) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("mmap failed")));
    }
    return lean_io_result_mk_ok(lean_box((uint64_t)(uintptr_t)ptr));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_munmap — wraps munmap(2)
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_munmap(uint64_t addr, uint64_t size)
{
    int ret = munmap((void *)(uintptr_t)addr, (size_t)size);
    if (ret != 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("munmap failed")));
    }
    return lean_io_result_mk_ok(lean_box(0));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_close — wraps close(2)
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_close(int32_t fd)
{
    int ret = close((int)fd);
    if (ret != 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("close failed")));
    }
    return lean_io_result_mk_ok(lean_box(0));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_unlink — wraps shm_unlink(2)
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_unlink(b_lean_obj_arg name)
{
    int ret = shm_unlink(lean_string_cstr(name));
    if (ret != 0) {
        return lean_io_result_mk_error(
            lean_mk_io_error_other_error(
                (uint32_t)errno,
                lean_mk_string("shm_unlink failed")));
    }
    return lean_io_result_mk_ok(lean_box(0));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_read_bytes — copy `size` bytes from mapped memory at addr+offset
 *
 *  Returns IO ByteArray (Lean SArray<uint8>).
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_read_bytes(uint64_t addr, uint64_t offset, uint64_t size)
{
    const uint8_t *src = (const uint8_t *)(uintptr_t)(addr + offset);
    lean_object *ba = lean_alloc_sarray(1, (size_t)size, (size_t)size);
    memcpy(lean_sarray_cptr(ba), src, (size_t)size);
    return lean_io_result_mk_ok(ba);
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_write_status — write a uint32 at addr+offset
 *
 *  Used for updating the header status field (offset 12) or any other
 *  uint32 slot in the shared region.
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_write_status(uint64_t addr, uint64_t offset, uint32_t status)
{
    uint8_t *dst = (uint8_t *)(uintptr_t)(addr + offset);
    memcpy(dst, &status, sizeof(uint32_t));
    return lean_io_result_mk_ok(lean_box(0));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  lean_shm_write_result — write status + message into result slot
 *
 *  Result slot layout at addr+resultOffset:
 *    [+0]  int32 status   (4 bytes, native endian)
 *    [+4]  int32 resultLen (4 bytes, native endian)
 *    [+8]  uint8[] result  (resultLen bytes)
 *
 *  Mirrors Nim SharedIRBuffer.writeResult.
 * ═══════════════════════════════════════════════════════════════════════════ */
lean_obj_res lean_shm_write_result(uint64_t addr, uint64_t resultOffset,
                                   uint32_t status, b_lean_obj_arg msg)
{
    uint8_t *base = (uint8_t *)(uintptr_t)(addr + resultOffset);

    /* status (4 bytes) */
    memcpy(base, &status, sizeof(uint32_t));

    /* result length (4 bytes) */
    uint32_t msgLen = (uint32_t)lean_string_len(msg);
    memcpy(base + 4, &msgLen, sizeof(uint32_t));

    /* result bytes */
    if (msgLen > 0) {
        memcpy(base + 8, lean_string_cstr(msg), (size_t)msgLen);
    }

    return lean_io_result_mk_ok(lean_box(0));
}
