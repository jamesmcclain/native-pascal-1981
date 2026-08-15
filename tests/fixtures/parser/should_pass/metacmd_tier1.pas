(* Tier-1 listing/output metacommands are silently absorbed.
   Every name here should parse without error. *)
{$LIST-}
{$LIST+}
{$OCODE-}
{$SYMTAB-}
{$TITLE:'My Program'}
{$SUBTITLE:'Page 1'}
{$PAGE:1}
{$PAGE}
{$PAGEIF:10}
{$PAGESIZE:60}
{$LINESIZE:132}
{$ERRORS:10}
{$SKIP:3}
PROGRAM Tier1Meta;
BEGIN
END.
