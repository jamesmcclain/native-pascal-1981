/*
 * Runtime support for FILLSC.
 *
 * FILLSC is the SEGMENTED-address sibling of FILLC (manual: "the corresponding
 * segmented address versions of these routines, called MOVESL, MOVESR, and
 * FILLSC, ... are declared with ADSMEM instead of ADRMEM parameters"). The
 * destination is therefore an ADSMEM value, which this compiler lowers to a
 * {flat pointer, segment word} pair. On this flat host the segment is always
 * zero, so only the pointer is used; the field is still received intact.
 *
 * Fills `len` bytes at the destination with the byte `val` (as FILLC). There is
 * no bounds checking.
 */

#include "pascalrt.h"

int fillsc(adsmem dst, unsigned short len, char val)
{
    unsigned short i;
    for (i = 0; i < len; i++) {
        dst.ptr[i] = val;
    }
    return 0;
}
