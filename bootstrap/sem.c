/* The type model, symbol scopes, constant evaluation, and the C spelling of
 * every type.
 *
 * Strings and arrays are interned by shape, not by declared name, so that
 * Str255 and ArgStr (both LSTRING(255), declared in different units) are
 * one type. Records are nominal: each RECORD type expression is its own
 * type, and a repeated declaration of the same name is absorbed by the
 * unit model in emit.c before it gets here. */
#include <stdlib.h>
#include <string.h>

#include "pasboot.h"

Type *t_integer, *t_int32, *t_cint, *t_int64, *t_clong, *t_csize;
Type *t_real, *t_bool, *t_char, *t_adrmem, *t_nil, *t_strlit, *t_void;
Buf types_buf;

static int next_type_id = 1;

static Type *new_type(int kind)
{
    Type *t = xmalloc(sizeof *t);
    t->kind = kind;
    t->id = next_type_id++;
    return t;
}

static Type *int_type(int width, const char *name)
{
    Type *t = new_type(TY_INT);
    t->width = width;
    t->iname = name;
    return t;
}

/* ---- scopes ---- */

#define HASH_SIZE 4096

typedef struct Entry {
    Sym *sym;
    struct Entry *next;
} Entry;

typedef struct Scope {
    Entry **table;
    struct Scope *outer;
} Scope;

static Scope *scope;
static int depth;

static unsigned hash(const char *s)
{
    unsigned h = 2166136261u;
    while (*s)
        h = (h ^ (unsigned char) *s++) * 16777619u;
    return h % HASH_SIZE;
}

void scope_push(void)
{
    Scope *s = xmalloc(sizeof *s);
    s->table = xmalloc(HASH_SIZE * sizeof(Entry *));
    s->outer = scope;
    scope = s;
    depth++;
}

void scope_pop(void)
{
    scope = scope->outer;
    depth--;
}

int scope_depth(void)
{
    return depth;
}

Sym *new_sym(const char *name, int kind, Loc loc)
{
    Sym *s = xmalloc(sizeof *s);
    s->name = xstrdup(name);
    s->kind = kind;
    s->loc = loc;
    return s;
}

static Sym *find_in(Scope *sc, const char *name)
{
    for (Entry * e = sc->table[hash(name)]; e; e = e->next)
        if (strcmp(e->sym->name, name) == 0)
            return e->sym;
    return NULL;
}

Sym *lookup(const char *name)
{
    for (Scope * sc = scope; sc; sc = sc->outer) {
        Sym *s = find_in(sc, name);
        if (s)
            return s;
    }
    return NULL;
}

Sym *lookup_innermost(const char *name)
{
    return find_in(scope, name);
}

/* Define in the innermost scope, replacing any entry of the same name. */
void define(Sym *s)
{
    unsigned h = hash(s->name);
    for (Entry * e = scope->table[h]; e; e = e->next) {
        if (strcmp(e->sym->name, s->name) == 0) {
            e->sym = s;
            return;
        }
    }
    Entry *e = xmalloc(sizeof *e);
    e->sym = s;
    e->next = scope->table[h];
    scope->table[h] = e;
}

static void predefine_type(const char *name, Type *t)
{
    Loc none = { "<predefined>", 0 };
    Sym *s = new_sym(name, SY_TYPE, none);
    s->ty = t;
    define(s);
}

static void predefine_const(const char *name, Type *t, int64_t v)
{
    Loc none = { "<predefined>", 0 };
    Sym *s = new_sym(name, SY_CONST, none);
    s->ty = t;
    s->ival = v;
    define(s);
}

