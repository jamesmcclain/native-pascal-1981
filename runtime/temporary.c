/* Compiler-owned temporaries. Cleanup never traverses the shared namespace.
 * The signal path uses only async-signal-safe calls and pre-recorded paths. */
#define _GNU_SOURCE
#include "pascalrt.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define TEMP_ROOT "/tmp/native-pascal-1981"
#define MAX_TEMP_FILES 512
static char workspace[128];
static char files[MAX_TEMP_FILES][160];
static volatile sig_atomic_t file_count;
static pid_t owner;

const char *pas_project_temp_root(void)
{
    struct stat st;
    if (mkdir(TEMP_ROOT, 0700) != 0 && errno != EEXIST)
        return NULL;
    if (lstat(TEMP_ROOT, &st) != 0)
        return NULL;
    if (!S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 0022)) {
        errno = EACCES;
        return NULL;
    }
    return TEMP_ROOT;
}

static void cleanup(void)
{
    int i;
    if (getpid() != owner)
        return;
    for (i = 0; i < file_count; ++i)
        unlink(files[i]);
    if (workspace[0])
        rmdir(workspace);
}

static void terminate(int sig)
{
    cleanup();
    _exit(128 + sig);
}

/* Return an already-created .ll or .o pathname, or NULL on failure. All
 * allocations are recorded before signals are unblocked. Forked pipeline
 * children inherit the table, but must never delete the parent's files. */
char *pas_driver_temp_file(const char *suffix)
{
    sigset_t blocked, previous;
    struct sigaction action;
    const char *base;
    char *result = NULL;
    int fd;
    if (!suffix || (strcmp(suffix, ".ll") && strcmp(suffix, ".o"))) {
        errno = EINVAL;
        return NULL;
    }
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGHUP);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGTERM);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) != 0)
        return NULL;
    if (!workspace[0]) {
        base = pas_project_temp_root();
        if (!base)
            goto done;
        snprintf(workspace, sizeof(workspace), "%s/driver.XXXXXXXXXX", base);
        if (!mkdtemp(workspace)) {
            workspace[0] = '\0';
            goto done;
        }
        owner = getpid();
        if (atexit(cleanup) != 0) {
            cleanup();
            workspace[0] = '\0';
            goto done;
        }
        memset(&action, 0, sizeof(action));
        action.sa_handler = terminate;
        action.sa_mask = blocked;
        sigaction(SIGHUP, &action, NULL);
        sigaction(SIGINT, &action, NULL);
        sigaction(SIGTERM, &action, NULL);
    }
    if (file_count >= MAX_TEMP_FILES) {
        errno = ENOSPC;
        goto done;
    }
    result = files[file_count];
    snprintf(result, sizeof(files[0]), "%s/artifact.XXXXXX%s", workspace, suffix);
    fd = mkstemps(result, (int) strlen(suffix));
    if (fd < 0) {
        result = NULL;
        goto done;
    }
    ++file_count;
    close(fd);
  done:
    sigprocmask(SIG_SETMASK, &previous, NULL);
    return result;
}

/* Anonymous Pascal FILE storage: unlink before returning, so fclose, process
 * exit, and even fatal signals leave no pathname behind. Block catchable
 * termination while the very short-lived names are being allocated. */
FILE *pas_project_tmpfile(void)
{
    sigset_t blocked, previous;
    const char *base;
    char directory[128];
    char path[160];
    int fd = -1;
    FILE *stream;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGHUP);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGTERM);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) != 0)
        return NULL;
    base = pas_project_temp_root();
    if (base) {
        snprintf(directory, sizeof(directory), "%s/file.XXXXXXXXXX", base);
        if (mkdtemp(directory)) {
            snprintf(path, sizeof(path), "%s/data.XXXXXX", directory);
            fd = mkstemp(path);
            if (fd >= 0 && unlink(path) != 0) {
                close(fd);
                fd = -1;
                unlink(path);
            }
            rmdir(directory);
        }
    }
    sigprocmask(SIG_SETMASK, &previous, NULL);
    if (fd < 0)
        return NULL;
    stream = fdopen(fd, "w+b");
    if (!stream)
        close(fd);
    return stream;
}
