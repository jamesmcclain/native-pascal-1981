#include <stdint.h>

/* UNIT esplit's INTERFACE declares Helper EXTERN; neither the interface nor
   the implementation defines it, so it is supplied here.  INTEGER32 lowers
   to i32. */
int32_t Helper(int32_t x)
{
    return x * 10;
}
