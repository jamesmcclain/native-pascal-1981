/* The C emitter and the unit model.
 *
 * One compiland becomes one C translation unit: the spliced interfaces give
 * extern declarations, the implementation (or program) gives definitions.
 * Types are written on demand into types_buf, everything else in source
 * order, so the output is "#include prelude.h", then the types, then the
 * declarations.
 *
 * Expression semantics are the native compiler's, which the Python reference
 * compiler that used to build generation 1 shares wherever the compiled
 * sources can tell (scripts/cross-bootstrap-check.sh checks exactly that):
 *   - integer operands widen (sign-extending) to the wider of the two, the
 *     operation happens at that width and wraps (the C is compiled with
 *     -fwrapv), and comparisons are signed, CHAR included;
 *   - AND and OR evaluate both operands; only AND THEN short-circuits;
 *   - ORD yields 32 bits, zero-extended; CHR truncates to 8 bits;
 *   - RETYPE between integers truncates or sign-extends (the Python
 *     reference zero-filled on widening; the sources only narrow);
 *   - a FOR limit is evaluated once and converted to the control variable's
 *     type, and the variable ends one past it (the Python reference
 *     re-evaluated the limit; the sources never depend on either);
 *   - LSTRING comparison is memcmp over the shorter length, then length. */
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#include "pasboot.h"

typedef struct CE {
    char *s;                    /* C text */
    Type *ty;
    int lval;
    Expr *lit;                  /* the E_STR or E_CHAR literal, if it is one */
} CE;

static Buf out;                 /* declarations and definitions */
static Buf *body;               /* where statements go */
static int indent;
static Compiland *comp;
static const char *impl_unit;   /* IMPLEMENTATION OF <unit>, else NULL */
static const char *iface_unit;  /* the interface being processed, else NULL */
static Sym *cur_func;           /* routine whose body is being emitted */
static int in_main;             /* emitting the program body */
static int for_count;           /* numbers each FOR's limit temporaries */

static CE gen_expr(Expr * e);

static void line(const char *fmt, ...) __attribute__((format(printf, 1, 2)));


static void line(const char *fmt, ...)
{
    for (int i = 0; i < indent; i++)
        buf_put(body, "    ");
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    char *s = xmalloc((size_t) n + 1);
    va_start(ap, fmt);
    vsnprintf(s, (size_t) n + 1, fmt, ap);
    va_end(ap);
    buf_put(body, s);
    buf_put(body, "\n");
    free(s);
}

static CE mk(char *s, Type *ty, int lval)
{
    CE c = { s, ty, lval, NULL };
    return c;
}

/* ---- literals ---- */