void sem_init(void)
{
    t_integer = int_type(16, "INTEGER");
    t_int32 = int_type(32, "INTEGER32");
    t_cint = int_type(32, "CINT");
    t_int64 = int_type(64, "INTEGER64");
    t_clong = int_type(64, "CLONG");
    t_csize = int_type(64, "CSIZE_T");
    t_real = new_type(TY_REAL);
    t_bool = new_type(TY_BOOL);
    t_char = new_type(TY_CHAR);
    t_adrmem = new_type(TY_ADRMEM);
    t_nil = new_type(TY_NIL);
    t_strlit = new_type(TY_STRLIT);
    t_void = new_type(TY_VOID);
    scope_push();
    predefine_type("integer", t_integer);
    predefine_type("integer32", t_int32);
    predefine_type("cint", t_cint);
    predefine_type("integer64", t_int64);
    predefine_type("clong", t_clong);
    predefine_type("csize_t", t_csize);
    predefine_type("real", t_real);
    predefine_type("boolean", t_bool);
    predefine_type("char", t_char);
    predefine_type("adrmem", t_adrmem);
    predefine_const("true", t_bool, 1);
    predefine_const("false", t_bool, 0);
    predefine_const("nil", t_nil, 0);
    predefine_const("maxint", t_integer, 32767);
    predefine_const("maxword", t_int32, 65535);
    predefine_const("maxint32", t_int32, INT32_MAX);
    predefine_const("maxint64", t_int64, INT64_MAX);
}

/* ---- type predicates ---- */

int is_int(Type *t)
{
    return t->kind == TY_INT;
}

int is_ptr(Type *t)
{
    return t->kind == TY_PTR || t->kind == TY_ADRMEM || t->kind == TY_NIL;
}

int same_type(Type *a, Type *b)
{
    if (a == b)
        return 1;
    if (a->kind != b->kind)
        return 0;
    switch (a->kind) {
    case TY_INT:
        return a->width == b->width;
    case TY_LSTR:
        return a->cap == b->cap;
    case TY_ARRAY:
        return a->lo == b->lo && a->hi == b->hi && same_type(a->elem, b->elem);
    case TY_PTR:
        return a->target && b->target && same_type(a->target, b->target);
    case TY_REAL:
    case TY_BOOL:
    case TY_CHAR:
    case TY_ADRMEM:
    case TY_NIL:
        return 1;
    default:
        return 0;
    }
}

const char *type_name(Type *t)
{
    switch (t->kind) {
    case TY_INT:
        return t->iname;
    case TY_REAL:
        return "REAL";
    case TY_BOOL:
        return "BOOLEAN";
    case TY_CHAR:
        return "CHAR";
    case TY_ADRMEM:
        return "ADRMEM";
    case TY_ENUM:
        return "enumeration";
    case TY_LSTR:
        return xfmt("LSTRING(%d)", t->cap);
    case TY_ARRAY:
        return xfmt("ARRAY [%lld..%lld] OF %s", (long long) t->lo, (long long) t->hi, type_name(t->elem));
    case TY_RECORD:
        return "RECORD";
    case TY_PTR:
        return t->target ? xfmt("^%s", type_name(t->target)) : "pointer";
    case TY_NIL:
        return "NIL";
    case TY_STRLIT:
        return "string literal";
    default:
        return "no value";
    }
}

/* ---- interning ---- */

static Vec lstr_types, array_types;

static Type *lstring_of(int cap, Loc loc)
{
    if (cap < 1 || cap > 255)
        fatal(loc, "LSTRING capacity %d is outside 1..255", cap);
    for (int i = 0; i < lstr_types.n; i++) {
        Type *t = lstr_types.p[i];
        if (t->cap == cap)
            return t;
    }
    Type *t = new_type(TY_LSTR);
    t->cap = cap;
    vec_push(&lstr_types, t);
    return t;
}

static Type *array_of(int64_t lo, int64_t hi, Type *elem, Loc loc)
{
    if (hi < lo)
        fatal(loc, "empty array bounds %lld..%lld", (long long) lo, (long long) hi);
    for (int i = 0; i < array_types.n; i++) {
        Type *t = array_types.p[i];
        if (t->lo == lo && t->hi == hi && t->elem == elem)
            return t;
    }
    Type *t = new_type(TY_ARRAY);
    t->lo = lo;
    t->hi = hi;
    t->elem = elem;
    vec_push(&array_types, t);
    return t;
}

/* ---- constants ---- */

Type *int_type_for(int64_t v)
{
    if (v >= -32767 && v <= 32767)
        return t_integer;
    if (v >= INT32_MIN && v <= INT32_MAX)
        return t_int32;
    return t_int64;
}

