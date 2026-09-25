/* pasboot command line and shared utilities.
 *
 *   pasboot [--tokens | --parse-only] <compiland.pas> [-o <out.c>]
 *
 * With no mode option, translates the compiland to C on standard output or
 * into the -o file. --tokens prints the spliced token stream. --parse-only
 * parses and checks the compiland against the bootstrap subset and writes
 * nothing. */
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#include "pasboot.h"

void *xmalloc(size_t n)
{
    void *p = calloc(1, n ? n : 1);
    if (!p) {
        fprintf(stderr, "pasboot: out of memory\n");
        exit(1);
    }
    return p;
}

void *xrealloc(void *p, size_t n)
{
    p = realloc(p, n ? n : 1);
    if (!p) {
        fprintf(stderr, "pasboot: out of memory\n");
        exit(1);
    }
    return p;
}

char *xstrdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *d = xmalloc(n);
    memcpy(d, s, n);
    return d;
}

char *xfmt(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    char *s = xmalloc((size_t) n + 1);
    va_start(ap, fmt);
    vsnprintf(s, (size_t) n + 1, fmt, ap);
    va_end(ap);
    return s;
}

void fatal(Loc loc, const char *fmt, ...)
{
    va_list ap;
    fprintf(stderr, "%s:%d: ", loc.file ? loc.file : "pasboot", loc.line);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void unsupported(Loc loc, const char *what)
{
    fatal(loc, "unsupported: %s", what);
}

void buf_put(Buf *b, const char *s)
{
    size_t n = strlen(s);
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->p = xrealloc(b->p, b->cap);
    }
    memcpy(b->p + b->len, s, n + 1);
    b->len += n;
}

void buf_printf(Buf *b, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (b->len + (size_t) n + 1 > b->cap) {
        b->cap = (b->len + (size_t) n + 1) * 2;
        b->p = xrealloc(b->p, b->cap);
    }
    va_start(ap, fmt);
    vsnprintf(b->p + b->len, (size_t) n + 1, fmt, ap);
    va_end(ap);
    b->len += (size_t) n;
}

void vec_push(Vec *v, void *x)
{
    if (v->n == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 8;
        v->p = xrealloc(v->p, (size_t) v->cap * sizeof(void *));
    }
    v->p[v->n++] = x;
}

static void usage(void)
{
    fprintf(stderr, "usage: pasboot [--tokens | --parse-only] <compiland.pas> [-o <out.c>]\n");
    exit(2);
}

static void dump_tokens(Token *t, int n)
{
    for (int i = 0; i < n; i++) {
        printf("%s:%d: ", t[i].loc.file, t[i].loc.line);
        switch (t[i].kind) {
        case T_EOF:
            printf("EOF\n");
            break;
        case T_IDENT:
            printf("IDENT %s\n", t[i].orig);
            break;
        case T_INT:
            printf("INT %lld\n", (long long) t[i].ival);
            break;
        case T_REAL:
            printf("REAL %.17g\n", t[i].rval);
            break;
        case T_CHAR:
            printf("CHAR %d\n", (int) t[i].ival);
            break;
        case T_STR:
            printf("STR '%.*s'\n", t[i].slen, (const char *) t[i].sval);
            break;
        case T_PUNCT:
            printf("PUNCT %s\n", punct_text(t[i].punct));
            break;
        }
    }
}

int main(int argc, char **argv)
{
    const char *src = NULL, *out = NULL;
    int tokens = 0, parse_only = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--tokens") == 0) {
            tokens = 1;
        } else if (strcmp(argv[i], "--parse-only") == 0) {
            parse_only = 1;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (++i >= argc)
                usage();
            out = argv[i];
        } else if (argv[i][0] == '-' && argv[i][1]) {
            usage();
        } else {
            if (src)
                usage();
            src = argv[i];
        }
    }
    if (!src || (tokens && parse_only))
        usage();

    int ntok;
    Token *toks = lex_file(src, &ntok);
    if (tokens) {
        dump_tokens(toks, ntok);
        return 0;
    }
    Compiland *c = parse_compiland(toks, ntok);
    if (parse_only)
        return translate(c, NULL, 1);

    FILE *f = stdout;
    if (out) {
        f = fopen(out, "w");
        if (!f) {
            fprintf(stderr, "pasboot: cannot write '%s'\n", out);
            return 1;
        }
    }
    int rc = translate(c, f, 0);
    if (out && fclose(f) != 0) {
        fprintf(stderr, "pasboot: error writing '%s'\n", out);
        rc = 1;
    }
    if (rc != 0 && out)
        remove(out);
    return rc;
}
