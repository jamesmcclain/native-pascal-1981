"""Check COPYLST's full-width guard and failure edge before destination writes."""
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
assert re.search(r"copylst\.in\w* = icmp ule i64",
                 ir), "length not checked wide"
bad = re.search(r"^copylst\.bad\w*:.*?\n(.*?)(?=^\S|\Z)", ir, re.M | re.S)
assert bad, "no failure block"
body = bad.group(1)
assert "call void @pas_copylst_error" in body and "unreachable" in body
assert not re.search(r"\b(load|store|getelementptr)\b",
                     body), "failure accesses destination"
assert re.search(
    r"br i1 %copylst\.in\w*, label %copylst\.ok\w*, label %copylst\.bad\w*",
    ir), "guard branch bypassed"
assert ir.index("copylst.ok:") < ir.index(
    "strcpy_body:"), "copy precedes success edge"
# Function result temporaries may be published earlier; the destination
# length store, uniquely fed by its i32-to-i8 truncation, must be later.
trunc = re.search(r"^.* = trunc i32 .* to i8$", ir, re.M)
assert trunc and trunc.start() > ir.index(
    "copylst.ok:"), "length truncated before guard"
