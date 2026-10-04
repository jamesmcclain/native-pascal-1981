PROGRAM mixed(output, view, scale, tag);
{ Three bindable heading parameters of different types, all supplied on the
  command line. OUTPUT occupies no argv position, so 'view' binds to argv[1]
  even though it is second in the heading (manual 13-5..13-7). }
VAR
  view: INTEGER;
  scale: REAL;
  tag: LSTRING(32);
BEGIN
  WRITELN('view=', view);
  WRITELN('scale=', scale);
  WRITELN('tag=', tag);
END.
