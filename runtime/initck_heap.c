/* INITCK state of heap referents. Signatures and pointer representation
 * never change: a successful NEW of a tracked type registers its data address
 * with one byte per scalar leaf (nonzero when initialized), and a dereference
 * looks the address up to find that state. Nothing here touches Pascal data.
 *
 * An address that is not registered (memory from C, RETYPEd or foreign
 * pointers) or whose registration does not match the expected leaf count (the
 * pointer has been reinterpreted as another type) is untracked storage: the
 * lookup returns a run of initialized leaves, so a fresh lookup never fails a
 * checked read. A referent whose address escaped to untracked effects (ADR,
 * a conversion to ADRMEM or another pointer type, a [C] call) is released:
 * it reads as untracked until it is disposed or its address is registered
 * again.
 *
 * Compiled code passes each lookup site's own fallback buffer (in the
 * caller's frame) for that run, so aliases bound at different sites (two
 * VAR actuals, a WITH and a VAR actual) never share state bytes: an unchecked
 * write through one cannot fail a checked read through the other. The
 * fallback-less entry points serve code generated before the _at forms and
 * share one per-thread scratch run. */
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pascalrt.h"

struct heap_entry {
    const void *key;            /* NULL: empty; TOMBSTONE: deleted */
    unsigned char *shadow;
    int64_t n;
    int released;
};

#define TOMBSTONE ((const void *) 1)

static struct heap_entry *table;
static size_t capacity;         /* a power of two, or 0 */
static size_t occupied;         /* live entries plus tombstones */
static atomic_flag table_lock = ATOMIC_FLAG_INIT;

static void lock(void)
{
    while (atomic_flag_test_and_set_explicit(&table_lock, memory_order_acquire));
}

static void unlock(void)
{
    atomic_flag_clear_explicit(&table_lock, memory_order_release);
}

static _Noreturn void heap_error(const char *reason)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: INITCK heap state %s\n", reason);
    fflush(stderr);
    abort();
}

static size_t slot_of(const void *key, size_t cap)
{
    uint64_t h = (uint64_t) (uintptr_t) key;
    h ^= h >> 33;
    h *= UINT64_C(0xff51afd7ed558ccd);
    h ^= h >> 33;
    return (size_t) h & (cap - 1);
}

/* The entry for key, or NULL. Caller holds the lock. */
static struct heap_entry *find(const void *key)
{
    if (!capacity || !key || key == TOMBSTONE)
        return NULL;
    for (size_t i = slot_of(key, capacity);; i = (i + 1) & (capacity - 1)) {
        if (table[i].key == key)
            return &table[i];
        if (!table[i].key)
            return NULL;
    }
}

/* Grow (or compact) so one more key fits. Caller holds the lock. Fails
 * without changing anything when the new table cannot be allocated. */
static int reserve(void)
{
    if ((occupied + 1) * 4 <= capacity * 3)
        return 1;
    size_t live = 0;
    for (size_t i = 0; i < capacity; i++)
        if (table[i].key && table[i].key != TOMBSTONE)
            live++;
    size_t cap = capacity ? capacity : 64;
    while ((live + 1) * 2 > cap)
        cap *= 2;
    struct heap_entry *fresh = calloc(cap, sizeof *fresh);
    if (!fresh)
        return 0;
    for (size_t i = 0; i < capacity; i++)
        if (table[i].key && table[i].key != TOMBSTONE) {
            size_t j = slot_of(table[i].key, cap);
            while (fresh[j].key)
                j = (j + 1) & (cap - 1);
            fresh[j] = table[i];
        }
    free(table);
    table = fresh;
    capacity = cap;
    occupied = live;
    return 1;
}

/* After a successful allocation, before the pointer is published: data's n
 * leaves start unset. A stale registration at the same address (memory
 * freed by untracked code and reused) is replaced. Failing to record the
 * state aborts before publication, so no pointer or state is published. */
