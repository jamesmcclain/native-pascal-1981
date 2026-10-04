/* Linker-only failure injection; no production allocator hooks. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
struct descriptor { void *data; int64_t upper; };
extern struct descriptor slots[2];
extern int32_t evaluations, selections;
static struct descriptor saved[2];
static int armed, mode, calls;
void *__real_malloc(size_t size);
void __real_free(void *data);
void Arm(int32_t m)
{
    saved[0] = slots[0]; saved[1] = slots[1]; mode = m; armed = 1;
}
void *__wrap_malloc(size_t size)
{
    if (armed) {
        ++calls;
        if (mode != 5 || calls != 1 || size != 6) _Exit(99);
        return NULL;
    }
    return __real_malloc(size);
}
void __wrap_free(void *data)
{
    if (armed && data == saved[0].data) _Exit(99);
    __real_free(data);
}
_Noreturn void __wrap_abort(void)
{
    struct descriptor expected = mode == 6 ? (struct descriptor){NULL, 0} : saved[0];
    if (!armed || evaluations != 1 || selections != 1 || calls != (mode == 5) ||
        slots[0].data != expected.data || slots[0].upper != expected.upper ||
        slots[1].data != saved[1].data || slots[1].upper != saved[1].upper ||
        *(int16_t *)saved[0].data != 99) _Exit(99);
    puts("PASS: destination unchanged except bound-expression side effects");
    fflush(stdout);
    _Exit(134);
}
