# Native Pascal grammar

```ebnf
compilation_unit = { interface_unit } ( program_unit | module_unit | interface_unit | implementation_unit ) ;
program_unit = "PROGRAM" identifier [ "(" identifier_list ")" ] ";" { uses_clause } block "." ;
module_unit = [ "DEVICE" ] "MODULE" identifier ";" { uses_clause } { declaration } [ "END" ] "." ;
interface_unit = [ "DEVICE" ] "INTERFACE" ";" "UNIT" identifier [ "(" identifier_list ")" ] ";"
                 { uses_clause } { interface_declaration } ( "END" ";" | compound_statement ";" ) ;
implementation_unit = [ "DEVICE" ] "IMPLEMENTATION" "OF" identifier ";" { uses_clause }
                      { declaration } [ compound_statement ] "." ;
uses_clause = "USES" uses_import { "," uses_import } ";" ;
uses_import = identifier [ "(" identifier_list ")" ] ;
(* DEVICE above is a contextual keyword, recognized by comparing the
   current identifier's text, not a reserved lexer token like MODULE or
   INTERFACE; it may still be used as an ordinary identifier elsewhere. *)

block = { declaration } [ compound_statement ] ;
declaration = const_section | type_section | var_section | label_section | procedure_declaration | function_declaration ;
interface_declaration = const_section | type_section | var_section | label_section
                      | procedure_header ";" [ interface_directive ";" ]
                      | function_header ";" [ interface_directive ";" ] ;
(* An interface routine header is body-less by construction, so a directive is
   optional -- the Aug 1981 manual notes that "in a unit's interface, EXTERN or
   FORWARD is given automatically to all constituents", so writing it is
   redundant there rather than required. Accepted anyway, and taken to mean the
   body lives in a C library or another object, which exempts the routine from
   the implementation contract. FORWARD is excluded: it promises a definition
   later in the same declaration part, and an INTERFACE has none.

   The manual's own mechanism for the same need is the other way round: the
   IMPLEMENTATION declares any routine it does not define with the EXTERN
   directive, at the start, so one INTERFACE can be split across several
   IMPLEMENTATIONs or shared with assembly. That form uses the ordinary
   procedure_declaration production below and is also supported. *)
interface_directive = "EXTERN" | "EXTERNAL" ;
const_section = "CONST" { identifier "=" constant ";" } ;
type_section = "TYPE" { identifier "=" type ";" } ;
var_section = "VAR" { [ attributes ] identifier_list ":" type ";" } ;
label_section = "LABEL" label { "," label } ";" ;

procedure_declaration = procedure_header ";" ( routine_directive ";" | block ";" ) ;
function_declaration = function_header ";" ( routine_directive ";" | block ";" ) ;
procedure_header = "PROCEDURE" identifier [ "(" parameter_list ")" ] [ attributes ] ;
function_header = "FUNCTION" identifier [ "(" parameter_list ")" ] ":" type [ attributes ] ;
routine_directive = "EXTERN" | "EXTERNAL" | "FORWARD" ;
(* VALUE, ORIGIN, OVERLAY, FORTRAN are reserved words (cannot be used as
   identifiers) but have no grammar role in this toolchain's parser: they
   are period-correct IBM Pascal keywords the lexer still reserves without
   the parser implementing them. *)
parameter_list = parameter_group { ";" parameter_group } [ ";" ] ;
parameter_group = [ "VAR" | "VARS" | "CONST" | "CONSTS" ] identifier_list ":" type ;
attributes = "[" [ attribute { "," attribute } ] "]" ;
attribute = "READONLY" | "PUBLIC" | "STATIC" | "EXTERN" | "EXTERNAL" | "PURE"
          | "SPACE" "(" expression ")" | "C" | "CDECL" | "VARARGS"
          | ( "MAXNTID" | "REQNTID" | "MINCTASM" ) "(" expression { "," expression } ")" ;

compound_statement = "BEGIN" { statement [ ";" ] } "END" ;
statement = assignment | procedure_call | compound_statement | if_statement | for_statement
          | repeat_statement | while_statement | case_statement | with_statement | goto_statement
          | label_statement | "RETURN" | ( "BREAK" | "CYCLE" ) [ label ] | empty ;
empty = ;
assignment = designator ( ":=" | "=" ) expression ;
procedure_call = ( "WRITE" | "WRITELN" ) [ "(" write_argument { "," write_argument } ")" ]
               | identifier [ "(" [ expression_list ] ")" ] ;
if_statement = "IF" boolean_expression "THEN" statement [ "ELSE" statement ] ;
for_statement = "FOR" [ "STATIC" ] identifier ":=" expression ( "TO" | "DOWNTO" ) expression "DO" statement ;
repeat_statement = "REPEAT" { statement [ ";" ] } "UNTIL" boolean_expression ;
while_statement = "WHILE" boolean_expression "DO" statement ;
case_statement = "CASE" expression "OF" { case_element ";" } [ case_element ]
                 [ "OTHERWISE" statement ] "END" ;
case_element = case_constant_list ":" statement ;
case_constant_list = case_constant { "," case_constant } ;
case_constant = constant [ ".." constant ] ;
with_statement = "WITH" with_designator { "," with_designator } "DO" statement ;
goto_statement = "GOTO" label ;
label_statement = label ":" statement ;
write_argument = expression [ ":" [ expression ] [ ":" expression ] ] ;
expression_list = expression { "," expression } ;

boolean_expression = expression { ( "AND" "THEN" | "OR" "ELSE" ) expression } ;
expression = simple_expression [ relation simple_expression ] ;
simple_expression = [ "+" | "-" ] term { ( "+" | "-" | "OR" | "XOR" ) term } ;
term = factor { ( "*" | "/" | "DIV" | "MOD" | "AND" ) factor } ;
factor = constant | designator | identifier "(" [ expression_list ] ")" | "RETYPE" "(" identifier "," expression ")"
       | "NOT" factor | "(" expression ")" | set_constructor | "ADR" identifier
       | "SIZEOF" "(" ( identifier | type ) ")" | ( "LOWER" | "UPPER" ) "(" identifier [ "^" ] ")" ;
designator = identifier { "[" expression { "," expression } "]" | "." identifier | "^" } ;
with_designator = identifier { "[" expression "]" | "." identifier | "^" } ;
set_constructor = "[" [ set_element { "," set_element } ] "]" ;
set_element = expression [ ".." expression ] ;
relation = "=" | "<>" | "<" | "<=" | ">" | ">=" | "IN" ;

type = [ "PACKED" ] ( array_type | record_type ) | set_type | file_type | enum_type | lstring_type
     | pointer_type | named_type | builtin_type ;
array_type = "ARRAY" "[" fixed_index_range "]" "OF" type
           | "SUPER" "ARRAY" "[" super_index_range "]" "OF" type ;
fixed_index_range = constant ".." constant ;
super_index_range = constant ".." "*" ;
record_type = "RECORD" { field_declaration ";" } [ field_declaration ] [ variant_part ] "END" ;
field_declaration = identifier_list ":" type ;
variant_part = "CASE" [ identifier ":" ] type "OF" { variant_arm ";" } [ variant_arm ] ;
variant_arm = case_constant_list ":" "(" { field_declaration [ ";" ] } ")" ;
set_type = "SET" "OF" ( type | fixed_index_range ) ;
file_type = "FILE" "OF" type ;
enum_type = "(" identifier_list ")" ;
lstring_type = "LSTRING" "(" constant ")" ;
pointer_type = "^" type | "ADR" "OF" type | "ADS" [ "(" expression ")" ] "OF" type ;
named_type = identifier [ "(" constant ")" ] ;
builtin_type = "INTEGER" | "REAL" | "BOOLEAN" | "CHAR" | "WORD" | "ADRMEM" ;

constant = [ "+" | "-" ] ( integer_literal | real_literal ) | char_literal | string_literal
         | boolean_literal | "NIL" | identifier | ( "WRD" | "BYWORD" ) "(" constant { "," constant } ")" ;
identifier_list = identifier { "," identifier } ;
label = integer_literal | identifier ;

identifier = letter_or_underscore { letter_or_underscore | digit } ;
letter_or_underscore = letter | "_" ;
letter = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L"
       | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z" ;
digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
radix_digit = digit | "A" | "B" | "C" | "D" | "E" | "F" ;
integer_literal = digit { digit } [ "#" radix_digit { radix_digit } ] ;
real_literal = digit { digit } "." digit { digit } [ ( "E" | "e" ) [ "+" | "-" ] digit { digit } ] ;
char_literal = "'" character "'" ;
string_literal = "'" { character | "''" } "'" ;
character = ? any character except "'" ? ;
boolean_literal = "TRUE" | "FALSE" ;

(* Metacommand directives: a `$`-prefixed sublanguage recognized inside
   comments, i.e. within "(* ... *)" or "{ ... }", where "..." matches
   metacommand_list below. Several forms affect parsing itself: $IF/$ELSE/
   $END drive conditional compilation (skipping source text), and $UNROLL
   must immediately precede a FOR, WHILE, or REPEAT statement. *)
metacommand_list = "$" metacommand { "," metacommand } ;
metacommand = conditional_directive | "PUSH" | "POP" | message_directive
            | include_directive | inconst_directive | unroll_directive
            | flag_directive ;
conditional_directive = "IF" meta_condition [ "$" "THEN" ]
                       | "ELSE" | "END" ;
meta_condition = integer_literal | "-" integer_literal | identifier ;
message_directive = "MESSAGE" [ ":" ] string_literal ;
include_directive = "INCLUDE" ":" string_literal ;
inconst_directive = "INCONST" [ ":" ] identifier ;
unroll_directive = "UNROLL" [ ":" ] ( integer_literal | identifier ) ;
flag_directive = flag_name ( "+" | "-" | ":" [ "+" | "-" ] integer_literal ) ;
flag_name = "BRAVE" | "DEBUG" | "ENTRY" | "GOTO" | "INDEXCK" | "INITCK"
          | "LINE" | "LIST" | "MATHCK" | "NILCK" | "OCODE" | "RANGECK"
          | "RUNTIME" | "STACKCK" | "SYMTAB" | "WARN" ;
```
