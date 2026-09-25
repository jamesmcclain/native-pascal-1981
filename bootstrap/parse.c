/* Recursive-descent parser for the bootstrap subset. It builds the AST in
 * pasboot.h and rejects every construct outside the subset by name. */
#include <string.h>

#include "pasboot.h"

static Token *tk;
static int pos;

static Token *cur(void)
{
    return &tk[pos];
}

static Token *peek(int k)
{
    int i = pos;
    while (k-- > 0 && tk[i].kind != T_EOF)
        i++;
    return &tk[i];
}

static Loc here(void)
{
    return tk[pos].loc;
}

static int is_word(Token *t, const char *w)
{
    return t->kind == T_IDENT && strcmp(t->text, w) == 0;
}

static int at_word(const char *w)
{
    return is_word(cur(), w);
}

static int at_punct(int p)
{
    return cur()->kind == T_PUNCT && cur()->punct == p;
}

static const char *describe(Token *t)
{
    switch (t->kind) {
    case T_EOF:
        return "end of file";
    case T_IDENT:
        return xfmt("'%s'", t->orig);
    case T_INT:
        return "integer literal";
    case T_REAL:
        return "real literal";
    case T_STR:
        return "string literal";
    case T_CHAR:
        return "character literal";
    default:
        return xfmt("'%s'", punct_text(t->punct));
    }
}

static void __attribute__((noreturn)) expected(const char *what)
{
    fatal(here(), "expected %s, found %s", what, describe(cur()));
}

static void expect_word(const char *w)
{
    if (!at_word(w))
        expected(xfmt("'%s'", w));
    pos++;
}

static void expect_punct(int p)
{
    if (!at_punct(p))
        expected(xfmt("'%s'", punct_text(p)));
    pos++;
}

static int accept_word(const char *w)
{
    if (at_word(w)) {
        pos++;
        return 1;
    }
    return 0;
}

static int accept_punct(int p)
{
    if (at_punct(p)) {
        pos++;
        return 1;
    }
    return 0;
}

/* Words that can never be an identifier in the subset, and the reserved
 * words whose constructs the subset leaves out. */
static const char *reserved[] = {
    "and", "array", "begin", "case", "const", "div", "do", "downto", "else",
    "end", "for", "function", "goto", "if", "in", "label", "mod", "not", "of",
    "or", "packed", "procedure", "program", "record", "repeat", "set", "then",
    "to", "type", "until", "var", "while", "with", "interface", "implementation",
    "unit", "uses", "otherwise", "value", "module", "xor", NULL
};

static int is_reserved(Token *t)
{
    if (t->kind != T_IDENT)
        return 0;
    for (int i = 0; reserved[i]; i++)
        if (strcmp(t->text, reserved[i]) == 0)
            return 1;
    return 0;
}

static Token *ident(void)
{
    if (cur()->kind != T_IDENT || is_reserved(cur()))
        expected("identifier");
    return &tk[pos++];
}

static void ident_list(Vec *v)
{
    do {
        vec_push(v, ident()->text);
    } while (accept_punct(P_COMMA));
}

/* ---- expressions ---- */

static Expr *new_expr(int kind, Loc loc)
{
    Expr *e = xmalloc(sizeof *e);
    e->kind = kind;
    e->loc = loc;
    return e;
}

static Expr *expr(void);

static Expr *selectors(Expr *e)
{
    for (;;) {
        Loc loc = here();
        if (accept_punct(P_LBRACK)) {
            Expr *x = new_expr(E_INDEX, loc);
            x->a = e;
            x->b = expr();
            if (at_punct(P_COMMA))
                unsupported(here(), "multi-dimensional subscript");
            expect_punct(P_RBRACK);
            e = x;
        } else if (accept_punct(P_DOT)) {
            Expr *x = new_expr(E_FIELD, loc);
            x->a = e;
            x->name = ident()->text;
            e = x;
        } else if (accept_punct(P_CARET)) {
            Expr *x = new_expr(E_DEREF, loc);
            x->a = e;
            e = x;
        } else {
            return e;
        }
    }
}

