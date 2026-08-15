/*
 * Runtime support for primes.pas (1981 BYTE Sieve benchmark).
 *
 * The Pascal source declares:
 *     PROCEDURE fillc (loc: adrmem; len: word; val: char); extern;
 *
 * The compiler lowers that to an external function with signature
 *     i32 @fillc(i8*, i16, i8)
 * (procedures in this compiler nominally return i32; the Pascal side ignores
 * the result). We mirror that here by returning int so the declared and
 * defined return types agree.
 *
 * Semantics: fill `len` bytes starting at `loc` with the byte `val`
 * (a memset). The benchmark calls fillc(adr flags, sizeof(flags), chr(true))
 * to set every BOOLEAN in the array to TRUE before each sieve pass.
 */
#include <stddef.h>

#include "pascalrt.h"

int fillc(char *loc, unsigned short len, char val)
{
    for (unsigned short i = 0; i < len; i++) {
        loc[i] = val;
    }
    return 0;
}
