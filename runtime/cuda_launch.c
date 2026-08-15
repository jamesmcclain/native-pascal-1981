/* Real-GPU device orchestration shim (Milestone D, cuda-kernel-prescription.md
 * §5.2 Strategy 1).
 *
 * This is the CUDA Driver API counterpart to cpu_device_shim.c: it defines the
 * EXACT same six `pas_dev_*` symbols the compiler already emits, so swapping
 * this file in for cpu_device_shim.c turns the *same* Pascal program into a real
 * GPU run with no Pascal-side change.  The two shims define the same symbols and
 * therefore cannot coexist in one archive (the Makefile's DEVICE_SHIM switch
 * selects exactly one).
 *
 * The Pascal builtins lower to these symbols:
 *   DEVALLOC(n)            -> pas_dev_alloc(n)            (cuMemAlloc)
 *   DEVCOPYTO(dev,src,n)   -> pas_dev_copy_to(dev,src,n)  (H2D cuMemcpyHtoD)
 *   DEVCOPYFROM(dst,dev,n) -> pas_dev_copy_from(dst,dev,n)(D2H cuMemcpyDtoH)
 *   DEVFREE(dev)           -> pas_dev_free(dev)           (cuMemFree)
 *   LAUNCH(...) lowers to the three-step driver path:
 *     module = pas_dev_module_load(registry, ptx)        (cuModuleLoadData)
 *     entry  = pas_dev_module_get_function(module, name)  (cuModuleGetFunction)
 *     pas_dev_launch(entry, gx,gy,gz, bx,by,bz, argv)     (cuLaunchKernel)
 */

#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Fail loudly with the symbolic CUDA error name -- driver errors are terse, so
 * naming the failing call and the error makes layered bring-up tractable. */
static void pas_cu_fail(const char *what, CUresult rc)
{
    const char *name = NULL;
    const char *desc = NULL;
    cuGetErrorName(rc, &name);
    cuGetErrorString(rc, &desc);
    fprintf(stderr, "pascal-cuda: %s failed: %s (%d)%s%s\n", what, name ? name : "UNKNOWN", (int) rc, desc ? " - " : "", desc ? desc : "");
    abort();
}

#define CU_CHECK(call)                                   \
    do {                                                 \
        CUresult _rc = (call);                           \
        if (_rc != CUDA_SUCCESS)                         \
            pas_cu_fail(#call, _rc);                     \
    } while (0)

/* ---- lazy context bring-up ------------------------------------------------ */

static int g_cu_ready = 0;
static CUdevice g_cu_device;
static CUcontext g_cu_context;

/* cuInit + device + context, once, on first allocate or module load. */
static void pas_cu_ensure(void)
{
    if (g_cu_ready)
        return;
    CU_CHECK(cuInit(0));
    CU_CHECK(cuDeviceGet(&g_cu_device, 0));
    CU_CHECK(cuCtxCreate(&g_cu_context, 0, g_cu_device));
    g_cu_ready = 1;
}

/* ---- allocate / copy / free ----------------------------------------------- */

/* Allocate n bytes of device memory; returns the CUdeviceptr handle cast to
 * void* (an opaque handle the host must not dereference -- the
 * dereferenceability invariant).  Pascal code only hands it back to the
 * copy/launch/free builtins. */
void *pas_dev_alloc(long long nbytes)
{
    if (nbytes <= 0)
        return NULL;
    pas_cu_ensure();
    CUdeviceptr dptr = 0;
    CU_CHECK(cuMemAlloc(&dptr, (size_t) nbytes));
    return (void *) (uintptr_t) dptr;
}

/* Host -> device copy. */
void pas_dev_copy_to(void *dev_dst, const void *host_src, long long nbytes)
{
    if (dev_dst && host_src && nbytes > 0)
        CU_CHECK(cuMemcpyHtoD((CUdeviceptr) (uintptr_t) dev_dst, host_src, (size_t) nbytes));
}

/* Device -> host copy. */
void pas_dev_copy_from(void *host_dst, const void *dev_src, long long nbytes)
{
    if (host_dst && dev_src && nbytes > 0)
        CU_CHECK(cuMemcpyDtoH(host_dst, (CUdeviceptr) (uintptr_t) dev_src, (size_t) nbytes));
}

/* Free a handle returned by pas_dev_alloc. */
void pas_dev_free(void *dev_ptr)
{
    if (dev_ptr)
        CU_CHECK(cuMemFree((CUdeviceptr) (uintptr_t) dev_ptr));
}

/* ---- module load / function lookup / launch ------------------------------- */

/* Load-once cache, keyed on the embedded PTX blob pointer.  The host embeds the
 * device PTX as a single static __pas_device_ptx global, so the pointer identity
 * is a stable per-program key; cuModuleLoadData is comparatively expensive, so
 * we load each distinct blob exactly once. */
typedef struct {
    const char *ptx;
    CUmodule module;
} pas_module_cache_entry;

#define PAS_MODULE_CACHE_MAX 32
static pas_module_cache_entry g_module_cache[PAS_MODULE_CACHE_MAX];
static int g_module_cache_count = 0;

/* Load a module from the embedded PTX blob (cuModuleLoadData).  The `registry`
 * argument is the CPU-device's name/thunk table -- ignored on the GPU, where the
 * PTX is the real module. */
void *pas_dev_module_load(void *registry, const char *ptx)
{
    (void) registry;
    if (!ptx || ptx[0] == '\0') {
        fprintf(stderr, "pascal-cuda: pas_dev_module_load: no embedded PTX " "(rebuild the host with --embed-device-ptx)\n");
        abort();
    }
    pas_cu_ensure();
    for (int i = 0; i < g_module_cache_count; i++)
        if (g_module_cache[i].ptx == ptx)
            return (void *) g_module_cache[i].module;

    CUmodule module = NULL;
    CU_CHECK(cuModuleLoadData(&module, ptx));
    if (g_module_cache_count < PAS_MODULE_CACHE_MAX) {
        g_module_cache[g_module_cache_count].ptx = ptx;
        g_module_cache[g_module_cache_count].module = module;
        g_module_cache_count++;
    }
    return (void *) module;
}

/* Resolve a kernel entry by name out of a loaded module (cuModuleGetFunction).
 * Cheap enough to call per launch. */
void *pas_dev_module_get_function(void *module, const char *name)
{
    if (!module || !name)
        return NULL;
    CUfunction fn = NULL;
    CU_CHECK(cuModuleGetFunction(&fn, (CUmodule) module, name));
    return (void *) fn;
}

/* Launch a resolved entry (cuLaunchKernel).  `argv` is exactly
 * cuLaunchKernel's kernelParams: an array of pointers, each pointing at the cell
 * holding one kernel argument value (scalars by value; device buffers as the
 * CUdeviceptr returned by pas_dev_alloc).  Pass it straight through, then
 * synchronize so D2H copy-back sees completed results and kernel faults surface
 * here. */
void pas_dev_launch(void *entry, long long gx, long long gy, long long gz, long long bx, long long by, long long bz, void **argv)
{
    if (!entry)
        return;
    CU_CHECK(cuLaunchKernel((CUfunction) entry, (unsigned) gx, (unsigned) gy, (unsigned) gz, (unsigned) bx, (unsigned) by, (unsigned) bz, 0,    /* sharedMemBytes */
                            NULL,       /* stream (default) */
                            argv,       /* kernelParams */
                            NULL));     /* extra */
    CU_CHECK(cuCtxSynchronize());
}
