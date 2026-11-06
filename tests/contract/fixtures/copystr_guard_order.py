"""Check COPYSTR's full-width guard and failure edge before destination writes."""
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
assert re.search(r"copystr\.in\w* = icmp ule i64",
                 ir), "length not checked wide"
bad = re.search(r"^copystr\.bad\w*:.*?\n(.*?)(?=^\S|\Z)", ir, re.M | re.S)
assert bad, "no failure block"
body = bad.group(1)
assert "call void @pas_copystr_error" in body and "unreachable" in body
assert not re.search(r"\b(load|store|getelementptr)\b",
                     body), "failure accesses destination"
assert re.search(
    r"br i1 %copystr\.in\w*, label %copystr\.ok\w*, label %copystr\.bad\w*",
    ir), "guard branch bypassed"
ok = ir.index("copystr.ok:")
assert ok < ir.index("strcpy_body:"), "copy precedes success edge"
assert ok < ir.index("strfill_body:"), "blank fill precedes success edge"
