/* IBM library functions UADDOK, SADDOK, UMULOK, SMULOK (manual 11-21).
 *
 * The manual says these are not predeclared: a program declares them, e.g.
 *     FUNCTION SADDOK(A, B: INTEGER; VAR C: INTEGER): BOOLEAN; EXTERN;
 * Undeclared, the compiler lowers them inline as builtins; these definitions
 * serve such EXTERN declarations, spelled as in the manual (EXTERN names
 * keep their source case). Each stores the 16-bit sum or product, wrapped,
 * through C and returns true when it did not overflow. They never trap.
 *
 * A and B arrive as i16 values; only their low 16 bits are read, so no
 * caller-side extension is assumed.
 */
#include <stdbool.h>
#include <stdint.h>

#include "pascalrt.h"

static int32_t low_signed(uint32_t v)
{
    return (int32_t) (int16_t) (uint16_t) v;
}

bool SADDOK(uint32_t a, uint32_t b, int16_t *c)
{
    int32_t r = low_signed(a) + low_signed(b);
    *c = (int16_t) (uint16_t) r;
    return r >= INT16_MIN && r <= INT16_MAX;
}

bool SMULOK(uint32_t a, uint32_t b, int16_t *c)
{
    int32_t r = low_signed(a) * low_signed(b);
    *c = (int16_t) (uint16_t) r;
    return r >= INT16_MIN && r <= INT16_MAX;
}

bool UADDOK(uint32_t a, uint32_t b, uint16_t *c)
{
    uint32_t r = (a & 0xFFFFu) + (b & 0xFFFFu);
    *c = (uint16_t) r;
    return r <= UINT16_MAX;
}

bool UMULOK(uint32_t a, uint32_t b, uint16_t *c)
{
    uint32_t r = (a & 0xFFFFu) * (b & 0xFFFFu);
    *c = (uint16_t) r;
    return r <= UINT16_MAX;
}
