/*
 * Runtime diagnostics for VLOAD/VSTORE on a NEW-allocated SUPER ARRAY.
 *
 * The compiler checks the whole lane range idx .. idx+lanes-1 against
 * LOWER(p^) .. UPPER(p^) once, before any lane is loaded or stored, and
 * calls one of these on failure. Both report on stderr and abort(), the
 * same "internal runtime error" exit as ABORT (pabort.c).
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

static const char *vector_op_name(int32_t is_store)
{
    return is_store ? "VSTORE" : "VLOAD";
}

void pas_vector_nil_error(int32_t is_store)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: %s through a NIL pointer\n", vector_op_name(is_store));
    fflush(stderr);
    abort();
}

void pas_upper_nil_error(int32_t unused)
{
    (void) unused;
    fflush(stdout);
    fputs("runtime error: UPPER through NIL super-array pointer\n", stderr);
    fflush(stderr);
    abort();
}

void pas_vector_range_error(int32_t is_store, int64_t idx, int32_t idx_unsigned, int32_t lanes, int64_t lo, int64_t hi)
{
    fflush(stdout);
    if (idx_unsigned)
        fprintf(stderr, "runtime error: %s index %" PRIu64 " with %" PRId32
                " lanes is outside array bounds %" PRId64 "..%" PRId64 "\n", vector_op_name(is_store), (uint64_t) idx, lanes, lo, hi);
    else
        fprintf(stderr, "runtime error: %s index %" PRId64 " with %" PRId32
                " lanes is outside array bounds %" PRId64 "..%" PRId64 "\n", vector_op_name(is_store), idx, lanes, lo, hi);
    fflush(stderr);
    abort();
}
