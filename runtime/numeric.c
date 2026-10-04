#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

/* Truncate a double toward zero into a 64-bit integer.
 *
 * Pascal's TRUNC cannot do this. It converts to this dialect's INTEGER
 * width, which is 16 bits, so TRUNC(40000.0) is a run-time range error
 * (pas_conversion_error below; it used to be LLVM poison).
 *
 * That mattered: the compiler's own constant folding used TRUNC to read an
 * integer literal's value, so every literal above 32767 was destroyed inside
 * the compiler rather than by any rule of the language.
 *
 * Values outside the destination range are clamped rather than converted,
 * since the conversion itself would be undefined behaviour in C too.
 */
long long pas_double_to_int64(double value)
{
    if (isnan(value))
        return 0;
    if (value >= 9223372036854775808.0)
        return 9223372036854775807LL;
    if (value <= -9223372036854775809.0)
        return -9223372036854775807LL - 1;
    return (long long) value;
}

/* Widen a 64-bit integer to a double.
 *
 * The dialect has no implicit INTEGER64-to-REAL conversion and its FLOAT()
 * accepts only a plain 16-bit INTEGER, so there is no way to write this in
 * Pascal. It is needed wherever a wide integer has to become a JSON number,
 * which is how the compiler's own stages pass a literal's value along.
 * Exact up to 2^53, as any double is.
 */
double pas_int64_to_double(long long value)
{
    return (double) value;
}

/* TRUNC/ROUND result outside INTEGER (-32768..32767), or a NaN argument.
 * IBM checks this unconditionally (manual 11-6: "Error if ABS(X) > MAXINT"),
 * so it is independent of MATHCK. kind: 0 TRUNC, 1 ROUND. value is the
 * argument; line/column are the function name's, 0:0 for a legacy AST.
 */
void pas_conversion_error(int32_t kind, double value, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: %s result out of INTEGER range at line %" PRId32 " column %" PRId32, kind ? "ROUND" : "TRUNC", line, column);
    /* A NaN's sign bit depends on how it was produced (and on -O). */
    if (isnan(value))
        fprintf(stderr, " (value=NaN)\n");
    else
        fprintf(stderr, " (value=%.17g)\n", value);
    fflush(stderr);
    abort();
}
