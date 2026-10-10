/* Test-only observation at a failed LSTRING length publication. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef EXPECTED_TARGET_TICKS
#define EXPECTED_TARGET_TICKS 1
#endif

static const unsigned char *slots;
static unsigned char before[8];
static unsigned target_ticks, source_ticks;

void Arm(void *p)
{
    slots = p;
    memcpy(before, p, sizeof before);
}

void TargetTick(void)
{
    ++target_ticks;
}

void SourceTick(void)
{
    ++source_ticks;
}

_Noreturn void __wrap_abort(void)
{
    if (!slots || memcmp(slots, before, sizeof before) != 0 || target_ticks != EXPECTED_TARGET_TICKS || source_ticks != 1) {
        fputs("FAIL: LEN modified destination or repeated target/source\n", stderr);
        _Exit(1);
    }
    puts("PASS: LEN destination unchanged; target and source evaluated once");
    fflush(stdout);
    _Exit(134);
}
