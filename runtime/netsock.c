/* netsock.c -- TCP sockets for Pascal programs.
 *
 * Everything awkward about the BSD socket API stays on this side of the
 * boundary: struct sockaddr layout, byte order, getaddrinfo's linked list,
 * and the errno retry dances. What crosses into Pascal is only file
 * descriptors, byte buffers with explicit lengths, and small integers, which
 * is all the dialect can express comfortably -- it has no way to declare a
 * struct sockaddr_in with a guaranteed layout, and no way to take the address
 * of a record field.
 *
 * Conventions used throughout:
 *   - Every function returning a descriptor returns -1 on failure.
 *   - Every transfer function takes an explicit length and never relies on
 *     NUL termination; an HTTP body is arbitrary bytes and may contain NULs.
 *   - Read returns >= 0 for bytes transferred (0 meaning the peer closed),
 *     PAS_SOCK_ERROR for a failure, and PAS_SOCK_TIMEOUT when the deadline
 *     passed with nothing to read. A caller that cannot tell "timed out" from
 *     "connection closed" cannot implement an upstream timeout correctly.
 *   - EINTR is retried everywhere rather than surfaced.
 */

#include "pascalrt.h"

#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* Resolve host/port to a list of candidate addresses. A NULL or empty host
 * means "any interface" for a listener. Port is formatted rather than passed
 * as a number because getaddrinfo takes a service string. */
static struct addrinfo *resolve(const char *host, int port, int passive)
{
    struct addrinfo hints;
    struct addrinfo *out = NULL;
    char service[16];

    if (port < 0 || port > 65535) {
        return NULL;
    }
    snprintf(service, sizeof(service), "%d", port);

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;  /* IPv4 only: the dialect side has no
                                 * need for scoped IPv6 literals, and
                                 * this keeps the surface small. */
    hints.ai_socktype = SOCK_STREAM;
    if (passive) {
        hints.ai_flags = AI_PASSIVE;
    }
    if (getaddrinfo((host && *host) ? host : NULL, service, &hints, &out) != 0) {
        return NULL;
    }
    return out;
}

void pas_net_init(void)
{
    /* A client that goes away mid-response makes the next write raise
     * SIGPIPE, whose default action is to kill the process -- so one
     * disconnecting client would take down the whole server. Ignoring it
     * turns that into a plain EPIPE from write(), which the caller can see.
     *
     * Deliberately *not* touching SIGCHLD here: that is a separate decision
     * with a visible side effect (see pas_net_autoreap), and folding it in
     * would silently break any caller that waits on its children.
     */
    signal(SIGPIPE, SIG_IGN);
}

void pas_net_autoreap(void)
{
    /* SIG_IGN on SIGCHLD makes exited children disappear rather than becoming
     * zombies, which is what a fork-per-connection server wants: it never
     * needs a child's exit status, and reaping by hand would mean an explicit
     * waitpid sweep in the accept loop.
     *
     * The cost is that waitpid() can no longer find a specific child -- it
     * fails with ECHILD -- so this is a separate call rather than part of
     * pas_net_init, and a program that wants exit statuses simply does not
     * make it.
     */
    signal(SIGCHLD, SIG_IGN);
}

int pas_tcp_listen(const char *host, int port, int backlog)
{
    struct addrinfo *addrs = resolve(host, port, 1);
    struct addrinfo *ai;
    int fd = -1;
    int on = 1;

    if (!addrs) {
        return -1;
    }
    for (ai = addrs; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            continue;
        }
        /* Without SO_REUSEADDR a restart within the TIME_WAIT window fails
         * with EADDRINUSE, which for a server people stop and start by hand
         * is the common case rather than the rare one. */
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
        if (bind(fd, ai->ai_addr, ai->ai_addrlen) == 0 && listen(fd, backlog > 0 ? backlog : 64) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(addrs);
    return fd;
}

/* The port actually bound. With port 0 the kernel picks one, which is how a
 * test can listen without hard-coding a port that might be in use. */
int pas_tcp_port(int fd)
{
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);

    if (fd < 0 || getsockname(fd, (struct sockaddr *) &addr, &len) != 0) {
        return -1;
    }
    return (int) ntohs(addr.sin_port);
}

int pas_tcp_accept(int listen_fd)
{
    int fd;

    if (listen_fd < 0) {
        return -1;
    }
    do {
        fd = accept(listen_fd, NULL, NULL);
    } while (fd < 0 && errno == EINTR);
    return fd;
}

