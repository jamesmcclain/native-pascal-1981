{ A named index resolves through an alias of an enum subrange. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
PROGRAM t(output); TYPE Color = (red, green, blue); Small = green..blue; Alias = Small; VAR a: ARRAY [Alias] OF INTEGER; BEGIN END.
