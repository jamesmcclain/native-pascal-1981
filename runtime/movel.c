/*
 * Runtime support for MOVEL.
 *
 * Manual: "Moves L characters (bytes) starting at S^ (source) to D^
 * (destination), starting at the LEFT end of the strings and continuing to the
 * right." This is a forward (ascending-address) byte copy. It must NOT be
 * memmove: for overlapping regions the forward direction is observable (e.g.
 * MOVEL(p, p+1, n) propagates the first byte across the buffer), and that
 * propagation is the defined behavior. There is no bounds checking.
 */

#include "pascalrt.h"

int movel(char *src, char *dst, unsigned short len)
{
    unsigned short i;
    for (i = 0; i < len; i++) {
        dst[i] = src[i];
    }
    return 0;
}
