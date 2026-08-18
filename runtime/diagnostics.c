#include <stdio.h>

/* Native compiler stages use stdout as an inter-stage JSON channel. */
void pas_eprint(const char *message)
{
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}
