/* Linker-only failure injection for INITCK heap metadata (see
 * initck_heap.sh); no production allocator hooks. Arm() snapshots the
 * destinations; the abort wrapper then checks that the failed NEW published
 * nothing: both destinations unchanged, the old referents' state intact, and
 * the allocation that did succeed (if any) never registered. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "../runtime/pascalrt.h"

struct descriptor { void *data; int64_t upper; };
extern void *slot;
extern struct descriptor cells;
void *__real_malloc(size_t size);
void *__real_calloc(size_t count, size_t size);
static void *saved_slot, *fresh;
static struct descriptor saved_cells;
static int armed, mode, mallocs, callocs;

/* Modes: 1 ordinary NEW data, 2 its state, 3 SUPER NEW data, 4 its state,
 * 5 the registry table growing for an ordinary NEW. */
void Arm(int32_t m)
{
    saved_slot = slot;
    saved_cells = cells;
    mode = m;
    armed = 1;
}

void *__wrap_malloc(size_t size)
{
    if (armed) {
        ++mallocs;
        if (mode == 1 || mode == 3)
            return NULL;
        fresh = __real_malloc(size);
        return fresh;
    }
    return __real_malloc(size);
}

void *__wrap_calloc(size_t count, size_t size)
{
    if (armed) {
        ++callocs;
        if ((mode == 2 || mode == 4) && callocs == 1)
            return NULL;
        if (mode == 5 && callocs == 2)
            return NULL;
    }
    return __real_calloc(count, size);
}

_Noreturn void __wrap_abort(void)
{
    int ok = armed;
    armed = 0;
    ok = ok && mallocs == 1 && slot == saved_slot &&
        cells.data == saved_cells.data && cells.upper == saved_cells.upper;
    ok = ok && callocs == (mode == 1 || mode == 3 ? 0 : mode == 5 ? 2 : 1);
    /* The old referents keep their state: field v and element 1 written. */
    const unsigned char *s = pas_initck_heap(saved_slot, 2);
    ok = ok && s[0] == 1 && s[1] == 0;
    ok = ok && *pas_initck_heap_part(saved_cells.data, 2, 0, 1) == 1 &&
        *pas_initck_heap_part(saved_cells.data, 2, 1, 1) == 0;
    /* A successful data allocation was never registered: its lookup is
     * initialized scratch, not an unset registration. */
    if (fresh) {
        s = mode == 4 ? pas_initck_heap_part(fresh, 3, 0, 3) : pas_initck_heap(fresh, 2);
        ok = ok && s[0] == 1 && s[1] == 1;
    }
    if (!ok)
        _Exit(99);
    puts("PASS: nothing published or registered");
    fflush(stdout);
    _Exit(134);
}
