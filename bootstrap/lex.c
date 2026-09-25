/* Tokenizer. Handles both comment forms ({ } and (* *), neither nesting),
 * string and character literals, decimal, radix and real numbers, and the
 * one metacommand the bootstrap subset allows, $INCLUDE, which splices the
 * named file's tokens in place. */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "pasboot.h"

typedef struct Lexer {
    const char *file;
    const char *dir;
    const char *src;
    size_t len, pos;
    int line;
    int depth;
} Lexer;

static Token *toks;
static int ntoks, captoks;

static void push_tok(Token t)
{
    if (ntoks == captoks) {
        captoks = captoks ? captoks * 2 : 4096;
        toks = xrealloc(toks, captoks * sizeof(Token));
    }
    toks[ntoks++] = t;
}

static char *read_file(const char *path, size_t *len, Loc from)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        if (from.file)
            fatal(from, "cannot open '%s'", path);
        fprintf(stderr, "pasboot: cannot open '%s'\n", path);
        exit(1);
    }
    Buf b = { 0 };
    char chunk[65536];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        if (b.len + n + 1 > b.cap) {
            b.cap = (b.len + n + 1) * 2;
            b.p = xrealloc(b.p, b.cap);
        }
        memcpy(b.p + b.len, chunk, n);
        b.len += n;
    }
    fclose(f);
    if (!b.p)
        b.p = xmalloc(1);
    b.p[b.len] = 0;
    *len = b.len;
    return b.p;
}

static char *dir_of(const char *path)
{
    const char *slash = strrchr(path, '/');
    if (!slash)
        return xstrdup("");
    size_t n = (size_t) (slash - path) + 1;
    char *d = xmalloc(n + 1);
    memcpy(d, path, n);
    d[n] = 0;
    return d;
}

static void lex_one(const char *path, int depth, Loc from);

/* The comment body starts at lx->pos, just past the opener. A body starting
 * with '$' is a metacommand. */
static void metacommand(Lexer *lx, const char *body, size_t n, Loc loc)
{
    char word[32];
    size_t i = 1, w = 0;
    while (i < n && (isalpha((unsigned char) body[i]) || body[i] == '_') && w < sizeof word - 1)
        word[w++] = (char) toupper((unsigned char) body[i++]);
    word[w] = 0;
    if (strcmp(word, "INCLUDE") != 0)
        unsupported(loc, xfmt("metacommand $%s", word));
    while (i < n && isspace((unsigned char) body[i]))
        i++;
    if (i < n && body[i] == ':')
        i++;
    while (i < n && isspace((unsigned char) body[i]))
        i++;
    if (i >= n || body[i] != '\'')
        fatal(loc, "malformed $INCLUDE");
    size_t start = ++i;
    while (i < n && body[i] != '\'')
        i++;
    if (i >= n)
        fatal(loc, "malformed $INCLUDE");
    char *name = xmalloc(i - start + 1);
    memcpy(name, body + start, i - start);
    name[i - start] = 0;
    char *path = name[0] == '/' ? name : xfmt("%s%s", lx->dir, name);
    if (lx->depth > 16)
        fatal(loc, "$INCLUDE nested too deeply");
    lex_one(path, lx->depth + 1, loc);
}

static void skip_comment(Lexer *lx, int paren)
{
    Loc loc = { lx->file, lx->line };
    size_t start = lx->pos;
    for (;;) {
        if (lx->pos >= lx->len)
            fatal(loc, "unterminated comment");
        char c = lx->src[lx->pos];
        if (!paren && c == '}')
            break;
        if (paren && c == '*' && lx->pos + 1 < lx->len && lx->src[lx->pos + 1] == ')')
            break;
        if (c == '\n')
            lx->line++;
        lx->pos++;
    }
    size_t end = lx->pos;
    lx->pos += paren ? 2 : 1;
    if (end > start && lx->src[start] == '$')
        metacommand(lx, lx->src + start, end - start, loc);
}

static int digit_value(int c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'z')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z')
        return c - 'A' + 10;
    return 99;
}

static void lex_number(Lexer *lx, Token *t)
{
    const char *s = lx->src;
    size_t p = lx->pos;
    int is_real = 0;
    while (p < lx->len && isdigit((unsigned char) s[p]))
        p++;
    if (p < lx->len && s[p] == '#') {
        /* radix constant: base#digits */
        int base = atoi(s + lx->pos);
        if (base < 2 || base > 36)
            fatal(t->loc, "bad radix constant");
        p++;
        uint64_t v = 0;
        size_t d0 = p;
        while (p < lx->len && digit_value(s[p]) < base)
            v = v * (uint64_t) base + (uint64_t) digit_value(s[p++]);
        if (p == d0)
            fatal(t->loc, "bad radix constant");
        t->kind = T_INT;
        t->ival = (int64_t) v;
        lx->pos = p;
        return;
    }
    if (p + 1 < lx->len && s[p] == '.' && isdigit((unsigned char) s[p + 1])) {
        is_real = 1;
        p++;
        while (p < lx->len && isdigit((unsigned char) s[p]))
            p++;
    }
    if (p < lx->len && (s[p] == 'e' || s[p] == 'E')) {
        size_t q = p + 1;
        if (q < lx->len && (s[q] == '+' || s[q] == '-'))
            q++;
        if (q < lx->len && isdigit((unsigned char) s[q])) {
            is_real = 1;
            p = q;
            while (p < lx->len && isdigit((unsigned char) s[p]))
                p++;
        }
    }
    char *text = xmalloc(p - lx->pos + 1);
    memcpy(text, s + lx->pos, p - lx->pos);
    text[p - lx->pos] = 0;
    if (is_real) {
        t->kind = T_REAL;
        t->rval = strtod(text, NULL);
    } else {
        t->kind = T_INT;
        t->ival = (int64_t) strtoull(text, NULL, 10);
    }
    lx->pos = p;
}

