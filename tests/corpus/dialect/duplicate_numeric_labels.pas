{ DIALECT: vintage extended }
{ NEW-7r: duplicate numeric labels in the same block are rejected, including
  leading-zero spellings of the same label and high 16-bit labels; an inner
  routine may still declare the same numeric label as an enclosing block. }
PROGRAM DuplicateNumericLabels(OUTPUT);
LABEL
  10, 10, 020, 20, 65534, 65534;

PROCEDURE ShadowOk;
LABEL
  10;
BEGIN
10:
END;

PROCEDURE InnerDup;
LABEL
  40, 40;
BEGIN
40:
END;

BEGIN
10:
20:
65534:
END.
