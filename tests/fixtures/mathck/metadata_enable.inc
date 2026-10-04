{ Save caller's off state; leave MATHCK enabled on return. INITCK is not
  under test here (DEBUG+ would enable it for SUCC/SQR call consumers). }
{$PUSH,DEBUG+,INITCK-}
x := a + a;
