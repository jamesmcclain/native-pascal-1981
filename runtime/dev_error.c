/* NVPTX device error channel: host side of the error cell.
 *
 * Device code compiled for NVPTX has no host failure path. A failing device
 * check (today TRUNC/ROUND out of INTEGER range) claims the module global
 * __pas_dev_error with a compare-and-swap, records its location and operand,
 * and the thread continues with a defined value. cuda_launch.c reads the cell
 * after each launch completes and hands it to this routine, which prints
 * exactly what the host check prints and fails the same way.
 *
 * It lives in the shared core (not in cuda_launch.c) so that it builds and is
 * unit-tested without the CUDA toolkit.
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "pascalrt.h"

_Bool pas_dev_error_file_symbol(int32_t file, char *buf, size_t size)
{
    int n;

    if (file <= 0 || size == 0)
        return 0;
    n = snprintf(buf, size, PAS_DEV_FILE_SYMBOL "%" PRId32, file);
    return n > 0 && (size_t) n < size;
}

void pas_dev_error_report(const pas_dev_error_cell *cell, const char *file)
{
    if (!cell || cell->code == PAS_DEV_ERROR_NONE)
        return;
    /* The host routines below print it through pas_diag_where(), as for a
     * failure in host code from the same included file. */
    pas_diag_file = (cell->file > 0) ? file : NULL;
    switch (cell->code) {
    case PAS_DEV_ERROR_TRUNC:
        pas_conversion_error(0, cell->value, cell->line, cell->column);
    case PAS_DEV_ERROR_ROUND:
        pas_conversion_error(1, cell->value, cell->line, cell->column);
    default:
        /* A code this runtime does not know (a newer compiler's check):
         * still fail rather than drop the error. */
        fflush(stdout);
        fprintf(stderr, "runtime error: device check %" PRId32 " failed at line %" PRId32 " column %" PRId32 "%s\n", cell->code, cell->line, cell->column, pas_diag_where());
        fflush(stderr);
        abort();
    }
}
