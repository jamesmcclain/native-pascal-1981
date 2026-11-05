"""Check DELETE's span guard and failure edge before destination writes."""
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
assert re.search(r"delete\.in\w* = and i1", ir), "span not checked"
bad = re.search(r"^delete\.bad\w*:.*?\n(.*?)(?=^\S|\Z)", ir, re.M | re.S)
assert bad, "no failure block"
body = bad.group(1)
assert "call void @pas_delete_error" in body and "unreachable" in body
assert not re.search(r"\b(load|store|getelementptr)\b",
                     body), "failure accesses destination"
assert re.search(
    r"br i1 %delete\.in\w*, label %delete\.ok\w*, label %delete\.bad\w*",
    ir), "guard branch bypassed"
ok = ir.index("delete.ok:")
assert ok < ir.index("call ptr @memmove"), "tail move precedes success edge"
trunc = re.search(r"^.* = trunc i32 .* to i8$", ir, re.M)
assert trunc and trunc.start() > ok, "length published before guard"
