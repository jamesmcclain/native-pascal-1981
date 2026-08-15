/* CPU-device orchestration shim (Milestone D, cuda-kernel-prescription.md §7).
 *
 * The "device" is the host CPU: device memory is ordinary heap memory, the
 * host->device and device->host copies are plain memcpy, and a kernel launch
 * is a direct call emitted by the compiler (so there is no launch entry here).
 * This lets a host Pascal program exercise the full allocate / copy / launch /
 * copy-back surface with zero GPU, as the fast correctness loop. Swapping these
 * four functions for CUDA Driver API wrappers (cuMemAlloc / cuMemcpyHtoD /
 * cuMemcpyDtoH / cuMemFree) turns the same Pascal program into a real GPU run
 * without touching the Pascal side (Strategy 1, §5.2).
 *
 * The Pascal builtins lower to these symbols:
 *   DEVALLOC(n)            -> pas_dev_alloc(n)
 *   DEVCOPYTO(dev,src,n)   -> pas_dev_copy_to(dev, src, n)   (H2D)
 *   DEVCOPYFROM(dst,dev,n) -> pas_dev_copy_from(dst, dev, n) (D2H)
 *   DEVFREE(dev)           -> pas_dev_free(dev)
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Thread-local index registers.  The compiler emits THREADIDX_X / BLOCKIDX_X
 * etc. as loads from these symbols (declared 'external thread_local global i32'
 * in the device LLVM IR).  pas_dev_launch sets them before each thunk call so
 * the kernel body sees the correct indices -- the same values a GPU provides
 * via hardware special registers.  _Thread_local storage makes the design
 * naturally OpenMP-parallelisable: each OS thread gets its own set. */
/* Thread indices and block indices start at 0 (first and only thread/block). */
_Thread_local int32_t __pas_tid_x = 0, __pas_tid_y = 0, __pas_tid_z = 0;
_Thread_local int32_t __pas_ctaid_x = 0, __pas_ctaid_y = 0, __pas_ctaid_z = 0;
/* Dimension counts default to 1: a unit grid so stride = BLOCKDIM*GRIDDIM = 1.
 * pas_dev_launch overrides these before the first thunk call. */
_Thread_local int32_t __pas_ntid_x = 1, __pas_ntid_y = 1, __pas_ntid_z = 1;
_Thread_local int32_t __pas_nctaid_x = 1, __pas_nctaid_y = 1, __pas_nctaid_z = 1;

/* Allocate n bytes of "device" memory; returns an opaque handle the host must
 * not dereference (the dereferenceability invariant). On the CPU device the
 * handle happens to be a real heap pointer, but Pascal code only ever hands it
 * back to the copy/launch/free builtins. */
void *pas_dev_alloc(long long nbytes)
{
    if (nbytes <= 0)
        return NULL;
    return malloc((size_t) nbytes);
}

/* Host -> device copy. */
void pas_dev_copy_to(void *dev_dst, const void *host_src, long long nbytes)
{
    if (dev_dst && host_src && nbytes > 0)
        memcpy(dev_dst, host_src, (size_t) nbytes);
}

/* Device -> host copy. */
void pas_dev_copy_from(void *host_dst, const void *dev_src, long long nbytes)
{
    if (host_dst && dev_src && nbytes > 0)
        memcpy(host_dst, dev_src, (size_t) nbytes);
}

/* Free a handle returned by pas_dev_alloc. */
void pas_dev_free(void *dev_ptr)
{
    free(dev_ptr);
}

/* Launch a kernel through a CUDA-driver-shaped three-step path.  The compiler
 * emits, per host compiland, a kernel registry: parallel name/entry tables it
 * fills with the launchable kernels and their per-kernel dispatch thunks.  The
 * launch site then does:
 *
 *     module = pas_dev_module_load(registry, ptx);     // cuModuleLoadData
 *     entry  = pas_dev_module_get_function(module, name); // cuModuleGetFunction
 *     pas_dev_launch(entry, gx,gy,gz, bx,by,bz, argv);  // cuLaunchKernel
 *
 * On the CPU device the "module" is the registry, get_function is a by-name
 * lookup returning the thunk, and launch drives it across the full launch
 * geometry (see pas_dev_launch).  Swapping this
 * file for CUDA Driver API wrappers turns the *same* compiler output into a real
 * GPU launch with no Pascal-side change: load takes the embedded PTX blob,
 * get_function returns a CUfunction, launch is cuLaunchKernel.  (A CUDA shim
 * should cache the loaded module internally -- e.g. a static handle keyed on the
 * registry/ptx pointer -- so the per-launch load call stays cheap.) */

/* Must match the LLVM struct the compiler emits: { i8** names; i8** entries;
 * i64 count }. */
typedef struct {
    const char *const *names;
    void *const *entries;
    long long count;
} pas_dev_registry;

/* Load a "module".  CPU device: the module *is* the compiler-emitted registry;
 * the PTX blob is unused here (the CUDA shim cuModuleLoadData's it instead and
 * ignores the registry). */
void *pas_dev_module_load(void *registry, const char *ptx)
{
    (void) ptx;
    return registry;
}

/* Resolve a kernel entry by name out of a loaded module.  CPU device: linear
 * search of the registry's name table, returning the matching dispatch thunk
 * (or NULL if absent). */
void *pas_dev_module_get_function(void *module, const char *name)
{
    const pas_dev_registry *r = (const pas_dev_registry *) module;
    long long i;
    if (!r || !name)
        return 0;
    for (i = 0; i < r->count; i++)
        if (r->names[i] && strcmp(r->names[i], name) == 0)
            return r->entries[i];
    return 0;
}

/* Launch a resolved entry.  CPU device: the entry is the dispatch thunk.
 * We emulate the GPU by iterating over every block (gx*gy*gz) and every thread
 * within each block (bx*by*bz), setting the thread-local index registers before
 * each call so the kernel body sees the correct THREADIDX_x/BLOCKIDX_x values.
 * BLOCKDIM_x/GRIDDIM_x are constant for the whole launch and are set once.
 *
 * Loop order matches CUDA's row-major convention: x is the fastest-varying
 * thread index, z the slowest, mirroring the hardware warp layout. */
typedef void (*pas_klaunch_fn)(void **);
void pas_dev_launch(void *entry, long long gx, long long gy, long long gz, long long bx, long long by, long long bz, void **argv)
{
    if (!entry)
        return;
    pas_klaunch_fn fn = (pas_klaunch_fn) entry;
    /* Block and grid dimensions are constant across the launch. */
    __pas_ntid_x = (int32_t) bx;
    __pas_ntid_y = (int32_t) by;
    __pas_ntid_z = (int32_t) bz;
    __pas_nctaid_x = (int32_t) gx;
    __pas_nctaid_y = (int32_t) gy;
    __pas_nctaid_z = (int32_t) gz;
    for (long long gz_i = 0; gz_i < gz; gz_i++)
        for (long long gy_i = 0; gy_i < gy; gy_i++)
            for (long long gx_i = 0; gx_i < gx; gx_i++) {
                __pas_ctaid_x = (int32_t) gx_i;
                __pas_ctaid_y = (int32_t) gy_i;
                __pas_ctaid_z = (int32_t) gz_i;
                for (long long bz_i = 0; bz_i < bz; bz_i++)
                    for (long long by_i = 0; by_i < by; by_i++)
                        for (long long bx_i = 0; bx_i < bx; bx_i++) {
                            __pas_tid_x = (int32_t) bx_i;
                            __pas_tid_y = (int32_t) by_i;
                            __pas_tid_z = (int32_t) bz_i;
                            fn(argv);
                        }
            }
}
