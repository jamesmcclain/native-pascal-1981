/* MATHCK runtime failures.
 *
 * pas_math_zero: mandatory scalar zero-divisor failure, including with
 * MATHCK disabled.
 * line/column are the operator token's; a legacy AST without an operator
 * snapshot passes 0:0. Operands are already evaluated and widened with
 * their own signedness.
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

void pas_math_zero(int32_t is_unsigned, int32_t is_mod, int64_t left, int64_t right, int32_t line, int32_t column)
{
    fflush(stdout);
    fprintf(stderr, "runtime error: MATHCK %s division by zero in %s at line %" PRId32 " column %" PRId32, is_unsigned ? "unsigned" : "signed", is_mod ? "MOD" : "DIV", line,
            column);
    if (is_unsigned)
        fprintf(stderr, " (left=%" PRIu64 ", right=%" PRIu64 ")\n", (uint64_t) left, (uint64_t) right);
    else
        fprintf(stderr, " (left=%" PRId64 ", right=%" PRId64 ")\n", left, right);
    fflush(stderr);
    abort();
}

/* MATHCK+ overflow: the exact result does not fit the operation's resolved
 * type. op: 0 +, 1 -, 2 *, 3 DIV, 4 unary -, 5 SUCC, 6 PRED, 7 ABS, 8 SQR,
 * 9 VSUM, 10 VPROD (integer VECTOR reductions: left is the partial result,
 * right the lane). The unary operations (4 through 8) report one operand and
 * ignore right. Operands are
 * already evaluated and widened with their own signedness; the failed
 * result is never stored or used.
 */
void pas_math_overflow(int32_t is_unsigned, int32_t op, int64_t left, int64_t right, int32_t line, int32_t column)
{
    static const char *const names[] = { "+", "-", "*", "DIV", "-", "SUCC", "PRED", "ABS", "SQR", "VSUM", "VPROD" };
    const char *name = (op >= 0 && op < 11) ? names[op] : "?";

    fflush(stdout);
    fprintf(stderr, "runtime error: MATHCK %s overflow in %s at line %" PRId32 " column %" PRId32, is_unsigned ? "unsigned" : "signed", name, line, column);
    if (op >= 4 && op <= 8) {
        if (is_unsigned)
            fprintf(stderr, " (operand=%" PRIu64 ")\n", (uint64_t) left);
        else
            fprintf(stderr, " (operand=%" PRId64 ")\n", left);
    } else if (is_unsigned)
        fprintf(stderr, " (left=%" PRIu64 ", right=%" PRIu64 ")\n", (uint64_t) left, (uint64_t) right);
    else
        fprintf(stderr, " (left=%" PRId64 ", right=%" PRId64 ")\n", left, right);
    fflush(stderr);
    abort();
}