static Expr *factor(void)
{
    Token *t = cur();
    Loc loc = t->loc;
    Expr *e;
    switch (t->kind) {
    case T_INT:
        pos++;
        e = new_expr(E_INT, loc);
        e->ival = t->ival;
        return e;
    case T_REAL:
        pos++;
        e = new_expr(E_REAL, loc);
        e->rval = t->rval;
        return e;
    case T_STR:
        pos++;
        e = new_expr(E_STR, loc);
        e->s = t->sval;
        e->slen = t->slen;
        return e;
    case T_CHAR:
        pos++;
        e = new_expr(E_CHAR, loc);
        e->ival = t->ival;
        return e;
    case T_PUNCT:
        if (accept_punct(P_LPAREN)) {
            e = expr();
            expect_punct(P_RPAREN);
            return selectors(e);
        }
        if (at_punct(P_LBRACK))
            unsupported(loc, "set constructor");
        expected("expression");
    case T_IDENT:
        if (accept_word("not")) {
            e = new_expr(E_UN, loc);
            e->op = OP_NOT;
            e->a = factor();
            return e;
        }
        if (is_word(t, "adr") && peek(1)->kind == T_IDENT) {
            pos++;
            e = new_expr(E_ADR, loc);
            e->name = ident()->text;
            if (at_punct(P_DOT) || at_punct(P_LBRACK) || at_punct(P_CARET))
                unsupported(here(), "ADR of anything but a bare identifier");
            return e;
        }
        if (is_word(t, "ads"))
            unsupported(loc, "ADS");
        if (is_reserved(t))
            expected("expression");
        pos++;
        if (at_punct(P_LPAREN)) {
            pos++;
            e = new_expr(E_CALL, loc);
            e->name = t->text;
            if (!at_punct(P_RPAREN)) {
                do {
                    vec_push(&e->args, expr());
                    if (at_punct(P_COLON))
                        unsupported(here(), "WRITE field width");
                } while (accept_punct(P_COMMA));
            }
            expect_punct(P_RPAREN);
            return selectors(e);
        }
        e = new_expr(E_NAME, loc);
        e->name = t->text;
        return selectors(e);
    default:
        expected("expression");
    }
}

static Expr *binary(int op, Expr *a, Expr *b, Loc loc)
{
    Expr *e = new_expr(E_BIN, loc);
    e->op = op;
    e->a = a;
    e->b = b;
    return e;
}

static Expr *term(void)
{
    Expr *e = factor();
    for (;;) {
        Loc loc = here();
        int op = 0;
        if (accept_punct(P_STAR)) {
            op = OP_MUL;
        } else if (accept_punct(P_SLASH)) {
            op = OP_RDIV;
        } else if (accept_word("div")) {
            op = OP_IDIV;
        } else if (accept_word("mod")) {
            op = OP_MOD;
        } else if (at_word("and") && !is_word(peek(1), "then")) {
            pos++;
            op = OP_AND;
        } else {
            return e;
        }
        e = binary(op, e, factor(), loc);
    }
}

static Expr *simple(void)
{
    Loc loc = here();
    Expr *e;
    if (accept_punct(P_MINUS)) {
        e = new_expr(E_UN, loc);
        e->op = OP_NEG;
        e->a = term();
    } else {
        accept_punct(P_PLUS);
        e = term();
    }
    for (;;) {
        loc = here();
        int op = 0;
        if (accept_punct(P_PLUS)) {
            op = OP_ADD;
        } else if (accept_punct(P_MINUS)) {
            op = OP_SUB;
        } else if (accept_word("or")) {
            if (at_word("else"))
                unsupported(here(), "OR ELSE");
            op = OP_OR;
        } else if (at_word("xor")) {
            unsupported(here(), "XOR");
        } else {
            return e;
        }
        e = binary(op, e, term(), loc);
    }
}

static Expr *expr(void)
{
    Expr *e = simple();
    Loc loc = here();
    int op = 0;
    if (accept_punct(P_EQ)) {
        op = OP_EQ;
    } else if (accept_punct(P_NE)) {
        op = OP_NE;
    } else if (accept_punct(P_LT)) {
        op = OP_LT;
    } else if (accept_punct(P_LE)) {
        op = OP_LE;
    } else if (accept_punct(P_GT)) {
        op = OP_GT;
    } else if (accept_punct(P_GE)) {
        op = OP_GE;
    } else if (at_word("in")) {
        unsupported(here(), "IN");
    } else {
        return e;
    }
    return binary(op, e, simple(), loc);
}

/* An IF or WHILE condition: the only place AND THEN may appear, binding
 * more loosely than any other operator, as in the native parser's
 * ParseBooleanExpression. */
static Expr *bool_expr(void)
{
    Expr *e = expr();
    for (;;) {
        Loc loc = here();
        if (at_word("and") && is_word(peek(1), "then")) {
            pos += 2;
            e = binary(OP_ANDTHEN, e, expr(), loc);
        } else if (at_word("or") && is_word(peek(1), "else")) {
            unsupported(loc, "OR ELSE");
        } else {
            return e;
        }
    }
}

