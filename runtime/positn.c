#include <stdint.h>
#include <stddef.h>

#include "pascalrt.h"

/* Return 1-based position of needle in haystack, or 0 if not found. */
int32_t positn(const char *haystack, int32_t haylen, const char *needle, int32_t needlelen)
{
    if (!haystack || !needle)
        return 0;
    if (needlelen < 0 || haylen < 0)
        return 0;
    if (needlelen == 0)
        return 1;
    if (needlelen > haylen)
        return 0;
    for (int32_t i = 0; i <= haylen - needlelen; ++i) {
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
