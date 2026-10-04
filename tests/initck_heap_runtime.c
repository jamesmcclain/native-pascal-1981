/* Unit test of the INITCK heap registry (runtime/initck_heap.c): state is
 * keyed by data address; lookups never hand out state beyond a registered
 * allocation; unregistered, mismatched and released referents read as
 * initialized scratch. Only metadata is inspected, never Pascal data. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "../runtime/pascalrt.h"

static int all(const unsigned char *s, int64_t n, unsigned char v)
{
    for (int64_t i = 0; i < n; i++)
        if (s[i] != v)
            return 0;
    return 1;
}

int main(void)
{
    static char blocks[256][8];
    char other[8];

    /* A fresh registration is wholly unset; writes stick. */
    pas_initck_heap_new(blocks[0], 3);
    unsigned char *s = pas_initck_heap(blocks[0], 3);
    assert(all(s, 3, 0));
    s[1] = 1;
    assert(pas_initck_heap(blocks[0], 3)[1] == 1);

    /* A lookup with another leaf count (a reinterpreted pointer) or of an
     * unregistered address is untracked scratch, initialized. */
    unsigned char *m = pas_initck_heap(blocks[0], 2);
    assert(m != s && all(m, 2, 1));
    assert(all(pas_initck_heap(other, 5), 5, 1));
    assert(all(pas_initck_heap(NULL, 4), 4, 1));

    /* Element parts stay within the allocation. */
    pas_initck_heap_new(blocks[1], 6);
    unsigned char *base = pas_initck_heap(blocks[1], 6);
    assert(pas_initck_heap_part(blocks[1], 6, 4, 2) == base + 4);
    assert(pas_initck_heap_part(blocks[1], 6, 0, 2) == base);
    unsigned char *out = pas_initck_heap_part(blocks[1], 6, 6, 2);
    assert(out < base || out >= base + 6);
    assert(all(out, 2, 1));
    out = pas_initck_heap_part(blocks[1], 6, -2, 2);
    assert((out < base || out >= base + 6) && all(out, 2, 1));
    out = pas_initck_heap_part(blocks[1], 6, 5, 2);
    assert((out < base || out >= base + 6) && all(out, 2, 1));
    out = pas_initck_heap_part(blocks[1], 8, 0, 2);
    assert((out < base || out >= base + 6) && all(out, 2, 1));
    out = pas_initck_heap_part(blocks[1], 6, INT64_MAX, 2);
    assert(all(out, 2, 1));

    /* Scratch is refilled: an earlier write to it never leaks. */
    out[0] = 0;
    assert(all(pas_initck_heap(other, 2), 2, 1));

    /* Re-registration at the same address replaces stale state. */
    base[0] = 1;
    pas_initck_heap_new(blocks[1], 6);
    assert(all(pas_initck_heap(blocks[1], 6), 6, 0));

    /* A release initializes every leaf and makes later lookups untracked
     * until the address is registered again. */
    unsigned char *held = pas_initck_heap(blocks[1], 6);
    pas_initck_heap_release(blocks[1]);
    assert(all(held, 6, 1));
    held[2] = 0;
    assert(all(pas_initck_heap(blocks[1], 6), 6, 1));
    assert(all(pas_initck_heap_part(blocks[1], 6, 2, 1), 1, 1));
    pas_initck_heap_release(other);
    pas_initck_heap_new(blocks[1], 6);
    assert(all(pas_initck_heap(blocks[1], 6), 6, 0));

    /* DISPOSE retires state: the address then reads as untracked, a
     * retired address can be registered afresh, and retiring unknown or
     * released addresses is harmless. */
    pas_initck_heap_new(blocks[2], 4);
    pas_initck_heap_dispose(blocks[2]);
    assert(all(pas_initck_heap(blocks[2], 4), 4, 1));
    assert(all(pas_initck_heap_part(blocks[2], 4, 0, 1), 1, 1));
    pas_initck_heap_dispose(blocks[2]);
    pas_initck_heap_dispose(other);
    pas_initck_heap_dispose(NULL);
    pas_initck_heap_new(blocks[2], 4);
    assert(all(pas_initck_heap(blocks[2], 4), 4, 0));
    pas_initck_heap_release(blocks[2]);
    pas_initck_heap_dispose(blocks[2]);
    pas_initck_heap_new(blocks[2], 4);
    assert(all(pas_initck_heap(blocks[2], 4), 4, 0));
    pas_initck_heap_dispose(blocks[2]);

    /* Many registrations: the table grows and keeps every entry, also
     * across retirements (tombstones). */
    for (int i = 2; i < 256; i++)
        pas_initck_heap_new(blocks[i], 1 + i % 7);
    for (int i = 2; i < 256; i++) {
        unsigned char *e = pas_initck_heap(blocks[i], 1 + i % 7);
        assert(all(e, 1 + i % 7, 0));
        e[0] = 1;
    }
    for (int i = 2; i < 256; i++)
        assert(pas_initck_heap(blocks[i], 1 + i % 7)[0] == 1);
    for (int round = 0; round < 50; round++)
        for (int i = 2; i < 256; i += 2) {
            pas_initck_heap_dispose(blocks[i]);
            pas_initck_heap_new(blocks[i], 1 + i % 7);
        }
    for (int i = 2; i < 256; i++)
        assert(pas_initck_heap(blocks[i], 1 + i % 7)[0] == (i % 2 ? 1 : 0));

    /* A large untracked request after small ones keeps earlier scratch
     * buffers valid (an alias may still refer to one). */
    unsigned char *small = pas_initck_heap(other, 3);
    unsigned char *big = pas_initck_heap(other, 100000);
    assert(all(big, 100000, 1));
    small[0] = 1;

    /* The _at forms put an untracked referent's leaves in the caller's
     * fallback, so lookups from different sites never share state; a
     * tracked referent ignores it. A released referent is untracked. */
    unsigned char fa[4], fb[4];
    unsigned char *ua = pas_initck_heap_at(other, 4, fa);
    unsigned char *ub = pas_initck_heap_at(&other[1], 4, fb);
    assert(ua == fa && ub == fb && all(fa, 4, 1) && all(fb, 4, 1));
    ua[0] = 0;
    assert(all(ub, 4, 1));
    pas_initck_heap_new(blocks[0], 4);
    assert(pas_initck_heap_at(blocks[0], 4, fa) != fa);
    assert(pas_initck_heap_part_at(blocks[0], 4, 2, 2, fa) == pas_initck_heap(blocks[0], 4) + 2);
    pas_initck_heap_release(blocks[0]);
    ua = pas_initck_heap_at(blocks[0], 4, fa);
    ub = pas_initck_heap_part_at(blocks[0], 4, 4, 2, fb);
    assert(ua == fa && ub == fb && all(fa, 4, 1) && all(fb, 2, 1));

    puts("PASS: INITCK heap registry runtime");
    return 0;
}
