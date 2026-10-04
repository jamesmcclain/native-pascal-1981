#include <stdint.h>

/* The half of UNIT vsplit's INTERFACE that its Pascal IMPLEMENTATION
   declares EXTERN rather than defining.  INTEGER32 lowers to i32. */
int32_t Helper(int32_t x)
{
    return x * 10;
}
