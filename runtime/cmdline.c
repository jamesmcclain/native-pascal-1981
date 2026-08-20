/* cmdline.c -- vintage program-parameter command-line binding.
 *
 * IBM Pascal gives every program-heading parameter (other than INPUT and
 * OUTPUT) a value at program initialization by reading it from the command
 * line, prompting at the keyboard when the argument is absent (manual
 * 13-5..13-7). We reproduce that observable behavior -- not the internal IBM
 * routine names PPMUQQ/PPMFQQ/PPM -- by redirecting stdin to a one-token,
 * newline-terminated in-memory stream while one of the existing pas_read_*
 * parsers consumes a single parameter, then restoring the real stdin. When the
 * command line is exhausted we leave stdin alone and emit the documented
 * "<name>: " prompt, so the very same parsers read from the keyboard. This
 * keeps command-line and interactive parsing byte-for-byte identical.
 *
 * Positional model: program parameter 0 maps to argv[1], parameter 1 to
 * argv[2], and so on; INPUT/OUTPUT are not bound and do not occupy a position
 * (the code generator skips them before assigning indices).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static int g_argc = 0;
static char **g_argv = NULL;

/* Redirect state for the parameter currently being read (one at a time). */
static FILE *g_saved_stdin = NULL;      /* non-NULL only while redirected */
static FILE *g_mem = NULL;
static char *g_buf = NULL;

void pas_args_init(int argc, char **argv)
{
    g_argc = argc;
    g_argv = argv;
}

int pas_arg_count(void)
{
    return g_argc;
}

const char *pas_arg_value(int index)
{
    if (index < 0 || index >= g_argc || !g_argv) {
        return NULL;
    }
    return g_argv[index];
}

/* Return an allocated toolchain root path. Linux uses /proc/self/exe when it
 * is available. Other systems fall back to argv[0], then the current directory.
 * This function returns path data only; the Pascal driver selects stage paths. */
char *pas_toolchain_root(void)
{
    char path[PATH_MAX];
    char *slash;
    size_t length;

#ifdef __linux__
    ssize_t read_length = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (read_length > 0) {
        path[read_length] = '\0';
    } else
#endif
    {
        const char *argv0 = pas_arg_value(0);
        if (argv0 && strchr(argv0, '/')) {
            strncpy(path, argv0, sizeof(path) - 1);
            path[sizeof(path) - 1] = '\0';
        } else if (!getcwd(path, sizeof(path))) {
            return strdup(".");
        } else {
            return strdup(path);
        }
    }

    slash = strrchr(path, '/');
    if (!slash) {
        return strdup(".");
    }
    *slash = '\0';
    length = strlen(path);
    if (length >= 4 && strcmp(path + length - 4, "/bin") == 0) {
        path[length - 4] = '\0';
    }
    return strdup(path[0] ? path : "/");
}

/* Begin reading program parameter `param_index` (0-based; argv slot is
 * param_index + 1). If a command-line token is present, stdin is redirected to
 * it and 1 is returned. Otherwise a prompt is written to stdout and 0 is
 * returned, leaving stdin pointed at the keyboard so the caller's read prompts
 * the user. Always pair with pas_arg_end(). */
int pas_arg_begin(int param_index, const char *name)
{
    int slot = param_index + 1;
    if (g_argv && slot < g_argc && g_argv[slot]) {
        const char *tok = g_argv[slot];
        size_t n = strlen(tok);
        g_buf = (char *) malloc(n + 2);
        if (g_buf) {
            memcpy(g_buf, tok, n);
            g_buf[n] = '\n';    /* line marker the readers stop on */
            g_buf[n + 1] = '\0';
            g_mem = fmemopen(g_buf, n + 1, "r");
            if (g_mem) {
                g_saved_stdin = stdin;
                stdin = g_mem;
                return 1;
            }
            free(g_buf);
            g_buf = NULL;
        }
        /* Fall through to keyboard on allocation/stream failure. */
    }

    if (name && *name) {
        fputs(name, stdout);
        fputs(": ", stdout);
    }
    fflush(stdout);
    return 0;
}

/* Restore the real stdin (if it was redirected) and release the token stream. */
void pas_arg_end(void)
{
    if (g_saved_stdin) {
        stdin = g_saved_stdin;
        g_saved_stdin = NULL;
    }
    if (g_mem) {
        fclose(g_mem);
        g_mem = NULL;
    }
    if (g_buf) {
        free(g_buf);
        g_buf = NULL;
    }
}