/* ---- types ---- */

static TypeExpr *new_te(int kind, Loc loc)
{
    TypeExpr *t = xmalloc(sizeof *t);
    t->kind = kind;
    t->loc = loc;
    return t;
}

static TypeExpr *type_expr(void)
{
    Loc loc = here();
    TypeExpr *t;
    if (accept_punct(P_CARET)) {
        t = new_te(TE_POINTER, loc);
        t->name = ident()->text;
        return t;
    }
    if (accept_punct(P_LPAREN)) {
        t = new_te(TE_ENUM, loc);
        ident_list(&t->names);
        expect_punct(P_RPAREN);
        return t;
    }
    if (accept_word("array")) {
        t = new_te(TE_ARRAY, loc);
        if (!at_punct(P_LBRACK))
            unsupported(here(), "ARRAY without explicit bounds");
        pos++;
        t->lo = simple();
        if (!at_punct(P_DOTDOT))
            unsupported(here(), "array index type other than lo..hi");
        pos++;
        t->hi = simple();
        if (at_punct(P_COMMA))
            unsupported(here(), "multi-dimensional array");
        expect_punct(P_RBRACK);
        expect_word("of");
        t->elem = type_expr();
        return t;
    }
    if (accept_word("record")) {
        t = new_te(TE_RECORD, loc);
        while (!at_word("end")) {
            if (at_word("case"))
                unsupported(here(), "record variant part");
            FieldGroup *g = xmalloc(sizeof *g);
            g->loc = here();
            ident_list(&g->names);
            expect_punct(P_COLON);
            g->te = type_expr();
            vec_push(&t->fields, g);
            if (!accept_punct(P_SEMI))
                break;
        }
        expect_word("end");
        return t;
    }
    if (at_word("packed"))
        unsupported(loc, "PACKED");
    if (at_word("set"))
        unsupported(loc, "SET type");
    if (at_word("file"))
        unsupported(loc, "FILE type");
    if (at_word("string") && peek(1)->kind == T_PUNCT && peek(1)->punct == P_LPAREN)
        unsupported(loc, "STRING(n)");
    if (at_word("super"))
        unsupported(loc, "SUPER ARRAY");
    if (at_word("vector"))
        unsupported(loc, "VECTOR");
    if (at_word("ads") || at_word("adr"))
        unsupported(loc, "ADS/ADR type");
    if (cur()->kind != T_IDENT)
        unsupported(loc, "subrange type");
    if (at_word("lstring")) {
        pos++;
        t = new_te(TE_LSTRING, loc);
        expect_punct(P_LPAREN);
        t->lo = expr();
        expect_punct(P_RPAREN);
        return t;
    }
    t = new_te(TE_NAME, loc);
    t->name = ident()->text;
    if (at_punct(P_DOTDOT))
        unsupported(loc, "subrange type");
    return t;
}

/* ---- statements ---- */

static Stmt *new_stmt(int kind, Loc loc)
{
    Stmt *s = xmalloc(sizeof *s);
    s->kind = kind;
    s->loc = loc;
    return s;
}

static Stmt *statement(void);

static void stmt_list(Vec *v)
{
    do {
        vec_push(v, statement());
    } while (accept_punct(P_SEMI));
}

