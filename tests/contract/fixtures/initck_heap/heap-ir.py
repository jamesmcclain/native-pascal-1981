import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
alloc = f.index('call ptr @malloc(i64 4)')
reg = f.index('call void @pas_initck_heap_new(ptr ', alloc)
assert f[reg:].split('\n')[0].endswith(', i64 2)')
store = f.index('store ptr ', reg)
publish = f.index('store i1 true, ptr %initck.p,', store)
read = f.rindex('call ptr @pas_initck_heap_at(ptr ')
assert f.rindex('load ptr, ptr %p', 0, read) > publish
guard = f.index('call void @pas_initck_fail(', read)
load = f.index('load i16, ptr ', read)
assert guard < load, 'heap guard must precede the native load'
print(
    'PASS: heap registration before publication; lookup and guard before load')
