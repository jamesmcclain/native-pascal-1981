/*
 * Runtime support for MOVESR.
 *
 * MOVESR is the SEGMENTED-address sibling of MOVER (manual: declared with
 * ADSMEM instead of ADRMEM parameters), NOT a "short count" variant. Both
 * source and destination are ADSMEM values, lowered to {flat pointer, segment
 * word} pairs; on this flat host the segment is always zero, so only the
 * pointer is used.
 *
 * Like MOVER, this is a backward (right-start, descending) byte copy. There is
 * no bounds checking.
 */

#include "pascalrt.h"

int movesr(adsmem src, adsmem dst, unsigned short len)
{
    unsigned short i;
    for (i = len; i > 0; i--) {
        dst.ptr[i - 1] = src.ptr[i - 1];
    }
    return 0;
}
