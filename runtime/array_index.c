/* Host diagnostic for a checked fixed-array subscript outside its bounds. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_array_index_error(int64_t value, int32_t value_unsigned, int64_t lo, int64_t hi)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: array index %" PRIu64 " is outside bounds %" PRId64 "..%" PRId64 "\n", (uint64_t) value, lo, hi);
    else
        fprintf(stderr, "runtime error: array index %" PRId64 " is outside bounds %" PRId64 "..%" PRId64 "\n", value, lo, hi);
    fflush(stderr);
    abort();
}
