/* Unsafe host descriptor import validates metadata, not provenance/liveness.
 * No raw pointer dereference or pre-data header access is permitted here. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "pascalrt.h"

static _Noreturn void new_error(const char *reason)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: NEW SUPER ARRAY %s\n", reason);
    fflush(stderr);
    abort();
}

void *pas_super_new(int64_t upper_bits, int32_t upper_unsigned, int64_t lower, int64_t domain_low, int64_t domain_high, uint64_t stride, uint64_t alignment)
{
    __int128 upper = upper_unsigned ? (__int128) (uint64_t) upper_bits : (__int128) upper_bits;
    if (upper > INT64_MAX)
        new_error("upper bound is not representable");
    if (upper < lower)
        new_error("upper bound is below declared lower");
    if (lower < domain_low || lower > domain_high || upper < domain_low || upper > domain_high)
        new_error("upper bound is outside declared index domain");
    if (!stride || !alignment || (alignment & (alignment - 1)) || alignment > 16)
        new_error("element size or alignment is unsupported");
    __uint128_t count = (__uint128_t) (upper - lower + 1);
    if (count > SIZE_MAX)
        new_error("element count overflows");
    __uint128_t bytes = count * stride;
    if (bytes > SIZE_MAX || bytes > PTRDIFF_MAX)
        new_error("byte size overflows");
    void *data = malloc((size_t) bytes);
    if (!data)
        new_error("allocation failed");
    return data;
}

void pas_super_index_nil_error(void)
{
    fflush(stdout);
    fputs("runtime error: index through NIL super-array pointer\n", stderr);
    fflush(stderr);
    abort();
}

static _Noreturn void import_error(const char *reason)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: UNSAFESUPER %s\n", reason);
    fflush(stderr);
    abort();
}

void pas_super_import_check(void *raw, int64_t lower_bits, int32_t lower_unsigned,
                            int64_t upper_bits, int32_t upper_unsigned, int64_t declared_lower, int64_t domain_low, int64_t domain_high, uint64_t stride, uint64_t alignment)
{
    __int128 lower = lower_unsigned ? (__int128) (uint64_t) lower_bits : (__int128) lower_bits;
    __int128 upper = upper_unsigned ? (__int128) (uint64_t) upper_bits : (__int128) upper_bits;
    if (lower != declared_lower)
        import_error("lower bound does not match declared lower");
    if (upper < domain_low || upper > domain_high || upper > INT64_MAX || upper < lower)
        import_error("upper bound is outside declared index domain");
    if (!raw)
        import_error("requires non-NIL data");
    uintptr_t address = (uintptr_t) raw;
    if (!alignment || (alignment & (alignment - 1)) || address % alignment)
        import_error("data is not correctly aligned");
    __uint128_t bytes = (__uint128_t) (upper - lower + 1) * stride;
    if (!stride || bytes > SIZE_MAX || bytes > PTRDIFF_MAX || (__uint128_t) address + bytes > UINTPTR_MAX)
        import_error("byte span or address arithmetic overflows");
}
