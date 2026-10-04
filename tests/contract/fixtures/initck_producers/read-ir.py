import re
import sys

ir = open(sys.argv[1]).read()
call = re.search(r'(%\d+) = call i32 @pas_fread_int16\(', ir)
assert call, ir
rest = ir[call.end():]
ok = re.search(r'(%\d+) = icmp eq i32 ' + re.escape(call.group(1)) + r', 0',
               rest)
assert ok
sel = re.search(
    r'%initck\.read\d* = select i1 ' + re.escape(ok.group(1)) +
    r', i1 true, i1 (%\d+)', rest)
assert sel
assert re.search(r'store i1 %initck\.read\d*, ptr %initck\.n', rest)