static char *c_string_bytes(const unsigned char *s, int n, int prefix_len)
{
    Buf b = { 0 };
    buf_put(&b, "\"");
    if (prefix_len)
        buf_printf(&b, "\\%03o", n);
    for (int i = 0; i < n; i++) {
        unsigned char c = s[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' || c == '_')
            buf_printf(&b, "%c", c);
        else
            buf_printf(&b, "\\%03o", c);
    }
    buf_put(&b, "\"");
    return b.p;
}

/* A string literal as a pointer to a length-prefixed byte sequence -- the
 * same shape as the b member of an LSTRING. */
static char *lit_lstr_ptr(Expr *e)
{
    if (e->slen > 255)
        fatal(e->loc, "string literal longer than 255 characters");
    return xfmt("((const uint8_t *)%s)", c_string_bytes(e->s, e->slen, 1));
}

static char *int_lit(int64_t v)
{
    if (v >= INT32_MIN && v <= INT32_MAX)
        return xfmt("%lld", (long long) v);
    return xfmt("INT64_C(%lld)", (long long) v);
}

static char *real_lit(double v)
{
    char *s = xfmt("%.17g", v);
    if (!strpbrk(s, ".eEni"))
        s = xfmt("%s.0", s);
    return xfmt("(%s)", s);
}

static CE const_ce(Sym *s, Expr *e)
{
    CE c = { 0 };
    c.ty = s->ty;
    switch (s->ty->kind) {
    case TY_INT:
    case TY_ENUM:
        c.s = xfmt("(%s)", int_lit(s->ival));
        break;
    case TY_BOOL:
        c.s = xfmt("((uint8_t)%d)", (int) s->ival);
        break;
    case TY_CHAR:{
            c.s = xfmt("((uint8_t)%d)", (int) s->ival);
            Expr *l = xmalloc(sizeof *l);
            l->kind = E_CHAR;
            l->loc = e->loc;
            l->ival = s->ival;
            c.lit = l;
            break;
        }
    case TY_REAL:
        c.s = real_lit(s->rval);
        break;
    case TY_NIL:
        c.s = "((void *)0)";
        break;
    case TY_STRLIT:{
            Expr *l = xmalloc(sizeof *l);
            l->kind = E_STR;
            l->loc = e->loc;
            l->s = s->sval;
            l->slen = s->slen;
            c.lit = l;
            c.s = lit_lstr_ptr(l);
            break;
        }
    default:
        fatal(e->loc, "bad constant");
    }
    return c;
}

/* ---- conversions ---- */

static const char *int_ctype(int width)
{
    return width == 8 ? "int8_t" : width == 16 ? "int16_t" : width == 32 ? "int32_t" : "int64_t";
}

/* The bytes of a string-valued operand, as a length-prefixed pointer. */
static char *lstr_bytes(CE e, Loc loc)
{
    if (e.ty->kind == TY_LSTR)
        return xfmt("((const uint8_t *)(%s).b)", e.s);
    if (e.ty->kind == TY_STRLIT)
        return lit_lstr_ptr(e.lit);
    fatal(loc, "string operand expected, found %s", type_name(e.ty));
}

/* e converted for storage in, or passing as a value of, type to. */
static char *conv(CE e, Type *to, Loc loc)
{
    Type *from = e.ty;
    switch (to->kind) {
    case TY_INT:
        if (is_int(from) || from->kind == TY_ENUM)
            return xfmt("((%s)%s)", ctype(to), e.s);
        break;
    case TY_REAL:
        if (from->kind == TY_REAL)
            return e.s;
        if (is_int(from))
            return xfmt("((double)%s)", e.s);
        break;
    case TY_BOOL:
        if (from->kind == TY_BOOL)
            return xfmt("((uint8_t)%s)", e.s);
        break;
    case TY_CHAR:
        if (from->kind == TY_CHAR)
            return e.s;
        break;
    case TY_ENUM:
        if (from == to)
            return e.s;
        break;
    case TY_ADRMEM:
    case TY_PTR:
        if (is_ptr(from))
            return xfmt("((%s)%s)", ctype(to), e.s);
        break;
    case TY_LSTR:
        if (from->kind == TY_LSTR && from->cap == to->cap)
            return e.s;
        if (from->kind == TY_STRLIT) {
            if (e.lit->slen > to->cap)
                fatal(loc, "string literal of length %d does not fit %s", e.lit->slen, type_name(to));
            return xfmt("((%s){%s})", ctype(to), c_string_bytes(e.lit->s, e.lit->slen, 1));
        }
        if (from->kind == TY_LSTR)
            unsupported(loc, xfmt("assignment between %s and %s", type_name(from), type_name(to)));
        break;
    case TY_ARRAY:
    case TY_RECORD:
        if (from == to || same_type(from, to))
            return e.s;
        break;
    default:
        break;
    }
    fatal(loc, "type mismatch: %s where %s is expected", type_name(from), type_name(to));
}

/* ---- names ---- */

static CE var_ce(Sym *s)
{
    if (s->is_varparam)
        return mk(xfmt("(*%s)", s->cname), s->ty, 1);
    return mk(s->cname, s->ty, 1);
}

static CE gen_call(Sym * r, Vec * args, Loc loc);

static CE gen_name(Expr *e)
{
    Sym *s = lookup(e->name);
    if (!s)
        fatal(e->loc, "undeclared identifier '%s'", e->name);
    switch (s->kind) {
    case SY_CONST:
        return const_ce(s, e);
    case SY_VAR:
        return var_ce(s);
    case SY_ROUTINE:
        /* A bare routine name is a call, even inside that routine: its
         * result is only ever assigned, never read. */
        return gen_call(s, NULL, e->loc);
    default:
        fatal(e->loc, "'%s' is a type, not a value", e->name);
    }
}

/* ---- calls ---- */

static CE gen_call(Sym *r, Vec *args, Loc loc)
{
    int nargs = args ? args->n : 0;
    if (nargs != r->nparams)
        fatal(loc, "'%s' takes %d argument(s), %d given", r->name, r->nparams, nargs);
    Buf b = { 0 };
    buf_printf(&b, "%s(", r->cname);
    for (int i = 0; i < nargs; i++) {
        Expr *a = args->p[i];
        ParamInfo *p = &r->params[i];
        if (i)
            buf_put(&b, ", ");
        CE v = gen_expr(a);
        if (p->is_var) {
            if (!v.lval)
                fatal(a->loc, "VAR argument %d of '%s' is not a variable", i + 1, r->name);
            if (!same_type(v.ty, p->ty) && !(is_ptr(v.ty) && is_ptr(p->ty)))
                fatal(a->loc, "VAR argument %d of '%s': %s where %s is expected", i + 1, r->name, type_name(v.ty), type_name(p->ty));
            buf_printf(&b, "((%s *)&%s)", ctype(p->ty), v.s);
        } else {
            buf_put(&b, conv(v, p->ty, a->loc));
        }
    }
    buf_put(&b, ")");
    return mk(b.p, r->ty ? r->ty : t_void, 0);
}

static Type *type_arg(Expr *e)
{
    if (e->kind != E_NAME)
        fatal(e->loc, "type name expected");
    Sym *s = lookup(e->name);
    if (!s || s->kind != SY_TYPE)
        fatal(e->loc, "type name expected");
    return s->ty;
}

static int bits_of(Type *t)
{
    if (is_int(t))
        return t->width;
    if (t->kind == TY_CHAR || t->kind == TY_BOOL)
        return 8;
    if (t->kind == TY_ENUM)
        return 32;
    return 0;
}

static CE gen_builtin(Expr *e)
{
    const char *n = e->name;
    int nargs = e->args.n;
    Expr **a = (Expr **) e->args.p;
    if (strcmp(n, "ord") == 0 && nargs == 1) {
        CE v = gen_expr(a[0]);
        int w = bits_of(v.ty);
        if (!w)
            fatal(e->loc, "ORD of %s", type_name(v.ty));
        if (w == 64)
            unsupported(e->loc, "ORD of a 64-bit value");
        if (w < 32)
            return mk(xfmt("((int32_t)(uint%d_t)%s)", w, v.s), t_int32, 0);
        return mk(xfmt("((int32_t)%s)", v.s), t_int32, 0);
    }
    if (strcmp(n, "chr") == 0 && nargs == 1) {
        CE v = gen_expr(a[0]);
        if (!is_int(v.ty))
            fatal(e->loc, "CHR of %s", type_name(v.ty));
        return mk(xfmt("((uint8_t)%s)", v.s), t_char, 0);
    }
    if (strcmp(n, "retype") == 0 && nargs == 2) {
        Type *to = type_arg(a[0]);
        CE v = gen_expr(a[1]);
        int tw = bits_of(to), fw = bits_of(v.ty);
        if (tw && fw) {
            /* Narrowing keeps the low bytes; widening sign-extends a signed
             * integer, as the native compiler does. (The Python reference
             * zero-filled instead; the compiled sources only ever narrow or
             * keep the width.) */
            return mk(xfmt("((%s)%s)", ctype(to), v.s), to, 0);
        }
        if (is_ptr(to) && is_ptr(v.ty))
            return mk(xfmt("((%s)%s)", ctype(to), v.s), to, 0);
        unsupported(e->loc, xfmt("RETYPE from %s to %s", type_name(v.ty), type_name(to)));
    }
    if (strcmp(n, "sizeof") == 0 && nargs == 1) {
        Type *t;
        Sym *s = a[0]->kind == E_NAME ? lookup(a[0]->name) : NULL;
        if (s && s->kind == SY_TYPE)
            t = s->ty;
        else
            t = gen_expr(a[0]).ty;
        return mk(xfmt("((int32_t)sizeof(%s))", ctype(t)), t_int32, 0);
    }
    if (strcmp(n, "trunc") == 0 && nargs == 1) {
        CE v = gen_expr(a[0]);
        if (v.ty->kind != TY_REAL)
            fatal(e->loc, "TRUNC of %s", type_name(v.ty));
        return mk(xfmt("((int16_t)(int64_t)%s)", v.s), t_integer, 0);
    }
    unsupported(e->loc, xfmt("builtin %s/%d", n, nargs));
}

/* ---- expressions ---- */

static Type *wider(Type *a, Type *b)
{
    return b->width > a->width ? b : a;
}

static int string_like(CE c)
{
    return c.ty->kind == TY_LSTR || c.ty->kind == TY_STRLIT;
}

static const char *op_text(int op)
{
    switch (op) {
    case OP_ADD:
        return "+";
    case OP_SUB:
        return "-";
    case OP_MUL:
        return "*";
    case OP_IDIV:
        return "/";
    case OP_MOD:
        return "%";
    case OP_AND:
        return "&";
    case OP_OR:
        return "|";
    case OP_EQ:
        return "==";
    case OP_NE:
        return "!=";
    case OP_LT:
        return "<";
    case OP_LE:
        return "<=";
    case OP_GT:
        return ">";
    case OP_GE:
        return ">=";
    default:
        return "?";
    }
}

static int is_cmp(int op)
{
    return op >= OP_EQ && op <= OP_GE;
}

static CE gen_binary(Expr *e)
{
    CE l = gen_expr(e->a), r = gen_expr(e->b);
    int op = e->op;
    const char *o = op_text(op);
    Loc loc = e->loc;

    if (op == OP_ANDTHEN) {
        if (l.ty->kind != TY_BOOL || r.ty->kind != TY_BOOL)
            fatal(loc, "AND THEN needs BOOLEAN operands");
        return mk(xfmt("((uint8_t)(%s && %s))", l.s, r.s), t_bool, 0);
    }
    if (is_cmp(op)) {
        if (string_like(l) || string_like(r)) {
            return mk(xfmt("((uint8_t)(pas_scmp(%s, %s) %s 0))", lstr_bytes(l, loc), lstr_bytes(r, loc), o), t_bool, 0);
        }
        if (is_ptr(l.ty) && is_ptr(r.ty)) {
            if (op != OP_EQ && op != OP_NE)
                fatal(loc, "pointers compare only with = and <>");
            return mk(xfmt("((uint8_t)((const void *)%s %s (const void *)%s))", l.s, o, r.s), t_bool, 0);
        }
        if (l.ty->kind == TY_REAL || r.ty->kind == TY_REAL) {
            if ((l.ty->kind != TY_REAL && !is_int(l.ty)) || (r.ty->kind != TY_REAL && !is_int(r.ty)))
                fatal(loc, "cannot compare %s with %s", type_name(l.ty), type_name(r.ty));
            return mk(xfmt("((uint8_t)((double)%s %s (double)%s))", l.s, o, r.s), t_bool, 0);
        }
        if (is_int(l.ty) && is_int(r.ty)) {
            const char *ct = int_ctype(wider(l.ty, r.ty)->width);
            return mk(xfmt("((uint8_t)((%s)%s %s (%s)%s))", ct, l.s, o, ct, r.s), t_bool, 0);
        }
        if (l.ty->kind == TY_CHAR && r.ty->kind == TY_CHAR)
            return mk(xfmt("((uint8_t)((int8_t)%s %s (int8_t)%s))", l.s, o, r.s), t_bool, 0);
        if (l.ty->kind == TY_BOOL && r.ty->kind == TY_BOOL) {
            if (op != OP_EQ && op != OP_NE)
                unsupported(loc, "ordering comparison of BOOLEAN values");
            return mk(xfmt("((uint8_t)(%s %s %s))", l.s, o, r.s), t_bool, 0);
        }
        if (l.ty->kind == TY_ENUM && l.ty == r.ty)
            return mk(xfmt("((uint8_t)(%s %s %s))", l.s, o, r.s), t_bool, 0);
        fatal(loc, "cannot compare %s with %s", type_name(l.ty), type_name(r.ty));
    }
    if (op == OP_AND || op == OP_OR) {
        if (l.ty->kind == TY_BOOL && r.ty->kind == TY_BOOL)
            return mk(xfmt("((uint8_t)(%s %s %s))", l.s, o, r.s), t_bool, 0);
        if (is_int(l.ty) && is_int(r.ty)) {
            Type *t = wider(l.ty, r.ty);
            const char *ct = int_ctype(t->width);
            return mk(xfmt("((%s)((%s)%s %s (%s)%s))", ct, ct, l.s, o, ct, r.s), t, 0);
        }
        fatal(loc, "%s needs BOOLEAN or integer operands", op == OP_AND ? "AND" : "OR");
    }
    if (op == OP_ADD && l.ty->kind == TY_PTR)
        ctype(l.ty->target);
    if (op == OP_ADD && r.ty->kind == TY_PTR)
        ctype(r.ty->target);
    if (op == OP_ADD && is_ptr(l.ty) && l.ty->kind != TY_NIL && is_int(r.ty))
        return mk(xfmt("(%s + %s)", l.s, r.s), l.ty, 0);
    if (op == OP_ADD && is_ptr(r.ty) && r.ty->kind != TY_NIL && is_int(l.ty))
        return mk(xfmt("(%s + %s)", r.s, l.s), r.ty, 0);
    if (op == OP_RDIV) {
        if ((l.ty->kind != TY_REAL && !is_int(l.ty)) || (r.ty->kind != TY_REAL && !is_int(r.ty)))
            fatal(loc, "'/' needs numeric operands");
        return mk(xfmt("((double)%s / (double)%s)", l.s, r.s), t_real, 0);
    }
    if (l.ty->kind == TY_REAL || r.ty->kind == TY_REAL) {
        if ((l.ty->kind != TY_REAL && !is_int(l.ty)) || (r.ty->kind != TY_REAL && !is_int(r.ty)))
            fatal(loc, "arithmetic on %s and %s", type_name(l.ty), type_name(r.ty));
        if (op == OP_IDIV || op == OP_MOD)
            fatal(loc, "DIV and MOD need integer operands");
        return mk(xfmt("((double)%s %s (double)%s)", l.s, o, r.s), t_real, 0);
    }
    if (is_int(l.ty) && is_int(r.ty)) {
        Type *t = wider(l.ty, r.ty);
        const char *ct = int_ctype(t->width);
        return mk(xfmt("((%s)((%s)%s %s (%s)%s))", ct, ct, l.s, o, ct, r.s), t, 0);
    }
    fatal(loc, "arithmetic on %s and %s", type_name(l.ty), type_name(r.ty));
}

static CE gen_expr(Expr *e)
{
    CE c = { 0 };
    switch (e->kind) {
    case E_INT:
        return mk(xfmt("(%s)", int_lit(e->ival)), int_type_for(e->ival), 0);
    case E_REAL:
        return mk(real_lit(e->rval), t_real, 0);
    case E_CHAR:
        c = mk(xfmt("((uint8_t)%d)", (int) e->ival), t_char, 0);
        c.lit = e;
        return c;
    case E_STR:
        c = mk(lit_lstr_ptr(e), t_strlit, 0);
        c.lit = e;
        return c;
    case E_NAME:
        return gen_name(e);
    case E_CALL:{
            Sym *s = lookup(e->name);
            if (s) {
                if (s->kind != SY_ROUTINE)
                    fatal(e->loc, "'%s' is not a routine", e->name);
                CE r = gen_call(s, &e->args, e->loc);
                if (r.ty == t_void)
                    fatal(e->loc, "procedure '%s' used as a value", e->name);
                return r;
            }
            return gen_builtin(e);
        }
    case E_INDEX:{
            CE b = gen_expr(e->a);
            CE i = gen_expr(e->b);
            if (!is_int(i.ty))
                fatal(e->loc, "subscript of type %s", type_name(i.ty));
            if (b.ty->kind == TY_LSTR)
                return mk(xfmt("(%s).b[%s]", b.s, i.s), t_char, b.lval);
            if (b.ty->kind == TY_ARRAY) {
                if (b.ty->lo == 0)
                    return mk(xfmt("(%s).a[%s]", b.s, i.s), b.ty->elem, b.lval);
                return mk(xfmt("(%s).a[%s - %s]", b.s, i.s, int_lit(b.ty->lo)), b.ty->elem, b.lval);
            }
            fatal(e->loc, "subscript of %s", type_name(b.ty));
        }
    case E_FIELD:{
            CE b = gen_expr(e->a);
            if (b.ty->kind != TY_RECORD)
                fatal(e->loc, "field selection from %s", type_name(b.ty));
            for (int i = 0; i < b.ty->nfields; i++)
                if (strcmp(b.ty->fields[i].name, e->name) == 0)
                    return mk(xfmt("(%s).f_%s", b.s, e->name), b.ty->fields[i].ty, b.lval);
            fatal(e->loc, "no field '%s' in record", e->name);
        }
    case E_DEREF:{
            CE b = gen_expr(e->a);
            if (b.ty->kind != TY_PTR)
                fatal(e->loc, "'^' applied to %s", type_name(b.ty));
            ctype(b.ty->target);        /* the pointee must be complete */
            return mk(xfmt("(*%s)", b.s), b.ty->target, 1);
        }
    case E_BIN:
        return gen_binary(e);
    case E_UN:{
            CE v = gen_expr(e->a);
            if (e->op == OP_NEG) {
                if (v.ty->kind == TY_REAL)
                    return mk(xfmt("(-%s)", v.s), t_real, 0);
                if (is_int(v.ty))
                    return mk(xfmt("((%s)-%s)", int_ctype(v.ty->width), v.s), v.ty, 0);
                fatal(e->loc, "unary minus on %s", type_name(v.ty));
            }
            if (v.ty->kind == TY_BOOL)
                return mk(xfmt("((uint8_t)!%s)", v.s), t_bool, 0);
            if (is_int(v.ty))
                return mk(xfmt("((%s)~%s)", int_ctype(v.ty->width), v.s), v.ty, 0);
            fatal(e->loc, "NOT on %s", type_name(v.ty));
        }
    case E_ADR:{
            Sym *s = lookup(e->name);
            if (!s || s->kind != SY_VAR)
                fatal(e->loc, "ADR needs a variable");
            CE v = var_ce(s);
            return mk(xfmt("((uint8_t *)&%s)", v.s), t_adrmem, 0);
        }
    }
    fatal(e->loc, "bad expression");
}

/* ---- statements ---- */

static void gen_stmt(Stmt * s);

static void gen_block_body(Stmt *s)
{
    indent++;
    if (s->kind == S_BLOCK) {
        for (int i = 0; i < s->stmts.n; i++)
            gen_stmt(s->stmts.p[i]);
    } else {
        gen_stmt(s);
    }
    indent--;
}

static void gen_write(Expr *call, int newline)
{
    int n = call && call->kind == E_CALL ? call->args.n : 0;
    for (int i = 0; i < n; i++) {
        Expr *a = call->args.p[i];
        CE v = gen_expr(a);
        if (v.ty->kind == TY_STRLIT)
            line("pas_wr_str(%s);", lit_lstr_ptr(v.lit));
        else if (v.ty->kind == TY_CHAR)
            line("pas_wr_ch(%s);", v.s);
        else
            unsupported(a->loc, xfmt("WRITE of %s", type_name(v.ty)));
    }
    if (newline)
        line("pas_wr_ch(10);");
}

static void gen_concat(Expr *call)
{
    if (call->args.n != 2)
        unsupported(call->loc, "CONCAT with other than two arguments");
    Expr *d = call->args.p[0];
    if (d->kind != E_NAME)
        unsupported(d->loc, "CONCAT destination other than a bare variable");
    CE dv = gen_expr(d);
    if (!dv.lval || dv.ty->kind != TY_LSTR)
        fatal(d->loc, "CONCAT destination must be an LSTRING variable");
    CE sv = gen_expr(call->args.p[1]);
    line("pas_concat(%s.b, %d, %s);", dv.s, dv.ty->cap, lstr_bytes(sv, call->loc));
}

static void gen_call_stmt(Stmt *st)
{
    Expr *e = st->lhs;
    Sym *s = lookup(e->name);
    if (s) {
        if (s->kind != SY_ROUTINE)
            fatal(e->loc, "'%s' is not a procedure", e->name);
        CE c = gen_call(s, e->kind == E_CALL ? &e->args : NULL, e->loc);
        line("%s;", c.s);
        return;
    }
    if (strcmp(e->name, "write") == 0 || strcmp(e->name, "writeln") == 0) {
        gen_write(e, strcmp(e->name, "writeln") == 0);
        return;
    }
    if (strcmp(e->name, "concat") == 0 && e->kind == E_CALL) {
        gen_concat(e);
        return;
    }
    if (e->kind == E_NAME)
        fatal(e->loc, "undeclared identifier '%s'", e->name);
    unsupported(e->loc, xfmt("builtin procedure %s", e->name));
}

static void gen_stmt(Stmt *s)
{
    switch (s->kind) {
    case S_EMPTY:
        return;
    case S_BLOCK:
        line("{");
        gen_block_body(s);
        line("}");
        return;
    case S_ASSIGN:{
            CE l;
            Expr *le = s->lhs;
            Sym *fs = le->kind == E_NAME ? lookup(le->name) : NULL;
            if (fs && fs->kind == SY_ROUTINE) {
                if (fs != cur_func || !fs->ty)
                    fatal(le->loc, "assignment to routine '%s'", le->name);
                l = mk("pres", fs->ty, 1);
            } else {
                l = gen_expr(le);
            }
            if (!l.lval)
                fatal(le->loc, "left side of ':=' is not a variable");
            CE r = gen_expr(s->rhs);
            line("%s = %s;", l.s, conv(r, l.ty, s->loc));
            return;
        }
    case S_CALL:
        gen_call_stmt(s);
        return;
    case S_IF:{
            CE c = gen_expr(s->cond);
            if (c.ty->kind != TY_BOOL)
                fatal(s->cond->loc, "IF condition is %s, not BOOLEAN", type_name(c.ty));
            line("if (%s) {", c.s);
            gen_block_body(s->then);
            if (s->els) {
                line("} else {");
                gen_block_body(s->els);
            }
            line("}");
            return;
        }
    case S_WHILE:{
            CE c = gen_expr(s->cond);
            if (c.ty->kind != TY_BOOL)
                fatal(s->cond->loc, "WHILE condition is %s, not BOOLEAN", type_name(c.ty));
            line("while (%s) {", c.s);
            gen_block_body(s->body);
            line("}");
            return;
        }
    case S_FOR:{
            Sym *v = lookup(s->var);
            if (!v || v->kind != SY_VAR)
                fatal(s->varloc, "FOR control '%s' is not a variable", s->var);
            if (!is_int(v->ty))
                unsupported(s->varloc, xfmt("FOR over %s", type_name(v->ty)));
            CE cv = var_ce(v);
            CE from = gen_expr(s->from);
            CE to = gen_expr(s->to);
            if (!is_int(to.ty))
                fatal(s->to->loc, "FOR limit is %s", type_name(to.ty));
            /* The limit is saved once. 'done' is set as the variable steps
             * past the limit, so a limit at the type's extreme ends the
             * loop instead of wrapping around, while the variable still
             * ends one step past the limit, as in the native compiler. */
            const char *ct = ctype(v->ty);
            int n = ++for_count;
            line("{");
            indent++;
            line("%s = %s;", cv.s, conv(from, v->ty, s->from->loc));
            line("%s lim_%d = (%s)%s;", ct, n, ct, to.s);
            line("int done_%d = 0;", n);
            line("for (; !done_%d && %s %s lim_%d; done_%d = %s == lim_%d, %s = (%s)(%s %s 1)) {", n, cv.s, s->down ? ">=" : "<=", n, n, cv.s, n, cv.s, ct, cv.s,
                 s->down ? "-" : "+");
            gen_block_body(s->body);
            line("}");
            indent--;
            line("}");
            return;
        }
    case S_RETURN:
        if (in_main)
            line("return 0;");
        else if (cur_func && cur_func->ty)
            line("return pres;");
        else
            line("return;");
        return;
    case S_BREAK:
        line("break;");
        return;
    case S_CYCLE:
        line("continue;");
        return;
    }
}

/* ---- declarations ---- */

static char *param_decl(ParamInfo *p, int named)
{
    const char *t = ctype(p->ty);
    if (p->is_var)
        return named ? xfmt("%s *a_%s", t, p->name) : xfmt("%s *", t);
    return named ? xfmt("%s a_%s", t, p->name) : xfmt("%s", t);
}

static char *prototype(Sym *r, int named)
{
    Buf b = { 0 };
    buf_printf(&b, "%s %s(", r->ty ? ctype(r->ty) : "void", r->cname);
    if (r->nparams == 0)
        buf_put(&b, "void");
    for (int i = 0; i < r->nparams; i++) {
        if (i)
            buf_put(&b, ", ");
        buf_put(&b, param_decl(&r->params[i], named));
    }
    buf_put(&b, ")");
    return b.p;
}

static int is_exported(Sym *s)
{
    return s->from_iface && impl_unit && strcmp(s->owner, impl_unit) == 0;
}

static void signature(Routine *r, Sym *s)
{
    int n = 0;
    for (int i = 0; i < r->params.n; i++)
        n += ((ParamGroup *) r->params.p[i])->names.n;
    s->params = xmalloc((size_t) (n ? n : 1) * sizeof(ParamInfo));
    s->nparams = 0;
    for (int i = 0; i < r->params.n; i++) {
        ParamGroup *g = r->params.p[i];
        Type *t = resolve_type(g->te);
        for (int j = 0; j < g->names.n; j++) {
            ParamInfo *p = &s->params[s->nparams++];
            p->name = g->names.p[j];
            p->ty = t;
            p->is_var = g->is_var;
        }
    }
    s->ty = r->is_func ? (r->result ? resolve_type(r->result) : NULL) : NULL;
    if (r->is_func && !s->ty)
        fatal(r->loc, "function '%s' has no result type", r->name);
}

static void process_sections(Vec * decls, int local);

static int c_scalar(Type *t)
{
    return is_int(t) || is_ptr(t) || t->kind == TY_REAL;
}

/* Only scalars cross the C boundary: no aggregate passed or returned by
 * value, and no VAR parameter. */
static void check_c_signature(Routine *r, Sym *s)
{
    for (int i = 0; i < s->nparams; i++)
        if (s->params[i].is_var || !c_scalar(s->params[i].ty))
            unsupported(r->loc, xfmt("[C] parameter '%s' of %s%s", s->params[i].name, s->params[i].is_var ? "VAR " : "", type_name(s->params[i].ty)));
    if (s->ty && !c_scalar(s->ty))
        unsupported(r->loc, xfmt("[C] result of %s", type_name(s->ty)));
}

static void emit_body(Sym *s, Routine *r)
{
    Buf fb = { 0 };
    Buf *saved = body;
    body = &fb;
    cur_func = s;
    scope_push();
    for (int i = 0; i < s->nparams; i++) {
        Sym *p = new_sym(s->params[i].name, SY_VAR, r->loc);
        p->ty = s->params[i].ty;
        p->is_varparam = s->params[i].is_var;
        p->cname = xfmt("a_%s", p->name);
        if (lookup_innermost(p->name))
            fatal(r->loc, "duplicate parameter '%s'", p->name);
        define(p);
    }
    Buf locals = { 0 };
    indent = 1;
    if (s->ty) {
        line("%s pres;", ctype(s->ty));
        line("memset(&pres, 0, sizeof pres);");
    }
    Buf *hold = body;
    body = &locals;
    process_sections(&r->decls, 1);
    body = hold;
    if (locals.p)
        buf_put(body, locals.p);
    for (int i = 0; i < r->body->stmts.n; i++)
        gen_stmt(r->body->stmts.p[i]);
    if (s->ty)
        line("return pres;");
    indent = 0;
    scope_pop();
    cur_func = NULL;
    body = saved;
    buf_printf(&out, "\n%s%s\n{\n", is_exported(s) ? "" : "static ", prototype(s, 1));
    if (fb.p)
        buf_put(&out, fb.p);
    buf_put(&out, "}\n");
}

static void routine_decl(Routine *r)
{
    Sym *old = lookup_innermost(r->name);
    if (iface_unit) {
        if (old) {
            if (old->kind == SY_ROUTINE && old->is_c && r->is_c)
                return;         /* the same C function, declared again */
            fatal(r->loc, "duplicate declaration of '%s'", r->name);
        }
        Sym *s = new_sym(r->name, SY_ROUTINE, r->loc);
        s->routine = r;
        s->from_iface = 1;
        s->owner = xstrdup(iface_unit);
        s->is_c = r->is_c;
        s->unit_level = 1;
        signature(r, s);
        if (r->is_c)
            check_c_signature(r, s);
        s->cname = r->is_c ? xfmt("c_%s", r->orig) : xfmt("p_%s", r->name);
        define(s);
        if (r->is_c)
            buf_printf(&out, "extern %s __asm__(\"%s\");\n", prototype(s, 0), r->orig);
        else
            buf_printf(&out, "extern %s;\n", prototype(s, 0));
        return;
    }
    if (r->is_c && !r->is_extern)
        unsupported(r->loc, "[C] routine that is not EXTERN");
    if (old) {
        if (old->kind == SY_ROUTINE && old->is_c && r->is_c)
            return;
        if (old->kind != SY_ROUTINE || old->is_c || r->is_c || old->defined || r->is_extern
            || !(old->routine->is_forward || is_exported(old)) || (r->is_forward && old->routine->is_forward))
            fatal(r->loc, "duplicate declaration of '%s'", r->name);
        /* The body of a FORWARD or interface routine. A repeated parameter
         * list must match; an omitted one takes the first. */
        if (r->has_params || r->result) {
            Sym tmp = { 0 };
            signature(r, &tmp);
            int ok = tmp.nparams == old->nparams && (!tmp.ty || same_type(tmp.ty, old->ty));
            for (int i = 0; ok && i < tmp.nparams; i++)
                ok = tmp.params[i].is_var == old->params[i].is_var && same_type(tmp.params[i].ty, old->params[i].ty)
                    && strcmp(tmp.params[i].name, old->params[i].name) == 0;
            if (!ok)
                fatal(r->loc, "heading of '%s' does not match its earlier declaration", r->name);
        }
        if (r->is_forward)
            return;             /* an exported routine, declared FORWARD too */
        old->defined = 1;
        emit_body(old, r);
        return;
    }
    Sym *s = new_sym(r->name, SY_ROUTINE, r->loc);
    s->routine = r;
    s->is_c = r->is_c;
    s->unit_level = 1;
    signature(r, s);
    if (r->is_c)
        check_c_signature(r, s);
    s->cname = r->is_c ? xfmt("c_%s", r->orig) : xfmt("p_%s", r->name);
    define(s);
    if (r->is_c) {
        buf_printf(&out, "extern %s __asm__(\"%s\");\n", prototype(s, 0), r->orig);
    } else if (r->is_forward) {
        buf_printf(&out, "static %s;\n", prototype(s, 0));
    } else if (r->is_extern) {
        unsupported(r->loc, "EXTERN routine without [C]");
    } else {
        s->defined = 1;
        emit_body(s, r);
    }
}

static void const_section(Decl *d)
{
    for (int i = 0; i < d->items.n; i++) {
        ConstDecl *c = d->items.p[i];
        Sym *v = const_eval(c->val);
        Sym *old = lookup_innermost(c->name);
        if (old) {
            if (old->kind == SY_CONST && old->from_iface && !iface_unit)
                continue;       /* an interface constant, repeated */
            fatal(c->loc, "duplicate declaration of '%s'", c->name);
        }
        Sym *s = new_sym(c->name, SY_CONST, c->loc);
        s->ty = v->ty;
        s->ival = v->ival;
        s->rval = v->rval;
        s->sval = v->sval;
        s->slen = v->slen;
        s->from_iface = iface_unit != NULL;
        define(s);
    }
}

static void type_section(Decl *d)
{
    for (int i = 0; i < d->items.n; i++) {
        TypeDecl *t = d->items.p[i];
        Sym *old = lookup_innermost(t->name);
        if (old) {
            if (old->kind == SY_TYPE && old->from_iface && !iface_unit)
                continue;       /* an interface type, repeated */
            fatal(t->loc, "duplicate declaration of '%s'", t->name);
        }
        Sym *s = new_sym(t->name, SY_TYPE, t->loc);
        s->from_iface = iface_unit != NULL;
        s->ty = resolve_type(t->te);
        define(s);
    }
    resolve_pending_pointers();
}

static void var_section(Decl *d, int local)
{
    for (int i = 0; i < d->items.n; i++) {
        VarDecl *v = d->items.p[i];
        Type *t = resolve_type(v->te);
        const char *ct = ctype(t);
        for (int j = 0; j < v->names.n; j++) {
            char *name = v->names.p[j];
            Sym *old = lookup_innermost(name);
            if (local) {
                if (old)
                    fatal(v->loc, "duplicate declaration of '%s'", name);
                Sym *s = new_sym(name, SY_VAR, v->loc);
                s->ty = t;
                s->cname = xfmt("l_%s", name);
                define(s);
                line("%s %s;", ct, s->cname);
                line("memset(&%s, 0, sizeof %s);", s->cname, s->cname);
                continue;
            }
            if (old) {
                if (old->kind == SY_VAR && is_exported(old) && !iface_unit && !old->defined) {
                    if (!same_type(old->ty, t))
                        fatal(v->loc, "'%s' is redeclared with a different type", name);
                    old->defined = 1;
                    buf_printf(&out, "%s %s;\n", ct, old->cname);
                    continue;
                }
                fatal(v->loc, "duplicate declaration of '%s'", name);
            }
            Sym *s = new_sym(name, SY_VAR, v->loc);
            s->ty = t;
            s->cname = xfmt("p_%s", name);
            s->unit_level = 1;
            if (iface_unit) {
                s->from_iface = 1;
                s->owner = xstrdup(iface_unit);
                buf_printf(&out, "extern %s %s;\n", ct, s->cname);
            } else {
                buf_printf(&out, "static %s %s;\n", ct, s->cname);
            }
            define(s);
        }
    }
}

static void process_sections(Vec *decls, int local)
{
    for (int i = 0; i < decls->n; i++) {
        Decl *d = decls->p[i];
        switch (d->kind) {
        case D_CONST:
            const_section(d);
            break;
        case D_TYPE:
            type_section(d);
            break;
        case D_VAR:
            var_section(d, local);
            break;
        case D_ROUTINE:
            if (local)
                unsupported(d->loc, "nested routine");
            routine_decl(d->routine);
            break;
        }
    }
}

/* ---- the unit model ---- */

static Interface *find_iface(const char *unit)
{
    for (int i = 0; i < comp->ifaces.n; i++) {
        Interface *in = comp->ifaces.p[i];
        if (strcmp(in->unit, unit) == 0)
            return in;
    }
    return NULL;
}

/* Mark the units a PROGRAM reaches through USES, as the native compiler's
 * BuildUnitInitOrder does: only units whose interface this compiland
 * splices take part, and a USES naming any other unit is skipped. */
static void mark_used(const char *unit, char *used)
{
    for (int i = 0; i < comp->ifaces.n; i++) {
        Interface *in = comp->ifaces.p[i];
        if (strcmp(in->unit, unit) == 0) {
            if (used[i])
                return;
            used[i] = 1;
            for (int j = 0; j < in->uses.n; j++)
                mark_used(in->uses.p[j], used);
            return;
        }
    }
}

int translate(Compiland *c, FILE *f, int check_only)
{
    comp = c;
    if (!c->name) {
        /* A bare interface file: it parsed, and its USES name units that
         * only a real compiland splices in, so there is nothing to check. */
        if (check_only)
            return 0;
        fatal(c->loc, "no PROGRAM or IMPLEMENTATION");
    }
    body = &out;
    sem_init();
    scope_push();               /* the compiland's own scope */

    for (int i = 0; i < c->ifaces.n; i++) {
        Interface *in = c->ifaces.p[i];
        for (int j = 0; j < i; j++)
            if (strcmp(((Interface *) c->ifaces.p[j])->unit, in->unit) == 0)
                fatal(in->loc, "interface of unit '%s' included twice", in->unit);
        for (int j = 0; j < in->uses.n; j++)
            if (find_iface(in->uses.p[j]) == in)
                fatal(in->loc, "unit %s USES itself", in->unit);
        buf_printf(&out, "\n/* INTERFACE; UNIT %s */\n", in->unit);
        iface_unit = in->unit;
        process_sections(&in->decls, 0);
        iface_unit = NULL;
    }
    if (!c->name) {
        /* A bare interface file: checked, nothing to emit. */
        if (check_only)
            return 0;
        fatal(c->loc, "no PROGRAM or IMPLEMENTATION");
    }
    char *used = xmalloc((size_t) c->ifaces.n + 1);
    for (int j = 0; j < c->uses.n; j++)
        mark_used(c->uses.p[j], used);
    if (!c->is_program) {
        impl_unit = c->name;
        if (!find_iface(c->name))
            fatal(c->loc, "IMPLEMENTATION OF %s without its interface", c->name);
    }
    buf_printf(&out, "\n/* %s %s */\n", c->is_program ? "PROGRAM" : "IMPLEMENTATION OF", c->name);
    process_sections(&c->decls, 0);

    /* Every exported routine needs a body. */
    for (int i = 0; impl_unit && i < c->ifaces.n; i++) {
        Interface *in = c->ifaces.p[i];
        if (strcmp(in->unit, impl_unit) != 0)
            continue;
        for (int j = 0; j < in->decls.n; j++) {
            Decl *d = in->decls.p[j];
            if (d->kind != D_ROUTINE || d->routine->is_c)
                continue;
            Sym *s = lookup(d->routine->name);
            if (!s->defined)
                fatal(d->routine->loc, "'%s' is declared in the interface but never defined", s->name);
        }
    }

    Buf mb = { 0 };
    body = &mb;
    indent = 1;
    if (c->is_program) {
        in_main = 1;
        for (int i = 0; i < c->ifaces.n; i++)
            if (used[i])
                buf_printf(&out, "void pascal_init_%s(void);\n", ((Interface *) c->ifaces.p[i])->unit);
        line("pas_args_init(argc, argv);");
        for (int i = 0; i < c->ifaces.n; i++)
            if (used[i])
                line("pascal_init_%s();", ((Interface *) c->ifaces.p[i])->unit);
    }
    for (int i = 0; i < c->body->stmts.n; i++)
        gen_stmt(c->body->stmts.p[i]);
    if (c->is_program) {
        line("return 0;");
        buf_printf(&out, "\nint main(int argc, char **argv)\n{\n%s}\n", mb.p);
    } else {
        buf_printf(&out, "\nvoid pascal_init_%s(void)\n{\n%s}\n", c->name, mb.p ? mb.p : "");
    }

    if (check_only)
        return 0;
    fprintf(f, "/* Generated by pasboot from %s. Do not edit. */\n#include \"prelude.h\"\n\n", c->loc.file);
    if (types_buf.p)
        fputs(types_buf.p, f);
    if (out.p)
        fputs(out.p, f);
    return 0;
}
