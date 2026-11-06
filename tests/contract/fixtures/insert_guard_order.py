"""Check INSERT's position and capacity guards precede destination writes."""
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
assert re.search(r"insertpos\.in\w* = and i1", ir), "position not checked"
assert re.search(r"insert\.in\w* = icmp ule i64",
                 ir), "length not checked wide"
for prefix, fn in (("insertpos", "pas_insert_position_error"),
                   ("insert", "pas_insert_error")):
    bad = re.search(r"^%s\.bad\w*:.*?\n(.*?)(?=^\S|\Z)" % prefix, ir,
                    re.M | re.S)
    assert bad, "no %s failure block" % prefix
    body = bad.group(1)
    assert "call void @%s" % fn in body and "unreachable" in body
    assert not re.search(r"\b(load|store|getelementptr)\b",
                         body), "failure accesses destination"
    assert re.search(
        r"br i1 %%%s\.in\w*, label %%%s\.ok\w*, label %%%s\.bad\w*" %
        (prefix, prefix, prefix), ir), "guard branch bypassed"
ok = ir.index("insert.ok:")
assert ir.index("insertpos.ok:") < ok, "capacity checked before position"
assert ok < ir.index("call ptr @memmove"), "move precedes success edge"
trunc = re.search(r"^.* = trunc i64 .* to i8$", ir, re.M)
assert trunc and trunc.start() > ok, "length published before guard"
