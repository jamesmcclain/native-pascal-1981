/*
 * Runtime support for MOVER.
 *
 * Manual: "Like MOVEL but starts at the RIGHT end of the strings." This is a
 * backward (descending-address) byte copy, the mirror of movel. As with movel
 * the direction is observable for overlapping regions, so this must not be
 * memmove. There is no bounds checking.
 */

#include "pascalrt.h"

int mover(char *src, char *dst, unsigned short len)
{
    unsigned short i;
    for (i = len; i > 0; i--) {
        dst[i - 1] = src[i - 1];
    }
    return 0;
}
