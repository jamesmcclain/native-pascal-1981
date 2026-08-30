#include <math.h>

#include "pascalrt.h"

/* Truncate a double toward zero into a 64-bit integer.
 *
 * Pascal's TRUNC cannot do this. It lowers to a float-to-int conversion at
 * this dialect's INTEGER width, which is 16 bits, so TRUNC(40000.0) is not
 * 40000 and TRUNC(100000.0) is not even a wrapped 100000 -- an out-of-range
 * float-to-int conversion is poison in LLVM, so the result is arbitrary.
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
