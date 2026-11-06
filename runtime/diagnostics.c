#include <stdio.h>

#include "pascalrt.h"

/* Native compiler stages use stdout as an inter-stage JSON channel. */
void pas_eprint(const char *message)
{
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}

/* The source file of the located runtime failure being reported, or NULL
 * for the primary file. Generated code stores it on a failure path just
 * before calling the reporting routine, and only for a location inside an
 * $INCLUDEd file (docs/dialect_notes.md, "Source locations in included
 * files"). Thread-local: CPU DEVICE kernels run on several threads. */
_Thread_local const char *pas_diag_file;

const char *pas_diag_where(void)
{
    static _Thread_local char text[300];

    if (pas_diag_file == NULL || pas_diag_file[0] == '\0')
        return "";
    snprintf(text, sizeof text, " of file %s", pas_diag_file);
    return text;
}
