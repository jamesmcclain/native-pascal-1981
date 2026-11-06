/* Test-only observation at abort; no production compiler/runtime hooks. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char *slots[2];
static unsigned char before[2][6];
static unsigned ticks;

void Arm(void *p, void *q)
{
    slots[0] = p;
    slots[1] = q;
    memcpy(before[0], p, sizeof before[0]);
    memcpy(before[1], q, sizeof before[1]);
}

void Tick(void)
{
    ++ticks;
}

_Noreturn void __wrap_abort(void)
{
    if (!slots[0] || !slots[1] || ticks != 1 ||
        memcmp(slots[0], before[0], sizeof before[0]) != 0 ||
        memcmp(slots[1], before[1], sizeof before[1]) != 0) {
        fputs("FAIL: INSERT modified destination/neighbor or repeated source\n", stderr);
        _Exit(1);
    }
    puts("PASS: INSERT destination and neighbor unchanged; source evaluated once");
    fflush(stdout);
    _Exit(134);
}
