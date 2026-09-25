{ Unit initialization follows the USES graph, not the splice order: each
  unit is initialized after the units it uses, in the order the PROGRAM's
  USES reaches them. The expected pascal_init_ calls are in init_order.inits. }
(*$INCLUDE:'order_a.inc'*)
(*$INCLUDE:'order_c.inc'*)
(*$INCLUDE:'order_b.inc'*)
PROGRAM init_order;
USES order_c, order_a;
BEGIN
  PA; PC
END.