static Stmt *statement(void)
{
    Loc loc = here();
    Token *t = cur();
    Stmt *s;
    if (t->kind == T_INT)
        unsupported(loc, "labelled statement");
    if (t->kind != T_IDENT)
        return new_stmt(S_EMPTY, loc);
    if (accept_word("begin")) {
        s = new_stmt(S_BLOCK, loc);
        stmt_list(&s->stmts);
        expect_word("end");
        return s;
    }
    if (accept_word("if")) {
        s = new_stmt(S_IF, loc);
        s->cond = bool_expr();
        expect_word("then");
        s->then = statement();
        if (accept_word("else"))
            s->els = statement();
        return s;
    }
    if (accept_word("while")) {
        s = new_stmt(S_WHILE, loc);
        s->cond = bool_expr();
        expect_word("do");
        s->body = statement();
        return s;
    }
    if (accept_word("for")) {
        s = new_stmt(S_FOR, loc);
        if (at_word("static"))
            unsupported(here(), "FOR STATIC");
        s->varloc = here();
        s->var = ident()->text;
        expect_punct(P_ASSIGN);
        s->from = expr();
        if (accept_word("downto")) {
            s->down = 1;
        } else {
            expect_word("to");
        }
        s->to = expr();
        expect_word("do");
        s->body = statement();
        return s;
    }
    if (at_word("repeat"))
        unsupported(loc, "REPEAT");
    if (at_word("case"))
        unsupported(loc, "CASE");
    if (at_word("with"))
        unsupported(loc, "WITH");
    if (at_word("goto"))
        unsupported(loc, "GOTO");
    if (at_word("end") || at_word("else"))
        return new_stmt(S_EMPTY, loc);
    Token *nx = peek(1);
    int assigns = nx->kind == T_PUNCT && nx->punct == P_ASSIGN;
    if (!assigns) {
        if (is_word(t, "return") || is_word(t, "break") || is_word(t, "cycle")) {
            pos++;
            s = new_stmt(is_word(t, "return") ? S_RETURN : is_word(t, "break") ? S_BREAK : S_CYCLE, loc);
            if (cur()->kind == T_IDENT && !at_word("end") && !at_word("else"))
                unsupported(here(), "labelled BREAK/CYCLE/RETURN");
            return s;
        }
    }
    if (is_reserved(t))
        expected("statement");
    if (nx->kind == T_PUNCT && nx->punct == P_COLON)
        unsupported(loc, "labelled statement");
    Expr *lhs = factor();
    if (accept_punct(P_ASSIGN)) {
        s = new_stmt(S_ASSIGN, loc);
        s->lhs = lhs;
        s->rhs = expr();
        return s;
    }
    if (lhs->kind != E_NAME && lhs->kind != E_CALL)
        expected("':='");
    s = new_stmt(S_CALL, loc);
    s->lhs = lhs;
    return s;
}

/* ---- declarations ---- */

static Decl *new_decl(int kind, Loc loc)
{
    Decl *d = xmalloc(sizeof *d);
    d->kind = kind;
    d->loc = loc;
    return d;
}

static int at_ident_then(int p)
{
    Token *n = peek(1);
    return cur()->kind == T_IDENT && !is_reserved(cur()) && n->kind == T_PUNCT && n->punct == p;
}

static Decl *const_section(void)
{
    Decl *d = new_decl(D_CONST, here());
    pos++;
    do {
        ConstDecl *c = xmalloc(sizeof *c);
        c->loc = here();
        c->name = ident()->text;
        expect_punct(P_EQ);
        c->val = expr();
        expect_punct(P_SEMI);
        vec_push(&d->items, c);
    } while (at_ident_then(P_EQ));
    return d;
}

static Decl *type_section(void)
{
    Decl *d = new_decl(D_TYPE, here());
    pos++;
    do {
        TypeDecl *t = xmalloc(sizeof *t);
        t->loc = here();
        t->name = ident()->text;
        expect_punct(P_EQ);
        t->te = type_expr();
        expect_punct(P_SEMI);
        vec_push(&d->items, t);
    } while (at_ident_then(P_EQ));
    return d;
}

static Decl *var_section(void)
{
    Decl *d = new_decl(D_VAR, here());
    pos++;
    do {
        VarDecl *v = xmalloc(sizeof *v);
        v->loc = here();
        ident_list(&v->names);
        expect_punct(P_COLON);
        v->te = type_expr();
        if (at_punct(P_LBRACK))
            unsupported(here(), "variable attribute");
        if (at_punct(P_EQ))
            unsupported(here(), "variable initializer");
        expect_punct(P_SEMI);
        vec_push(&d->items, v);
    } while (at_ident_then(P_COMMA) || at_ident_then(P_COLON));
    return d;
}

static int at_section(void)
{
    return at_word("const") || at_word("type") || at_word("var");
}

static Decl *section(void)
{
    if (at_word("const"))
        return const_section();
    if (at_word("type"))
        return type_section();
    return var_section();
}

/* A routine heading, through the semicolon that ends it and any attribute
 * list before that semicolon. */
static Routine *routine_heading(void)
{
    Routine *r = xmalloc(sizeof *r);
    r->loc = here();
    r->is_func = at_word("function");
    pos++;
    Token *n = ident();
    r->name = n->text;
    r->orig = n->orig;
    if (accept_punct(P_LPAREN)) {
        r->has_params = 1;
        do {
            ParamGroup *g = xmalloc(sizeof *g);
            g->loc = here();
            if (accept_word("var")) {
                g->is_var = 1;
            } else if (at_word("vars") || at_word("const") || at_word("consts")) {
                unsupported(here(), xfmt("%s parameter", cur()->orig));
            } else if (at_word("procedure") || at_word("function")) {
                unsupported(here(), "procedural parameter");
            }
            ident_list(&g->names);
            expect_punct(P_COLON);
            g->te = type_expr();
            vec_push(&r->params, g);
        } while (accept_punct(P_SEMI));
        expect_punct(P_RPAREN);
    }
    if (r->is_func && accept_punct(P_COLON))
        r->result = type_expr();
    if (accept_punct(P_LBRACK)) {
        Token *a = ident();
        if (strcmp(a->text, "c") != 0 || !at_punct(P_RBRACK))
            unsupported(a->loc, xfmt("routine attribute [%s]", a->orig));
        pos++;
        r->is_c = 1;
    }
    expect_punct(P_SEMI);
    return r;
}