static void lex_string(Lexer *lx, Token *t)
{
    Buf b = { 0 };
    lx->pos++;
    for (;;) {
        if (lx->pos >= lx->len || lx->src[lx->pos] == '\n')
            fatal(t->loc, "unterminated string literal");
        char c = lx->src[lx->pos++];
        if (c == '\'') {
            if (lx->pos < lx->len && lx->src[lx->pos] == '\'') {
                lx->pos++;
            } else {
                break;
            }
        }
        if (b.len + 2 > b.cap) {
            b.cap = b.cap ? b.cap * 2 : 32;
            b.p = xrealloc(b.p, b.cap);
        }
        b.p[b.len++] = c;
    }
    if (b.len == 1) {
        /* A single quoted character is a CHAR, not a string. */
        t->kind = T_CHAR;
        t->ival = (unsigned char) b.p[0];
        return;
    }
    t->kind = T_STR;
    t->sval = (unsigned char *) (b.p ? b.p : xmalloc(1));
    t->slen = (int) b.len;
}

static void lex_one(const char *path, int depth, Loc from)
{
    Lexer lx = { 0 };
    lx.file = xstrdup(path);
    lx.dir = dir_of(path);
    lx.src = read_file(path, &lx.len, from);
    lx.line = 1;
    lx.depth = depth;
    const char *s = lx.src;
    while (lx.pos < lx.len) {
        char c = s[lx.pos];
        if (c == '\n') {
            lx.line++;
            lx.pos++;
            continue;
        }
        if (isspace((unsigned char) c)) {
            lx.pos++;
            continue;
        }
        if (c == '{') {
            lx.pos++;
            skip_comment(&lx, 0);
            continue;
        }
        if (c == '(' && lx.pos + 1 < lx.len && s[lx.pos + 1] == '*') {
            lx.pos += 2;
            skip_comment(&lx, 1);
            continue;
        }
        Token t = { 0 };
        t.loc.file = lx.file;
        t.loc.line = lx.line;
        if (isalpha((unsigned char) c) || c == '_') {
            size_t p = lx.pos;
            while (p < lx.len && (isalnum((unsigned char) s[p]) || s[p] == '_'))
                p++;
            t.kind = T_IDENT;
            t.orig = xmalloc(p - lx.pos + 1);
            memcpy(t.orig, s + lx.pos, p - lx.pos);
            t.orig[p - lx.pos] = 0;
            t.text = xstrdup(t.orig);
            for (char *q = t.text; *q; q++)
                *q = (char) tolower((unsigned char) *q);
            lx.pos = p;
        } else if (isdigit((unsigned char) c)) {
            lex_number(&lx, &t);
        } else if (c == '\'') {
            lex_string(&lx, &t);
        } else {
            char d = lx.pos + 1 < lx.len ? s[lx.pos + 1] : 0;
            int two = 0;
            t.kind = T_PUNCT;
            switch (c) {
            case '(':
                t.punct = P_LPAREN;
                break;
            case ')':
                t.punct = P_RPAREN;
                break;
            case '[':
                t.punct = P_LBRACK;
                break;
            case ']':
                t.punct = P_RBRACK;
                break;
            case ',':
                t.punct = P_COMMA;
                break;
            case ';':
                t.punct = P_SEMI;
                break;
            case '^':
                t.punct = P_CARET;
                break;
            case '+':
                t.punct = P_PLUS;
                break;
            case '-':
                t.punct = P_MINUS;
                break;
            case '*':
                t.punct = P_STAR;
                break;
            case '/':
                t.punct = P_SLASH;
                break;
            case '=':
                t.punct = P_EQ;
                break;
            case ':':
                if (d == '=') {
                    t.punct = P_ASSIGN;
                    two = 1;
                } else {
                    t.punct = P_COLON;
                }
                break;
            case '.':
                if (d == '.') {
                    t.punct = P_DOTDOT;
                    two = 1;
                } else {
                    t.punct = P_DOT;
                }
                break;
            case '<':
                if (d == '>') {
                    t.punct = P_NE;
                    two = 1;
                } else if (d == '=') {
                    t.punct = P_LE;
                    two = 1;
                } else {
                    t.punct = P_LT;
                }
                break;
            case '>':
                if (d == '=') {
                    t.punct = P_GE;
                    two = 1;
                } else {
                    t.punct = P_GT;
                }
                break;
            default:
                fatal(t.loc, "unexpected character '%c' (0x%02x)", isprint((unsigned char) c) ? c : '?', (unsigned char) c);
            }
            lx.pos += two ? 2 : 1;
        }
        push_tok(t);
    }
}

Token *lex_file(const char *path, int *ntok)
{
    Loc none = { 0, 0 };
    ntoks = 0;
    lex_one(path, 0, none);
    Token eof = { 0 };
    eof.kind = T_EOF;
    eof.loc.file = ntoks ? toks[ntoks - 1].loc.file : path;
    eof.loc.line = ntoks ? toks[ntoks - 1].loc.line : 1;
    push_tok(eof);
    *ntok = ntoks;
    return toks;
}

const char *punct_text(int p)
{
    static const char *names[] = {
        "?", "(", ")", "[", "]", ",", ";", ":", ":=", ".", "..", "^", "+", "-",
        "*", "/", "=", "<>", "<", "<=", ">", ">="
    };
    if (p < 0 || p >= (int) (sizeof names / sizeof names[0]))
        return "?";
    return names[p];
}
