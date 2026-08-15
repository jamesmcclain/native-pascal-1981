#include <stdint.h>

#include "pascalrt.h"

/*
 * SCANEQ / SCANNE: scan up to |L| characters of a string starting at the
 * 1-based position I, returning the signed count of characters scanned.
 *
 *   chars   - pointer to the FIRST character (position 1). This is NOT a
 *             length-prefixed buffer: STRING has no prefix, and the codegen
 *             passes the LSTRING character pointer (already past its prefix),
 *             so position i lives at chars[i - 1].
 *   length  - number of valid characters in `chars`.
 *   I       - 1-based starting position.
 *   stop_on_equal - 1 (SCANEQ) stops at the first character equal to P;
 *                   0 (SCANNE) stops at the first character not equal to P.
 *
 * A positive L scans forward and returns a non-negative count; a negative L
 * scans backward and returns a non-positive count. The previous version read
 * chars[0] as a length byte and indexed chars[idx], which started one
 * character late and mis-derived the length (and was meaningless for STRING).
 */
static int32_t scan_impl(int32_t L, char P, const char *chars, int32_t length, int32_t I, int32_t stop_on_equal)
{
    if (!chars || I < 1 || I > length || L == 0)
        return 0;

    int32_t skipped = 0;
    if (L > 0) {
        for (int32_t i = I; i <= length && skipped < L; ++i, ++skipped) {
            char ch = chars[i - 1];
            if ((stop_on_equal && ch == P) || (!stop_on_equal && ch != P))
                break;
        }
        return skipped;
    }
    /* L < 0: scan backward toward the start of the string. */
    for (int32_t i = I; i >= 1 && skipped > L; --i, --skipped) {
        char ch = chars[i - 1];
        if ((stop_on_equal && ch == P) || (!stop_on_equal && ch != P))
            break;
    }
    return skipped;
}

int32_t scaneq(int32_t L, char P, const char *chars, int32_t length, int32_t I, int32_t stop_on_equal)
{
    return scan_impl(L, P, chars, length, I, stop_on_equal);
}

/*
 * SCANNE and SCANEQ differ only in the stop condition, which the caller
 * already encodes in `stop_on_equal` (codegen passes 1 for SCANEQ, 0 for
 * SCANNE). An earlier version re-inverted that flag, making SCANNE behave
 * identically to SCANEQ; forward it unchanged.
 */
int32_t scanne(int32_t L, char P, const char *chars, int32_t length, int32_t I, int32_t stop_on_equal)
{
    return scan_impl(L, P, chars, length, I, stop_on_equal);
}