static Decl *routine_decl(int in_interface)
{
    Loc loc = here();
    Routine *r = routine_heading();
    Decl *d = new_decl(D_ROUTINE, loc);
    d->routine = r;
    if (in_interface)
        return d;
    if (accept_word("forward")) {
        r->is_forward = 1;
        expect_punct(P_SEMI);
        return d;
    }
    if (accept_word("extern") || accept_word("external")) {
        r->is_extern = 1;
        expect_punct(P_SEMI);
        return d;
    }
    if (r->is_c)
        unsupported(loc, "[C] routine with a body");
    while (at_section())
        vec_push(&r->decls, section());
    if (at_word("procedure") || at_word("function"))
        unsupported(here(), "nested routine");
    if (at_word("label"))
        unsupported(here(), "LABEL");
    expect_word("begin");
    r->has_body = 1;
    r->body = new_stmt(S_BLOCK, loc);
    stmt_list(&r->body->stmts);
    expect_word("end");
    expect_punct(P_SEMI);
    return d;
}

static void uses_clause(Vec *v)
{
    while (accept_word("uses")) {
        ident_list(v);
        expect_punct(P_SEMI);
    }
}

static Interface *interface(void)
{
    Interface *in = xmalloc(sizeof *in);
    in->loc = here();
    expect_word("interface");
    expect_punct(P_SEMI);
    expect_word("unit");
    in->unit = ident()->text;
    if (accept_punct(P_LPAREN)) {
        /* The export list: every interface declaration is treated as
         * visible, so the names only need to parse. */
        Vec names = { 0 };
        ident_list(&names);
        expect_punct(P_RPAREN);
    }
    expect_punct(P_SEMI);
    uses_clause(&in->uses);
    for (;;) {
        if (at_section()) {
            vec_push(&in->decls, section());
        } else if (at_word("procedure") || at_word("function")) {
            vec_push(&in->decls, routine_decl(1));
        } else if (at_word("label")) {
            unsupported(here(), "LABEL");
        } else {
            break;
        }
    }
    expect_word("end");
    expect_punct(P_SEMI);
    return in;
}

Compiland *parse_compiland(Token *toks, int ntok)
{
    (void) ntok;
    tk = toks;
    pos = 0;
    Compiland *c = xmalloc(sizeof *c);
    while (at_word("interface"))
        vec_push(&c->ifaces, interface());
    c->loc = here();
    if (cur()->kind == T_EOF && c->ifaces.n > 0)
        return c;               /* a bare .inc: interfaces only */
    if (accept_word("program")) {
        c->is_program = 1;
        c->name = ident()->text;
        if (accept_punct(P_LPAREN)) {
            Vec files = { 0 };
            ident_list(&files);
            expect_punct(P_RPAREN);
        }
    } else if (accept_word("implementation")) {
        expect_word("of");
        c->name = ident()->text;
    } else if (at_word("module")) {
        unsupported(here(), "MODULE compiland");
    } else if (at_word("device")) {
        unsupported(here(), "DEVICE compiland");
    } else {
        expected("PROGRAM or IMPLEMENTATION");
    }
    expect_punct(P_SEMI);
    uses_clause(&c->uses);
    for (;;) {
        if (at_section()) {
            vec_push(&c->decls, section());
        } else if (at_word("procedure") || at_word("function")) {
            vec_push(&c->decls, routine_decl(0));
        } else if (at_word("label")) {
            unsupported(here(), "LABEL");
        } else if (at_word("uses")) {
            uses_clause(&c->uses);
        } else {
            break;
        }
    }
    Loc bl = here();
    expect_word("begin");
    c->body = new_stmt(S_BLOCK, bl);
    stmt_list(&c->body->stmts);
    expect_word("end");
    expect_punct(P_DOT);
    if (cur()->kind != T_EOF)
        fatal(here(), "text after the final 'END.'");
    return c;
}
