/*
 * Runtime support for MOVESL.
 *
 * MOVESL is the SEGMENTED-address sibling of MOVEL (manual: declared with
 * ADSMEM instead of ADRMEM parameters), NOT a "short count" variant. Both
 * source and destination are ADSMEM values, lowered to {flat pointer, segment
 * word} pairs; on this flat host the segment is always zero, so only the
 * pointer is used.
 *
 * Like MOVEL, this is a forward (left-start, ascending) byte copy, so for
 * overlapping regions it propagates left-to-right. There is no bounds checking.
 */

#include "pascalrt.h"

int movesl(adsmem src, adsmem dst, unsigned short len)
{
    unsigned short i;
    for (i = 0; i < len; i++) {
        dst.ptr[i] = src.ptr[i];
    }
    return 0;
}