static Sym *const_int(int64_t v, Loc loc)
{
    Sym *s = new_sym("<const>", SY_CONST, loc);
    s->ty = int_type_for(v);
    s->ival = v;
    return s;
}

Sym *const_eval(Expr *e)
{
    Sym *s, *a, *b;
    switch (e->kind) {
    case E_INT:
        return const_int(e->ival, e->loc);
    case E_REAL:
        s = new_sym("<const>", SY_CONST, e->loc);
        s->ty = t_real;
        s->rval = e->rval;
        return s;
    case E_CHAR:
        s = new_sym("<const>", SY_CONST, e->loc);
        s->ty = t_char;
        s->ival = e->ival;
        return s;
    case E_STR:
        s = new_sym("<const>", SY_CONST, e->loc);
        s->ty = t_strlit;
        s->sval = e->s;
        s->slen = e->slen;
        return s;
    case E_NAME:
        s = lookup(e->name);
        if (!s)
            fatal(e->loc, "undeclared identifier '%s'", e->name);
        if (s->kind != SY_CONST)
            fatal(e->loc, "'%s' is not a constant", e->name);
        return s;
    case E_UN:
        a = const_eval(e->a);
        if (e->op == OP_NEG && is_int(a->ty))
            return const_int(-a->ival, e->loc);
        if (e->op == OP_NEG && a->ty->kind == TY_REAL) {
            s = new_sym("<const>", SY_CONST, e->loc);
            s->ty = t_real;
            s->rval = -a->rval;
            return s;
        }
        unsupported(e->loc, "constant expression form");
    case E_BIN:
        a = const_eval(e->a);
        b = const_eval(e->b);
        if (!is_int(a->ty) || !is_int(b->ty))
            unsupported(e->loc, "non-integer constant arithmetic");
        switch (e->op) {
        case OP_ADD:
            return const_int(a->ival + b->ival, e->loc);
        case OP_SUB:
            return const_int(a->ival - b->ival, e->loc);
        case OP_MUL:
            return const_int(a->ival * b->ival, e->loc);
        case OP_IDIV:
            if (b->ival == 0)
                fatal(e->loc, "division by zero in constant");
            return const_int(a->ival / b->ival, e->loc);
        default:
            unsupported(e->loc, "constant expression operator");
        }
    default:
        unsupported(e->loc, "constant expression form");
    }
}

static int64_t const_int_value(Expr *e)
{
    Sym *s = const_eval(e);
    if (is_int(s->ty) || s->ty->kind == TY_ENUM)
        return s->ival;
    if (s->ty->kind == TY_CHAR)
        unsupported(e->loc, "CHAR array bound");
    fatal(e->loc, "integer constant expected");
}

/* ---- type expressions ---- */

static Vec pending_ptrs;

Type *resolve_type(TypeExpr *te)
{
    Sym *s;
    Type *t;
    switch (te->kind) {
    case TE_NAME:
        s = lookup(te->name);
        if (!s)
            fatal(te->loc, "undeclared type '%s'", te->name);
        if (s->kind != SY_TYPE)
            fatal(te->loc, "'%s' is not a type", te->name);
        return s->ty;
    case TE_LSTRING:
        return lstring_of((int) const_int_value(te->lo), te->loc);
    case TE_ARRAY:{
            int64_t lo = const_int_value(te->lo);
            int64_t hi = const_int_value(te->hi);
            return array_of(lo, hi, resolve_type(te->elem), te->loc);
        }
    case TE_RECORD:{
            t = new_type(TY_RECORD);
            t->loc = te->loc;
            int n = 0;
            for (int i = 0; i < te->fields.n; i++)
                n += ((FieldGroup *) te->fields.p[i])->names.n;
            t->fields = xmalloc((size_t) (n ? n : 1) * sizeof(Field));
            for (int i = 0; i < te->fields.n; i++) {
                FieldGroup *g = te->fields.p[i];
                Type *ft = resolve_type(g->te);
                for (int j = 0; j < g->names.n; j++) {
                    char *name = g->names.p[j];
                    for (int k = 0; k < t->nfields; k++)
                        if (strcmp(t->fields[k].name, name) == 0)
                            fatal(g->loc, "duplicate field '%s'", name);
                    t->fields[t->nfields].name = name;
                    t->fields[t->nfields].ty = ft;
                    t->nfields++;
                }
            }
            return t;
        }
    case TE_POINTER:
        t = new_type(TY_PTR);
        t->loc = te->loc;
        s = lookup(te->name);
        if (s && s->kind == SY_TYPE) {
            t->target = s->ty;
        } else {
            /* A forward reference, legal until the end of this TYPE
             * section. */
            t->pending = te->name;
            vec_push(&pending_ptrs, t);
        }
        return t;
    case TE_ENUM:{
            t = new_type(TY_ENUM);
            t->loc = te->loc;
            t->lo = 0;
            t->hi = te->names.n - 1;
            for (int i = 0; i < te->names.n; i++) {
                Sym *c = new_sym(te->names.p[i], SY_CONST, te->loc);
                c->ty = t;
                c->ival = i;
                if (lookup_innermost(c->name))
                    fatal(te->loc, "duplicate identifier '%s'", c->name);
                define(c);
            }
            return t;
        }
    }
    fatal(te->loc, "bad type expression");
}

