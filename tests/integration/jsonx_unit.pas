(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)
PROGRAM jsonx_unit(input, output);
{ jsonx over the three things jsonutil cannot do: serialize a tree, build an
  array, and carry a string longer than 255 characters.

  The long-string case is the one that matters. jsonutil's GetStr returns a
  Str255 and clamps silently, so a completion of any real size would come back
  quietly truncated and look like a model that stopped early. Here the value
  goes out and comes back through a ByteBuf and is checked by length, so a
  regression shows up as a number rather than as mysteriously short output. }
USES bytebuf, jsonx;

VAR
  payload, msgs, msg, parsed, choices, choice, content, part: ADRMEM;
  out, big, back: ByteBuf;
  s: ByteStr;
  i, n, mismatches: INTEGER32;
  c: CHAR;

BEGIN
  { ---- Build a chat-completions request payload and serialize it ---- }
  payload := JxNewObject;
  JxAddStr(payload, 'model', 'test-model');
  JxAddInt(payload, 'max_tokens', 256);
  JxAddNum(payload, 'temperature', 0.2);

  msgs := JxNewArray;
  msg := JxNewObject;
  JxAddStr(msg, 'role', 'system');
  JxAddStr(msg, 'content', 'be brief');
  JxArrAppend(msgs, msg);
  msg := JxNewObject;
  JxAddStr(msg, 'role', 'user');
  JxAddStr(msg, 'content', 'hello');
  JxArrAppend(msgs, msg);
  JxAddItem(payload, 'messages', msgs);

  BufInit(out, 0);
  WRITELN('printed=', JxPrintToBuf(payload, out));
  WRITELN('len=', BufLen(out));
  BufSliceToStr(out, 0, 46, s);
  WRITELN('head=', s);

  { ---- Read it back ---- }
  parsed := JxParseBuf(out);
  WRITELN('parsed_obj=', JxIsObject(parsed));
  JxGetStr(parsed, 'model', s);
  WRITELN('model=', s);
  WRITELN('max_tokens=', JxGetInt(parsed, 'max_tokens'));
  WRITELN('nmsgs=', JxArrSize(JxGet(parsed, 'messages')));
  JxGetStr(JxArrItem(JxGet(parsed, 'messages'), 1), 'role', s);
  WRITELN('role1=', s);

  { Type predicates, including the NIL case an absent key produces. }
  WRITELN('is_array=', JxIsArray(JxGet(parsed, 'messages')),
          ' is_string=', JxIsString(JxGet(parsed, 'model')),
          ' is_number=', JxIsNumber(JxGet(parsed, 'max_tokens')));
  WRITELN('absent=', JxHas(parsed, 'nope'),
          ' absent_is_string=', JxIsString(JxGet(parsed, 'nope')));

  JxDelete(parsed);
  JxDelete(payload);
  BufFree(out);

  { ---- A string well past what an LSTRING can hold ---- }
  BufInit(big, 0);
  n := 300;
  FOR i := 0 TO n - 1 DO
    BufAppendChar(big, CHR(97 + (i MOD 26)));

  payload := JxNewObject;
  JxAddStrFromBuf(payload, 'content', big);
  BufInit(out, 0);
  WRITELN('big_printed=', JxPrintToBuf(payload, out));
  parsed := JxParseBuf(out);
  BufInit(back, 0);
  WRITELN('big_read=', JxGetStrToBuf(parsed, 'content', back));
  WRITELN('big_len=', BufLen(back));
  WRITELN('big_strlen=', JxStrLen(JxGet(parsed, 'content')));

  mismatches := 0;
  FOR i := 0 TO n - 1 DO
  BEGIN
    c := CHR(97 + (i MOD 26));
    IF BufAt(back, i) <> c THEN mismatches := mismatches + 1;
  END;
  WRITELN('big_mismatches=', mismatches);

  { The truncating reader is still available and still truncates -- which is
    fine for a short enumerated value and wrong for anything else. }
  JxGetStr(parsed, 'content', s);
  WRITELN('str255_len=', ORD(s[0]));

  JxDelete(parsed);
  JxDelete(payload);
  BufFree(out);
  BufFree(big);
  BufFree(back);

  { ---- Content as a list of parts, the other shape a reply may take ---- }
  BufInit(out, 0);
  BufAppendStr(out, '{"choices":[{"message":{"content":');
  BufAppendStr(out, '[{"type":"text","text":"alpha"},');
  BufAppendStr(out, '{"type":"text","text":"beta"}]}}]}');
  parsed := JxParseBuf(out);
  choices := JxGet(parsed, 'choices');
  choice := JxArrItem(choices, 0);
  content := JxGet(JxGet(choice, 'message'), 'content');
  WRITELN('parts_is_array=', JxIsArray(content), ' nparts=', JxArrSize(content));
  BufInit(back, 0);
  FOR i := 0 TO JxArrSize(content) - 1 DO
  BEGIN
    part := JxArrItem(content, i);
    IF NOT JxGetStrToBuf(part, 'text', back) THEN WRITELN('part read failed');
  END;
  BufSliceToStr(back, 0, BufLen(back), s);
  WRITELN('parts=', s);
  JxDelete(parsed);
  BufFree(out);
  BufFree(back);

  { ---- Malformed input is a NIL tree, not an abort ---- }
  BufInit(out, 0);
  BufAppendStr(out, '{"unterminated": ');
  parsed := JxParseBuf(out);
  WRITELN('malformed_nil=', parsed = NIL);
  WRITELN('nil_obj=', JxIsObject(parsed),
          ' nil_get=', JxGet(parsed, 'anything') = NIL);
  JxDelete(parsed);
  BufFree(out);
END.
