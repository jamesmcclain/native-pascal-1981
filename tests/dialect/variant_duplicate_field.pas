PROGRAM VariantDuplicateField;
TYPE
  Bad = RECORD
    CASE INTEGER OF
      1: (value: INTEGER);
      2: (value: CHAR)
  END;
BEGIN
END.
