"""Assert the checked CONCAT failure edge precedes all copy/publication IR."""
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
assert re.search(r"concat\.length\w* = add i64", ir), "length not widened"
assert re.search(r"concat\.in\w* = icmp ule i64",
                 ir), "capacity not checked wide"
bad = re.search(r"^concat\.bad\w*:.*?\n(.*?)(?=^\S|\Z)", ir, re.M | re.S)
assert bad, "no failure block"
body = bad.group(1)
assert "call void @pas_concat_error" in body and "unreachable" in body
assert not re.search(r"\b(load|store|getelementptr)\b",
                     body), "failure accesses destination"
assert re.search(
    r"br i1 %concat\.in\w*, label %concat\.ok\w*, label %concat\.bad\w*", ir)
assert ir.index("concat.ok:") < ir.index(
    "strcpy_body:"), "copy emitted before success edge"
