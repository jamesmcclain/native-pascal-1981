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

void pas_concat_error(uint64_t length, int32_t capacity, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: RANGECK CONCAT length %" PRIu64 " exceeds capacity %" PRId32 " at line %" PRId32 " column %" PRId32 "\n", length, capacity, line, column);
    fflush(stderr);
    abort();
}

void pas_lstring_length_error(uint64_t length, int32_t capacity, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: RANGECK LSTRING length %" PRIu64 " exceeds capacity %" PRId32 " at line %" PRId32 " column %" PRId32 "\n", length, capacity, line, column);
    fflush(stderr);
    abort();
}

void pas_chr_error(int64_t value, int32_t value_unsigned, int32_t line, int32_t column)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: RANGECK CHR argument %" PRIu64 " is outside 0..255 at line %" PRId32 " column %" PRId32 "\n", (uint64_t) value, line, column);
    else
        fprintf(stderr, "runtime error: RANGECK CHR argument %" PRId64 " is outside 0..255 at line %" PRId32 " column %" PRId32 "\n", value, line, column);
    fflush(stderr);
    abort();
}

void pas_byword_error(int64_t value, int32_t value_unsigned, int32_t line, int32_t column)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: RANGECK BYWORD argument %" PRIu64 " is outside 0..255 at line %" PRId32 " column %" PRId32 "\n", (uint64_t) value, line, column);
    else
        fprintf(stderr, "runtime error: RANGECK BYWORD argument %" PRId64 " is outside 0..255 at line %" PRId32 " column %" PRId32 "\n", value, line, column);
    fflush(stderr);
    abort();
}

void pas_case_error(int64_t value, int32_t value_unsigned, int32_t line, int32_t column)
{
    fflush(stdout);
    if (value_unsigned)
        fprintf(stderr, "runtime error: RANGECK CASE selector %" PRIu64 " has no matching label at line %" PRId32 " column %" PRId32 "\n", (uint64_t) value, line, column);
    else
        fprintf(stderr, "runtime error: RANGECK CASE selector %" PRId64 " has no matching label at line %" PRId32 " column %" PRId32 "\n", value, line, column);
    fflush(stderr);
    abort();
}

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
