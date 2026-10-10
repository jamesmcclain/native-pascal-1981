#include <stdint.h>
#include <stddef.h>

#include "pascalrt.h"

/* Return the first matching absolute position at/after start, not an
 * offset relative to start. Never form start-1 until its domain is checked.
 * The manual's empty-pattern result is 1, independent of the start. */
int32_t positn_from(const char *haystack, int32_t haylen, const char *needle, int32_t needlelen, int32_t start)
{
    if (!haystack || !needle)
        return 0;
    if (needlelen < 0 || haylen < 0)
        return 0;
    if (needlelen == 0)
        return 1;
    if (start < 1 || start > haylen || needlelen > haylen)
        return 0;
    for (int32_t i = start - 1; i <= haylen - needlelen; ++i) {
        size_t j = 0;
        for (; j < (size_t) needlelen; ++j) {
            if ((unsigned char) haystack[i + (int32_t) j] != (unsigned char) needle[j])
                break;
        }
        if (j == (size_t) needlelen)
            return i + 1;
    }
    return 0;
}

/* Do not break the runtime ABI used by older generated code. */
int32_t positn(const char *haystack, int32_t haylen, const char *needle, int32_t needlelen)
{
    return positn_from(haystack, haylen, needle, needlelen, 1);
}