int pas_tcp_connect(const char *host, int port, int timeout_ms)
{
    struct addrinfo *addrs = resolve(host, port, 0);
    struct addrinfo *ai;
    int fd = -1;

    if (!addrs) {
        return -1;
    }
    for (ai = addrs; ai; ai = ai->ai_next) {
        int rc;
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            continue;
        }
        do {
            rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
        } while (rc < 0 && errno == EINTR);
        if (rc == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(addrs);

    if (fd >= 0 && timeout_ms > 0) {
        /* Bound every later read and write on this descriptor, so a backend
         * that accepts the connection and then stalls cannot hang the caller
         * forever. pas_sock_read polls as well, but a socket-level timeout
         * also covers the write side. */
        struct timeval tv;
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    }
    return fd;
}

long pas_sock_read(int fd, char *buf, long cap, int timeout_ms)
{
    ssize_t n;

    if (fd < 0 || !buf || cap <= 0) {
        return PAS_SOCK_ERROR;
    }
    if (timeout_ms > 0) {
        struct pollfd pfd;
        int rc;
        pfd.fd = fd;
        pfd.events = POLLIN;
        do {
            rc = poll(&pfd, 1, timeout_ms);
        } while (rc < 0 && errno == EINTR);
        if (rc == 0) {
            return PAS_SOCK_TIMEOUT;
        }
        if (rc < 0) {
            return PAS_SOCK_ERROR;
        }
    }
    do {
        n = read(fd, buf, (size_t) cap);
    } while (n < 0 && errno == EINTR);
    if (n < 0) {
        return (errno == EAGAIN || errno == EWOULDBLOCK)
            ? PAS_SOCK_TIMEOUT : PAS_SOCK_ERROR;
    }
    return (long) n;
}

/* Writes the whole buffer or reports failure. A short write is normal on a
 * socket, so a caller that treated one write() as "sent" would silently
 * truncate responses under load. */
long pas_sock_write(int fd, const char *buf, long len)
{
    long sent = 0;

    if (fd < 0 || !buf || len < 0) {
        return PAS_SOCK_ERROR;
    }
    while (sent < len) {
        ssize_t n;
        do {
            n = write(fd, buf + sent, (size_t) (len - sent));
        } while (n < 0 && errno == EINTR);
        if (n <= 0) {
            return PAS_SOCK_ERROR;
        }
        sent += n;
    }
    return sent;
}

/* Half-close: the peer sees end-of-input and can stop reading, while this end
 * can still receive the reply. Without it, a request/response exchange where
 * both sides write before either reads can deadlock in the socket buffers. */
void pas_sock_shutdown_write(int fd)
{
    if (fd >= 0) {
        shutdown(fd, SHUT_WR);
    }
}

void pas_sock_close(int fd)
{
    if (fd >= 0) {
        close(fd);
    }
}

/* Split "http://host[:port][/path]" into its parts. Returns 0 on success.
 * Only http is accepted -- there is no TLS here, so an https URL is rejected
 * loudly rather than silently connecting in the clear. */
int pas_url_split(const char *url, char *host, int hostcap, int *port, char *path, int pathcap)
{
    const char *rest;
    const char *slash;
    const char *colon;
    size_t hostlen;

    if (!url || !host || !port || !path || hostcap <= 1 || pathcap <= 1) {
        return -1;
    }
    if (strncmp(url, "http://", 7) != 0) {
        return -1;
    }
    rest = url + 7;

    slash = strchr(rest, '/');
    if (slash) {
        if ((int) strlen(slash) >= pathcap) {
            return -1;
        }
        strcpy(path, slash);
    } else {
        strcpy(path, "/");
    }

    hostlen = slash ? (size_t) (slash - rest) : strlen(rest);
    colon = memchr(rest, ':', hostlen);
    if (colon) {
        char portbuf[16];
        size_t portlen = (size_t) (rest + hostlen - colon - 1);
        if (portlen == 0 || portlen >= sizeof(portbuf)) {
            return -1;
        }
        memcpy(portbuf, colon + 1, portlen);
        portbuf[portlen] = '\0';
        *port = atoi(portbuf);
        if (*port <= 0 || *port > 65535) {
            return -1;
        }
        hostlen = (size_t) (colon - rest);
    } else {
        *port = 80;
    }
    if (hostlen == 0 || (int) hostlen >= hostcap) {
        return -1;
    }
    memcpy(host, rest, hostlen);
    host[hostlen] = '\0';
    return 0;
}
