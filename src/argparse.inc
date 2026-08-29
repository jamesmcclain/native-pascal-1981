{ INTERFACE header for argparse, command-line option parsing for programs
  written in this dialect.

  Intended as a general runtime-library component rather than a helper for one
  tool: a program registers the options it accepts, calls ArgParse once, and
  then queries values by name. src/driver.pas's hand-rolled IF/ELSE chain over
  pas_arg_value is the pattern this replaces.

  ------------------------------------------------------------------------
  IMPORTANT -- a program using argparse must declare no program parameters
  beyond INPUT and OUTPUT:

      PROGRAM myprog(input, output);         <- correct
      PROGRAM myprog(input, output, count);  <- breaks flag parsing

  A program-heading parameter is a period-correct feature of this dialect
  (manual 13-5..13-7, implemented in runtime/cmdline.c): each one is bound
  positionally to argv[1], argv[2], ... during program initialization, before
  the main BEGIN runs, and when the token is absent the runtime prompts for it
  on stdin. So a heading parameter eats the very argv slots argparse wants,
  and a flag in that slot is read as a value for it. The observed failure is
  not a parse error but an abort during startup -- `./prog --verbose` against
  an INTEGER parameter dies with "runtime error: malformed integer input"
  before any of the program's own code executes, which gives no hint that the
  program heading is at fault.
  ------------------------------------------------------------------------

  Grammar accepted:

      --long value        --long=value        --flag
      -s value            -s=value            -f
      --                  (ends options; everything after is positional)

  Deliberately not supported, to stay implementable and period-appropriate:
  bundled short flags (-abc for -a -b -c), abbreviated/prefix matching of long
  names, repeated options accumulating a list, subcommands, and callbacks --
  the dialect has no procedural type, so a callback-style API is impossible
  here regardless.

  An option with no short form registers a space as its short_name. That is a
  plain literal rather than a named constant because this dialect's CONST
  section accepts only foldable integer and real values -- a CHAR or string
  CONST aborts codegen with "IntLiteralValue: not a foldable integer
  constant".

  Values are not copied. A parsed value is a pointer straight into the argv
  the C runtime holds, which lives for the life of the process, so a value of
  any length is available through ArgGetRaw without the 255-character ceiling
  an LSTRING would impose. ArgGetStr is the convenient form and truncates at
  255; use ArgGetRaw for anything that can be longer, such as a URL or a path.

  Spliced via (*$INCLUDE:'argparse.inc'*) into every USES argparse caller, and
  into argparse.pas itself ahead of its IMPLEMENTATION. }

INTERFACE;
UNIT argparse (ArgBegin, ArgFlag, ArgString, ArgInt, ArgReal,
               ArgParse, ArgHelpWanted, ArgError, ArgUsage,
               ArgGetFlag, ArgGetInt, ArgGetReal, ArgGetStr, ArgGetRaw,
               ArgWasGiven, ArgPosCount, ArgPosRaw, ArgPosStr);

CONST
  ARG_MAX_OPTIONS    = 32;
  ARG_MAX_POSITIONAL = 32;

TYPE
  ArgStr = LSTRING(255);

{ Registration. Call ArgBegin first; it resets all state, so a program may
  parse more than once (a test does). Registering more than ARG_MAX_OPTIONS
  options, or a duplicate long name, is a programming error and is reported
  through ArgError at ArgParse time rather than being silently ignored. }
PROCEDURE ArgBegin(program_name: ArgStr; description: ArgStr);
PROCEDURE ArgFlag(long_name: ArgStr; short_name: CHAR; help: ArgStr);
PROCEDURE ArgString(long_name: ArgStr; short_name: CHAR;
                    default_value: ArgStr; help: ArgStr);
PROCEDURE ArgInt(long_name: ArgStr; short_name: CHAR;
                 default_value: INTEGER32; help: ArgStr);
PROCEDURE ArgReal(long_name: ArgStr; short_name: CHAR;
                  default_value: REAL; help: ArgStr);

{ Parsing. ArgParse returns FALSE both for a bad command line and for --help;
  the two are told apart by ArgHelpWanted, so the caller chooses the exit
  status rather than having the unit call exit() on its behalf:

      IF NOT ArgParse THEN
      BEGIN
        IF ArgHelpWanted THEN exit(0);
        ArgError(msg);   -- describes the problem
        exit(2);
      END;

  ArgParse prints nothing itself except the help text, which goes to stdout
  when --help is given. }
FUNCTION ArgParse: BOOLEAN;
FUNCTION ArgHelpWanted: BOOLEAN;
PROCEDURE ArgError(VAR out: ArgStr);
PROCEDURE ArgUsage;

{ Queries. Asking for an option that was never registered, or with the wrong
  kind, yields that kind's zero value (FALSE / 0 / 0.0 / empty / NIL) rather
  than aborting. }
FUNCTION ArgGetFlag(long_name: ArgStr): BOOLEAN;
FUNCTION ArgGetInt(long_name: ArgStr): INTEGER32;
FUNCTION ArgGetReal(long_name: ArgStr): REAL;
PROCEDURE ArgGetStr(long_name: ArgStr; VAR out: ArgStr);
FUNCTION ArgGetRaw(long_name: ArgStr): ADRMEM;
FUNCTION ArgWasGiven(long_name: ArgStr): BOOLEAN;

{ Positional arguments, in command-line order, 0-based. }
FUNCTION ArgPosCount: INTEGER32;
FUNCTION ArgPosRaw(i: INTEGER32): ADRMEM;
PROCEDURE ArgPosStr(i: INTEGER32; VAR out: ArgStr);

END;
