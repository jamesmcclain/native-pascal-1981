{ INTERFACE header for jsonx, JSON for payloads that outgrow an LSTRING.

  jsonutil already wraps cJSON for the compiler stages, and it stays exactly
  as it is: every bootstrap stage depends on it, so it is the last file in the
  tree that should be disturbed. What it cannot do is carry a value longer
  than 255 characters -- its GetStr returns a Str255 and silently clamps --
  and it has no serializer and no array construction, because an AST walker
  never needed either.

  This unit supplies those three things over a ByteBuf, so a completion, a
  source buffer, or a whole request body can go in and come back out intact.
  It deliberately does not USES jsonutil: sharing would mean two names for
  LSTRING(255) meeting at every call site for no gain, and the handful of
  duplicated EXTERN declarations costs nothing at link time.

  Ownership follows cJSON's own rules, which are easy to get wrong from
  Pascal, where there is nothing to free a value at end of scope:

  * JxParse and JxNewObject/JxNewArray/JxNewString/JxNewNumber return nodes
    the caller owns and must eventually pass to JxDelete.
  * JxAddItem and JxArrAppend hand ownership of the item to its parent.
    Deleting the parent deletes it; deleting it separately is a double free.
  * JxGet, JxArrItem and JxStrRaw return borrowed pointers into the tree.
    They are valid until the tree is deleted and must never be freed.

  Requires bytebuf. }

INTERFACE;
UNIT jsonx (JxParse, JxParseBuf, JxDelete, JxPrintToBuf,
            JxIsObject, JxIsArray, JxIsString, JxIsNumber, JxIsBool,
            JxIsNull, JxIsTrue,
            JxGet, JxHas, JxArrSize, JxArrItem,
            JxStrRaw, JxStrLen, JxStrToBuf, JxGetStrToBuf,
            JxGetNum, JxGetInt, JxGetStr, JxNumValue, JxIntValue,
            JxNewObject, JxNewArray, JxNewStr, JxNewStrFromBuf, JxNewNum,
            JxArrAppend, JxAddItem, JxAddStr, JxAddStrFromBuf,
            JxAddNum, JxAddInt);

USES bytebuf;

{ ---- Parsing and printing ---- }

{ Parse a NUL-terminated C string. Returns NIL on malformed input, which is a
  normal outcome for anything arriving off a socket, not a reason to abort. }
FUNCTION JxParse(text: ADRMEM): ADRMEM;

{ Parse the contents of a ByteBuf. The buffer is NUL-terminated in place, so
  it must hold no embedded NUL -- valid JSON never does. }
FUNCTION JxParseBuf(VAR b: ByteBuf): ADRMEM;

PROCEDURE JxDelete(node: ADRMEM);

{ Serialize compactly and append to `out`. Returns FALSE if cJSON could not
  print the tree. This is the gap that matters most: without it a payload can
  be built but not sent. }
FUNCTION JxPrintToBuf(node: ADRMEM; VAR out: ByteBuf): BOOLEAN;

{ ---- Inspection ---- }

{ Type predicates over real cJSON types. Note that jsonutil's NodeType is a
  different thing entirely: it reads the "type" *field* of an AST node. A NIL
  node answers FALSE to all of these, so an absent key needs no separate
  test. }
FUNCTION JxIsObject(node: ADRMEM): BOOLEAN;
FUNCTION JxIsArray(node: ADRMEM): BOOLEAN;
FUNCTION JxIsString(node: ADRMEM): BOOLEAN;
FUNCTION JxIsNumber(node: ADRMEM): BOOLEAN;
FUNCTION JxIsBool(node: ADRMEM): BOOLEAN;
FUNCTION JxIsNull(node: ADRMEM): BOOLEAN;
FUNCTION JxIsTrue(node: ADRMEM): BOOLEAN;

{ Borrowed child by key, or NIL. }
FUNCTION JxGet(obj: ADRMEM; key: ByteStr): ADRMEM;
FUNCTION JxHas(obj: ADRMEM; key: ByteStr): BOOLEAN;
FUNCTION JxArrSize(arr: ADRMEM): INTEGER32;
FUNCTION JxArrItem(arr: ADRMEM; i: INTEGER32): ADRMEM;

{ The raw characters of a string node, borrowed and NUL-terminated, or NIL
  when the node is not a string. This is the non-truncating read: whatever
  the length, nothing is copied and nothing is lost. }
FUNCTION JxStrRaw(node: ADRMEM): ADRMEM;
FUNCTION JxStrLen(node: ADRMEM): INTEGER32;

{ A number node's value, 0.0 for anything else. The node-level counterpart of
  JxGetNum, for a value already fetched -- checking a node's type and then
  reading it should not require going back to the parent by key. }
FUNCTION JxNumValue(node: ADRMEM): REAL;

{ A number node as a 32-bit integer, truncated toward zero, 0 for anything
  else. Not TRUNC: TRUNC produces this dialect's 16-bit INTEGER, so a value of
  65536 comes back through it as 0 -- silently, and far from where it was
  read. Out-of-range values clamp, so a caller testing whether a value is
  integral sees the clamp and rejects it. }
FUNCTION JxIntValue(node: ADRMEM): INTEGER32;

{ Append a string node's value to `out`. Returns FALSE when the node is not a
  string, leaving `out` untouched. }
FUNCTION JxStrToBuf(node: ADRMEM; VAR out: ByteBuf): BOOLEAN;
FUNCTION JxGetStrToBuf(obj: ADRMEM; key: ByteStr; VAR out: ByteBuf): BOOLEAN;

{ Convenience reads for values known to be short. JxGetStr truncates at 255
  exactly as jsonutil does, and is for identifiers and enumerated values --
  a model name, a finish_reason -- never for content. }
FUNCTION JxGetNum(obj: ADRMEM; key: ByteStr): REAL;
FUNCTION JxGetInt(obj: ADRMEM; key: ByteStr): INTEGER32;
PROCEDURE JxGetStr(obj: ADRMEM; key: ByteStr; VAR out: ByteStr);

{ ---- Building ---- }

FUNCTION JxNewObject: ADRMEM;
FUNCTION JxNewArray: ADRMEM;
FUNCTION JxNewStr(s: ByteStr): ADRMEM;
FUNCTION JxNewStrFromBuf(VAR b: ByteBuf): ADRMEM;
FUNCTION JxNewNum(v: REAL): ADRMEM;

PROCEDURE JxArrAppend(arr: ADRMEM; item: ADRMEM);
PROCEDURE JxAddItem(obj: ADRMEM; key: ByteStr; item: ADRMEM);
PROCEDURE JxAddStr(obj: ADRMEM; key: ByteStr; val: ByteStr);
PROCEDURE JxAddStrFromBuf(obj: ADRMEM; key: ByteStr; VAR val: ByteBuf);
PROCEDURE JxAddNum(obj: ADRMEM; key: ByteStr; val: REAL);
PROCEDURE JxAddInt(obj: ADRMEM; key: ByteStr; val: INTEGER32);

END;
