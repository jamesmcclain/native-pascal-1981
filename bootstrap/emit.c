#include "pasboot.h"
int translate(Compiland *c, FILE *out, int check_only)
{
    (void) c;
    (void) out;
    return check_only ? 0 : 1;
}
