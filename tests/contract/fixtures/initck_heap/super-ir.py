import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @pas_super_new(')
leaves = f.index('%initck.leaves', new)
assert re.search(r'%initck\.leaves\d* = mul i64 %\S+, 2\n',
                 f[new:]), 'two leaves per element'
reg = f.index('call void @pas_initck_heap_new(ptr ', leaves)
store = f.index('store { ptr, i64 } ', reg)
publish = f.index('store i1 true, ptr %initck.p,', store)
read = f.rindex('call ptr @pas_initck_heap_part_at(ptr ')
assert re.search(
    r'call ptr @pas_initck_heap_part_at\(ptr %\S+, i64 %\S+, i64 %\S+, i64 2, ptr %initck\.untracked\d*\)',
    f[read:])
bounds = f.rindex('call void @pas_array_index_error', 0, read)
guard = f.index('call void @pas_initck_fail(', read)
load = f.index('load i16, ptr ', read)
assert publish < bounds < read < guard < load
print(
    'PASS: SUPER element registration before publication; per-element lookup after bounds, before load'
)
