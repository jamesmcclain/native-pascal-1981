import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
alloc = f.index('call ptr @malloc(i64 4)')
check = re.search(
    r'%\S+ = icmp eq ptr %\S+, null\n\s+br i1 %\S+, label %new\.fail, label %new\.ok',
    f[alloc:])
assert check
ok = f.index('new.ok:', alloc)
assert f.index('call void @pas_initck_heap_new(', alloc) > ok
fail = f[f.index('new.fail:'):]
assert re.match(
    r'new\.fail:.*?\n\s+call void @pas_new_error\(\)\n\s+unreachable', fail,
    re.S)
print('PASS: NEW failure branch before registration and publication')
