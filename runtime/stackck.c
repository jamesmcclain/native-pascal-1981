/* STACKCK runtime reporting (host, main thread).
 *
 * Codegen gives every host routine compiled under STACKCK+ the LLVM function
 * attribute "probe-stack"="inline-asm". The backend then touches a large
 * frame page by page while it reserves it, so the frame can never jump over
 * the guard area below the main thread's stack: stack exhaustion becomes a
 * fault at the first page past the stack limit, before any later stack use.
 *
 * pas_stackck_init, called at program (and unit) start when the compiland has
 * a STACKCK+ routine, installs a SIGSEGV handler on an alternate signal stack,
 * so reporting does not need the exhausted stack. The handler reports a fault
 * as a stack overflow only when the fault address lies just below (or inside)
 * the main thread's stack extent and near the interrupted stack pointer.
 * Any other SIGSEGV (a wild pointer, a worker thread, a fault inside the
 * report itself) gets the default action back and re-faults as before.
 *
 * IBM Appendix A error 2000 ("Overflow") is the historical class; as with the
 * other runtime errors the message carries no IBM error number.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <ucontext.h>
#include <unistd.h>

#include "pascalrt.h"

/* How far outside the recorded extent, and from the interrupted stack
 * pointer, a fault may lie and still count as stack exhaustion. Probed
 * frames fault within one page of the stack pointer; the margin also admits
 * a small unprobed frame's accesses and the kernel's growth granularity. */
#define STACKCK_SLACK ((uintptr_t) 64 * 1024)
#define STACKCK_ALTSTACK_SIZE (64 * 1024)

static const char stackck_message[] = "runtime error: STACKCK stack overflow\n";

static uintptr_t stack_lo;      /* lowest address the main stack may use */
static uintptr_t stack_hi;      /* one past its highest address */
static volatile sig_atomic_t stackck_installed;
static volatile sig_atomic_t stackck_reporting;
static char stackck_altstack[STACKCK_ALTSTACK_SIZE] __attribute__((aligned(16)));

static void stackck_write_message(void)
{
    const char *p = stackck_message;
    size_t left = sizeof stackck_message - 1;
    while (left > 0) {
        ssize_t n = write(2, p, left);
        if (n <= 0)
            break;
        p += n;
        left -= (size_t) n;
    }
}

static int stackck_is_overflow(const siginfo_t *info, const void *context)
{
    uintptr_t addr = (uintptr_t) info->si_addr;
    if (stack_hi == 0 || addr >= stack_hi)
        return 0;
    if (addr + STACKCK_SLACK < stack_lo)
        return 0;
#if defined(__x86_64__)
    {
        const ucontext_t *uc = (const ucontext_t *) context;
        uintptr_t sp = (uintptr_t) uc->uc_mcontext.gregs[REG_RSP];
        if (sp >= stack_hi || sp + STACKCK_SLACK < stack_lo)
            return 0;           /* not running on the main stack */
        if (addr + STACKCK_SLACK < sp || addr > sp + STACKCK_SLACK)
            return 0;           /* not a stack access at the stack pointer */
    }
#else
    (void) context;
#endif
    /* Below the current mapping: the stack could not grow there. */
    return 1;
}

static void stackck_handler(int sig, siginfo_t *info, void *context)
{
    if (stackck_reporting) {
        /* A fault while flushing stdout: the line still gets out. */
        stackck_write_message();
        abort();
    }
    if (!stackck_is_overflow(info, context)) {
        /* Not ours: restore the default action and let the faulting
         * instruction run again, so it ends exactly as without STACKCK. */
        signal(sig, SIG_DFL);
        return;
    }
    stackck_reporting = 1;
    /* Same order as the other runtime errors: earlier output first. This
     * is best effort -- the overflow may have struck inside stdio. A
     * nested fault re-enters above (SA_NODEFER) and still reports. */
    fflush(stdout);
    stackck_write_message();
    abort();
}

/* Parse one hexadecimal field of a /proc/self/maps line. */
static const char *stackck_hex(const char *p, uintptr_t *out)
{
    uintptr_t v = 0;
    for (;; p++) {
        unsigned d;
        if (*p >= '0' && *p <= '9')
            d = (unsigned) (*p - '0');
        else if (*p >= 'a' && *p <= 'f')
            d = (unsigned) (*p - 'a' + 10);
        else
            break;
        v = v * 16 + d;
    }
    *out = v;
    return p;
}

/* The main thread's usable stack: the mapping that holds the current stack
 * pointer, extended down by RLIMIT_STACK but never below the end of the
 * mapping before it -- what glibc's pthread_getattr_np computes for the main
 * thread. Read with open/read into a fixed buffer, not stdio: the reporter
 * runs before main and must leave the heap exactly as it found it. */
static int stackck_find_stack(uintptr_t *lo, uintptr_t *hi)
{
    char buf[4096];
    char line[512];
    size_t used = 0;
    uintptr_t here = (uintptr_t) __builtin_frame_address(0);
    uintptr_t prev_end = 0;
    struct rlimit rl;
    int fd, found = 0;
    ssize_t n;

    fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    while (!found && (n = read(fd, buf, sizeof buf)) > 0) {
        for (ssize_t i = 0; i < n && !found; i++) {
            if (buf[i] != '\n') {
                if (used < sizeof line - 1)
                    line[used++] = buf[i];
                continue;
            }
            line[used] = '\0';
            used = 0;
            uintptr_t start, end;
            const char *q = stackck_hex(line, &start);
            if (*q != '-')
                continue;
            stackck_hex(q + 1, &end);
            if (start <= here && here < end) {
                *hi = end;
                *lo = prev_end;
                found = 1;
            } else
                prev_end = end;
        }
    }
    close(fd);
    if (!found)
        return 0;
    if (getrlimit(RLIMIT_STACK, &rl) == 0 && rl.rlim_cur != RLIM_INFINITY && rl.rlim_cur < *hi && *hi - rl.rlim_cur > *lo)
        *lo = *hi - rl.rlim_cur;
    return 1;
}

void pas_stackck_init(void)
{
    stack_t ss;
    struct sigaction sa;
    uintptr_t lo, hi;

    if (stackck_installed)
        return;
    stackck_installed = 1;

    if (!stackck_find_stack(&lo, &hi))
        return;
    stack_lo = lo;
    stack_hi = hi;

    memset(&ss, 0, sizeof ss);
    ss.ss_sp = stackck_altstack;
    ss.ss_size = sizeof stackck_altstack;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) != 0) {
        stack_hi = 0;
        return;
    }

    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = stackck_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGSEGV, &sa, NULL) != 0)
        stack_hi = 0;
}