void resolve_pending_pointers(void)
{
    for (int i = 0; i < pending_ptrs.n; i++) {
        Type *t = pending_ptrs.p[i];
        Sym *s = lookup(t->pending);
        if (!s || s->kind != SY_TYPE)
            fatal(t->loc, "undeclared pointer target type '%s'", t->pending);
        t->target = s->ty;
        t->pending = NULL;
    }
    pending_ptrs.n = 0;
}

/* ---- C spellings ---- */

static const char *tag_of(Type *t)
{
    switch (t->kind) {
    case TY_LSTR:
        return xfmt("struct pl_%d", t->cap);
    case TY_ARRAY:
        return xfmt("struct pa_%d", t->id);
    case TY_RECORD:
        return xfmt("struct pr_%d", t->id);
    default:
        return NULL;
    }
}

/* The C type that stores a value of t; aggregate definitions it depends on
 * are appended to types_buf first. */
static const char *ctype_ref(Type *t, int need_complete)
{
    switch (t->kind) {
    case TY_INT:
        return t->width == 16 ? "int16_t" : t->width == 32 ? "int32_t" : "int64_t";
    case TY_REAL:
        return "double";
    case TY_BOOL:
    case TY_CHAR:
        return "uint8_t";
    case TY_ADRMEM:
        return "uint8_t *";
    case TY_ENUM:
        return "int32_t";
    case TY_PTR:
        if (!t->target)
            fatal(t->loc, "unresolved pointer target '%s'", t->pending);
        return xfmt("%s *", ctype_ref(t->target, 0));
    case TY_LSTR:
    case TY_ARRAY:
    case TY_RECORD:
        break;
    default:
        return "void";
    }
    const char *tag = tag_of(t);
    if (!t->declared) {
        t->declared = 1;
        buf_printf(&types_buf, "%s;\n", tag);
    }
    if (need_complete && !t->emitted) {
        t->emitted = 1;
        Buf def = { 0 };
        if (t->kind == TY_LSTR) {
            buf_printf(&def, "%s { uint8_t b[%d]; };\n", tag, t->cap + 1);
        } else if (t->kind == TY_ARRAY) {
            const char *et = ctype_ref(t->elem, 1);
            buf_printf(&def, "%s { %s a[%lld]; };\n", tag, et, (long long) (t->hi - t->lo + 1));
        } else {
            buf_printf(&def, "%s {\n", tag);
            for (int i = 0; i < t->nfields; i++)
                buf_printf(&def, "    %s f_%s;\n", ctype_ref(t->fields[i].ty, 1), t->fields[i].name);
            if (t->nfields == 0)
                buf_put(&def, "    char empty_;\n");
            buf_put(&def, "};\n");
        }
        buf_put(&types_buf, def.p);
    }
    return tag;
}

const char *ctype(Type *t)
{
    return ctype_ref(t, 1);
}
