{ INTERFACE header for bytebuf, a growable byte buffer for data that does not
  fit the dialect's LSTRING.

  An LSTRING(n) keeps its length in a single leading byte, so it can never
  hold more than 255 characters. HTTP bodies, JSON payloads and source buffers
  routinely run to tens of kilobytes, so none of them can be carried in one.
  A ByteBuf is the alternative the rest of this toolchain already reaches for
  by hand -- a malloc'd region plus an explicit INTEGER32 length, the shape
  jsonutil.pas's ReadAllStdin uses -- packaged so it need not be rewritten at
  every call site.

  Deliberately depends on no other unit, so that it can sit at the bottom of
  the layering: it defines its own ByteStr rather than borrowing jsonutil's
  Str255, which would drag a JSON library in behind it.

  Two rules shape everything here, both silent when broken:

  1. Bare INTEGER is 16 bits, so every length, capacity and offset is
     INTEGER32. A capacity that wrapped would turn into a malloc of a
     negative size and a segfault far from the cause. (Integer *literals*
     take their width from context and are fine at any size -- see
     docs/dialect_notes.md; the compiler bug that truncated them is fixed.)
  2. Pointers compare only with = and <>. There is no pointer subtraction and
     no relational comparison, so positions are carried as INTEGER32 indices
     against a base pointer, never as a wandering cursor compared against an
     end pointer.

  Spliced via (*$INCLUDE:'bytebuf.inc'*) into every USES bytebuf caller, and
  into bytebuf.pas itself ahead of its IMPLEMENTATION. }

INTERFACE;
UNIT bytebuf (BufInit, BufFree, BufClear, BufReserve,
              BufAppendChar, BufAppendStr, BufAppendCStr, BufAppendBytes,
              BufAppendBuf, BufAppendInt,
              BufLen, BufPtr, BufCStr, BufAt, BufSetAt, BufTruncate,
              BufIndexOfChar, BufIndexOfStr, BufMatchesStrAt,
              BufMatchesStrAtCI, BufSliceToStr, BufEqualsStr);

TYPE
  ByteStr = LSTRING(255);
  ByteBuf = RECORD
    data: ADRMEM;      { malloc'd region, or NIL before BufInit }
    len:  INTEGER32;   { bytes in use }
    cap:  INTEGER32;   { bytes allocated }
  END;

{ Lifecycle. BufInit rounds a request below the minimum up, so BufInit(b, 0)
  is a valid way to ask for a default-sized buffer. }
PROCEDURE BufInit(VAR b: ByteBuf; initial_cap: INTEGER32);
PROCEDURE BufFree(VAR b: ByteBuf);
PROCEDURE BufClear(VAR b: ByteBuf);
PROCEDURE BufReserve(VAR b: ByteBuf; need: INTEGER32);

{ Appending. }
PROCEDURE BufAppendChar(VAR b: ByteBuf; c: CHAR);
PROCEDURE BufAppendStr(VAR b: ByteBuf; s: ByteStr);
PROCEDURE BufAppendCStr(VAR b: ByteBuf; p: ADRMEM);
PROCEDURE BufAppendBytes(VAR b: ByteBuf; p: ADRMEM; n: INTEGER32);
PROCEDURE BufAppendBuf(VAR b: ByteBuf; VAR src: ByteBuf);
PROCEDURE BufAppendInt(VAR b: ByteBuf; v: INTEGER32);

{ Access. BufPtr is not NUL-terminated; BufCStr terminates in place and is the
  one to hand to a C function. Neither pointer survives the next append, which
  may reallocate. }
FUNCTION BufLen(VAR b: ByteBuf): INTEGER32;
FUNCTION BufPtr(VAR b: ByteBuf): ADRMEM;
FUNCTION BufCStr(VAR b: ByteBuf): ADRMEM;

{ An out-of-range index reads as CHR(0) rather than aborting: a parser that
  walks off the end of a truncated request then sees end-of-data and reports a
  bad request, which is what a server should do with a malformed message. }
FUNCTION BufAt(VAR b: ByteBuf; i: INTEGER32): CHAR;
PROCEDURE BufSetAt(VAR b: ByteBuf; i: INTEGER32; c: CHAR);
PROCEDURE BufTruncate(VAR b: ByteBuf; new_len: INTEGER32);

{ Searching and comparison. Both index functions return -1 when there is no
  match, and take a starting index so a scan can resume. The CI variant folds
  ASCII case only, which is what HTTP header names need. }
FUNCTION BufIndexOfChar(VAR b: ByteBuf; c: CHAR; from: INTEGER32): INTEGER32;
FUNCTION BufIndexOfStr(VAR b: ByteBuf; s: ByteStr; from: INTEGER32): INTEGER32;
FUNCTION BufMatchesStrAt(VAR b: ByteBuf; i: INTEGER32; s: ByteStr): BOOLEAN;
FUNCTION BufMatchesStrAtCI(VAR b: ByteBuf; i: INTEGER32; s: ByteStr): BOOLEAN;
FUNCTION BufEqualsStr(VAR b: ByteBuf; s: ByteStr): BOOLEAN;

{ Copy a slice out into an LSTRING. Anything past 255 characters is dropped,
  so this is for short, bounded things -- a header name, a method, a status
  token -- never for a body. }
PROCEDURE BufSliceToStr(VAR b: ByteBuf; from: INTEGER32; count: INTEGER32;
                        VAR out: ByteStr);

END;
