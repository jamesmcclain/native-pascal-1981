INTERFACE;
UNIT aliasstate (SetName, GetName);
TYPE
  Name = LSTRING(32);
  NameRecord = RECORD
    text: Name;
  END;
PROCEDURE SetName(input_name: Name);
PROCEDURE GetName(VAR output_name: Name);
END;