void pas_initck_heap_new(const void *data, int64_t n)
{
    if (!data || n <= 0)
        return;
    unsigned char *shadow = calloc((size_t) n, 1);
    if (!shadow)
        heap_error("allocation failed");
    lock();
    struct heap_entry *e = find(data);
    if (e) {
        free(e->shadow);
    } else {
        if (!reserve()) {
            unlock();
            heap_error("allocation failed");
        }
        size_t i = slot_of(data, capacity);
        while (table[i].key && table[i].key != TOMBSTONE)
            i = (i + 1) & (capacity - 1);
        if (!table[i].key)
            occupied++;
        e = &table[i];
        e->key = data;
    }
    e->shadow = shadow;
    e->n = n;
    e->released = 0;
    unlock();
}

/* Scratch for untracked referents: n initialized leaves. Outgrown buffers
 * are kept, since an alias (VAR or WITH binding) may still refer to one. */
static _Thread_local unsigned char *scratch;
static _Thread_local int64_t scratch_n;

static unsigned char *untracked(int64_t n)
{
    if (n < 0)
        n = 0;
    if (n > scratch_n || !scratch) {
        int64_t want = n > 2 * scratch_n ? n : 2 * scratch_n;
        if (want < 64)
            want = 64;
        unsigned char *fresh = malloc((size_t) want);
        if (!fresh)
            heap_error("allocation failed");
        scratch = fresh;
        scratch_n = want;
    }
    memset(scratch, 1, (size_t) n);
    return scratch;
}

/* fallback (n initialized leaves) when given, else shared scratch. */
static unsigned char *untracked_at(unsigned char *fallback, int64_t n)
{
    if (!fallback)
        return untracked(n);
    if (n > 0)
        memset(fallback, 1, (size_t) n);
    return fallback;
}

/* The state of the n-leaf referent at data; an untracked referent's
 * initialized leaves are written to fallback, n bytes, and returned. */
unsigned char *pas_initck_heap_at(const void *data, int64_t n, unsigned char *fallback)
{
    unsigned char *shadow = NULL;
    lock();
    struct heap_entry *e = find(data);
    if (e && !e->released && e->n == n)
        shadow = e->shadow;
    unlock();
    return shadow ? shadow : untracked_at(fallback, n);
}

unsigned char *pas_initck_heap(const void *data, int64_t n)
{
    return pas_initck_heap_at(data, n, NULL);
}

/* The count leaves at offset within the n-leaf referent at data: one SUPER
 * ARRAY element. A part outside the registered leaves (an unchecked index
 * out of range, or a descriptor whose upper bound no longer matches the
 * allocation) is untracked, so the instrumentation never touches state
 * beyond the allocation's own. */
unsigned char *pas_initck_heap_part_at(const void *data, int64_t n, int64_t offset, int64_t count, unsigned char *fallback)
{
    unsigned char *shadow = NULL;
    lock();
    struct heap_entry *e = find(data);
    if (e && !e->released && e->n == n && offset >= 0 && count >= 0 && offset <= n - count)
        shadow = e->shadow + offset;
    unlock();
    return shadow ? shadow : untracked_at(fallback, count);
}

unsigned char *pas_initck_heap_part(const void *data, int64_t n, int64_t offset, int64_t count)
{
    return pas_initck_heap_part_at(data, n, offset, count, NULL);
}

/* DISPOSE, before the allocation is freed: forget its state, so whatever
 * reuses the address (a later NEW registers afresh; memory from C stays
 * unregistered) never inherits it. Not a use-after-free detector: a dangling
 * pointer then reads as untracked storage, or sees a later NEW's state if
 * that NEW reused the address. An alias bound to the old state before the
 * DISPOSE (WITH, VAR) is as dangling as the data it denotes. */
void pas_initck_heap_dispose(const void *data)
{
    unsigned char *shadow = NULL;
    lock();
    struct heap_entry *e = find(data);
    if (e) {
        shadow = e->shadow;
        e->key = TOMBSTONE;
        e->shadow = NULL;
        e->n = 0;
        e->released = 0;
    }
    unlock();
    free(shadow);
}

/* data's referent escaped to untracked effects: every leaf counts as
 * initialized, and later lookups treat it as untracked storage. */
void pas_initck_heap_release(const void *data)
{
    lock();
    struct heap_entry *e = find(data);
    if (e && !e->released) {
        memset(e->shadow, 1, (size_t) e->n);
        e->released = 1;
    }
    unlock();
}
