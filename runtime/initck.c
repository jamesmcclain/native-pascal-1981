/* Host INITCK failure: called before touching uninitialized program bytes. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pascalrt.h"

/* Routine-boundary state side channel. Signatures never change: a Pascal
 * caller publishes, just before the call, a pointer to each tracked value
 * argument's i1 state; the callee prologue copies and clears each slot. NULL
 * (an uninstrumented caller, e.g. C) means "initialized". A callee publishes
 * its tracked scalar result's state in pas_initck_ret at each return; callers
 * reset it to 1 first so an uninstrumented callee reads as initialized.
 *
 * Handshake: a publishing caller also stores the callee's address in
 * pas_initck_callee and a pointer to its own acknowledgement flag (or NULL) in
 * pas_initck_ack. An instrumented callee trusts the slots only when the tag
 * names itself, and then sets the flag; either way it clears both. A slot
 * published for a C-implemented plain EXTERN therefore never reaches a Pascal
 * routine that C calls back, and the caller learns from an unset flag that the
 * callee was not instrumented (its VAR bindings and result were C's). */
_Thread_local void *pas_initck_args[PAS_INITCK_MAX_ARGS];
_Thread_local _Bool pas_initck_ret = 1;
_Thread_local void *pas_initck_callee;
_Thread_local _Bool *pas_initck_ack;

void pas_initck_fail(const char *what, const char *name, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: INITCK uninitialized %s %s", what, name);
    if (line > 0 && column > 0)
        fprintf(stderr, " at line %" PRId32 " column %" PRId32, line, column);
    fputc('\n', stderr);
    fflush(stderr);
    abort();
}

void pas_initck_error(const char *name, int32_t line, int32_t column)
{
    pas_initck_fail("local", name, line, column);
}

/* Aggregate shadows: one byte per scalar leaf (an LLVM i1 in memory), nonzero
 * when initialized. Lengths count leaves. None of these touch Pascal data. */
int32_t pas_initck_all(const unsigned char *s, int64_t n)
{
    for (int64_t i = 0; i < n; i++)
        if (!s[i])
            return 0;
    return 1;
}

/* An aggregate transfer: dst takes src's state, or every leaf unset when the
 * transfer itself consumed unset state (an unchecked index, say). A self-copy
 * is legal. */
void pas_initck_copy(unsigned char *dst, const unsigned char *src, int64_t n, int32_t ok)
{
    if (ok)
        memmove(dst, src, (size_t) n);
    else
        memset(dst, 0, (size_t) n);
}

/* Every leaf initialized (an untracked source) or unset. */
void pas_initck_fill(unsigned char *dst, int64_t n, int32_t ok)
{
    memset(dst, ok ? 1 : 0, (size_t) n);
}

/* After a call to a plain EXTERN that did not acknowledge the side channel:
 * C may have written the storage bound to a VAR/CONST formal. */
void pas_initck_release_unacked(unsigned char *dst, int64_t n, int32_t acked)
{
    if (!acked)
        memset(dst, 1, (size_t) n);
}

/* Callee prologue for a tracked aggregate value formal: copy the snapshot its
 * Pascal caller published, or treat an uninstrumented caller as initialized. */
void pas_initck_receive(unsigned char *own, const unsigned char *p, int64_t n)
{
    if (p)
        memcpy(own, p, (size_t) n);
    else
        memset(own, 1, (size_t) n);
}
