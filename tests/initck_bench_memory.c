/* Measure requested allocation bytes of the real heap-shadow registry.
 * Linker wrappers are test-only; excludes allocator headers and Pascal data. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../runtime/pascalrt.h"

void *__real_calloc(size_t, size_t);
void __real_free(void *);
static struct { void *p; size_t n; } allocations[8];
static size_t live, peak;
void *__wrap_calloc(size_t n, size_t size)
{
    void *p = __real_calloc(n, size);
    assert(p);
    for (size_t i = 0; i < 8; ++i) {
        if (!allocations[i].p) {
            allocations[i].p = p;
            allocations[i].n = n * size;
            live += n * size;
            if (live > peak) peak = live;
            return p;
        }
    }
    abort();
}
void __wrap_free(void *p)
{
    for (size_t i = 0; i < 8; ++i) {
        if (p && allocations[i].p == p) {
            live -= allocations[i].n;
            allocations[i].p = NULL;
            break;
        }
    }
    __real_free(p);
}
int main(void)
{
    static char key;
    const long leaves = 30000L * 64;
    pas_initck_heap_new(&key, leaves);
    size_t registered = live;
    pas_initck_heap_dispose(&key);
    printf("{\"leaves\":%ld,\"pascal_data_bytes\":%ld,"
           "\"registered_bytes\":%zu,\"peak_requested_bytes\":%zu,"
           "\"retained_registry_bytes\":%zu,\"shadow_bytes\":%zu}\n",
           leaves, leaves * 2, registered, peak, live, registered - live);
    assert(registered - live == (size_t)leaves);
    return 0;
}
