(* 4.7: WRD and BYWORD basic usage — must parse successfully *)
PROGRAM WrdBasic;
VAR
    i : INTEGER;
    w : WORD;
    c : CHAR;
BEGIN
    i := -1;
    w := WRD(i);          (* INTEGER -> WORD: same 16-bit pattern *)
    c := 'Z';
    w := WRD(c);          (* CHAR    -> WORD: ASCII ordinal       *)
    w := WRD(TRUE);       (* BOOLEAN -> WORD: 1 or 0              *)
    w := BYWORD(16#AB, 16#CD);  (* pack two bytes into one WORD   *)
    w := BYWORD(CHR(1), CHR(2))
END.
