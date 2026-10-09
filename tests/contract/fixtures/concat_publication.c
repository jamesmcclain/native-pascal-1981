/* Test-only observation of the live CONCAT slot at its failure boundary. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char *slot;
static unsigned char before[4];
static unsigned ticks;

void Arm(void *p)
{
    slot = p;
    memcpy(before, p, sizeof before);
}

void Tick(void)
{
    ++ticks;
}

_Noreturn void __wrap_abort(void)
{
    if (!slot || memcmp(slot, before, sizeof before) != 0 || ticks != 1) {
        fputs("FAIL: CONCAT modified destination or repeated source\n", stderr);
        _Exit(1);
    }
    puts("PASS: CONCAT destination unchanged; source evaluated once");
    fflush(stdout);
    _Exit(134);
}
