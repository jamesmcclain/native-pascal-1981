import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @pas_super_new(')
store = f.index('store { ptr, i64 } ', new)
publish = f.index('store i1 true, ptr %initck.p,', store)
ready = f.index('load i1, ptr %initck.p', publish)
fail = f.index('call void @pas_initck_error', ready)
load = f.index('load { ptr, i64 }, ptr %p', ready)
nil = f.index('call void @pas_upper_nil_error', load)
assert fail < load < nil
print(
    'PASS: descriptor publication, guard before descriptor load and NIL check')
