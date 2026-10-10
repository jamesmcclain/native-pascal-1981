/* Stdin pointer READ (pas_read_ptr) accepts the same text as the file
 * reader (pas_fread_ptr), since both share pas_scan_ptr_token: padded and
 * high-half values read back, the stopping character stays unread, and an
 * overflowing value aborts instead of saturating. */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../runtime/pascalrt.h"

static int feed_stdin(const char *text)
{
    FILE *h = pas_project_tmpfile();
    if (!h) return 1;
    fputs(text, h);
    rewind(h);
    if (dup2(fileno(h), STDIN_FILENO) < 0) return 1;
    fclose(h);
    clearerr(stdin);
    return 0;
}

static int check_ok(const char *text, uint64_t expected, int next)
{
    if (feed_stdin(text)) return 1;
    uint64_t val = 0;
    int rc = pas_read_ptr(&val);
    int ch = getchar();
    if (rc != 0 || val != expected || ch != next) {
        fprintf(stderr, "pas_read_ptr: reading '%s' failed\n", text);
        return 1;
    }
    return 0;
}

/* A rejected value aborts the program, so read it in a child. */
static int check_abort(const char *text)
{
    fflush(NULL);
    pid_t pid = fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        freopen("/dev/null", "w", stderr);
        uint64_t val = 0;
        if (feed_stdin(text)) _exit(2);
        pas_read_ptr(&val);
        _exit(0);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) != pid) return 1;
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT) {
        fprintf(stderr, "pas_read_ptr: '%s' was not rejected\n", text);
        return 1;
    }
    return 0;
}

int main(void)
{
    if (check_ok("  1234;", 1234, ';') ||
        check_ok("\n0x1F,", 31, ',') ||
        check_ok("017 ", 15, ' ') ||
        check_ok("0000000000000000000000000000000012345 ", 012345, ' ') ||
        check_ok("0xffff800000000000 ", 0xffff800000000000ULL, ' ') ||
        check_ok("18446744073709551615;", UINT64_MAX, ';'))
        return 1;
    if (check_abort("18446744073709551616\n") ||
        check_abort("0x10000000000000000\n") ||
        check_abort("1234567890123456789012345678901234567890\n") ||
        check_abort("+x\n"))
        return 1;
    puts("PASS: stdin pointer READ shares the file reader's syntax and range");
    return 0;
}
