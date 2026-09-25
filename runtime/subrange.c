/*
 * Runtime diagnostic for a value stored into a subrange outside its declared
 * bounds. Under $RANGECK (on by default) the compiler compares the value
 * against the subrange's low and high ordinals before an assignment, a
 * value-parameter pass, a READ, or the start of a FOR loop, and calls this
 * on failure. It reports on stderr and abort()s, the same exit as the other
 * range diagnostics (vector_bounds.c, readq.c).
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_subrange_error(int64_t value, int32_t value_unsigned, int64_t lo, int64_t hi)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: value %" PRIu64 " is outside subrange %" PRId64 "..%" PRId64 "\n", (uint64_t) value, lo, hi);
    else
        fprintf(stderr, "runtime error: value %" PRId64 " is outside subrange %" PRId64 "..%" PRId64 "\n", value, lo, hi);
    fflush(stderr);
    abort();
}
