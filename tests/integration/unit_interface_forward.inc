INTERFACE;
UNIT mutualrec (IsEven, IsOdd);
{ Two mutually recursive routines, both exported. The implementation cannot
  define IsOdd before IsEven uses it, and an interface entry does not itself
  forward-declare -- so the implementation must re-state IsOdd as a FORWARD
  even though this interface already declares it. }
FUNCTION IsEven(n: INTEGER): BOOLEAN;
FUNCTION IsOdd(n: INTEGER): BOOLEAN;
END;
