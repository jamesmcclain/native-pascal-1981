import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @malloc')
store = f.index('store ptr ', new)
publish = f.index('store i1 true, ptr %initck.p,', store)
ready = f.index('load i1, ptr %initck.p', publish)
fail = f.index('call void @pas_initck_error', ready)
load = f.index('load ptr, ptr %p', ready)
assert fail < load, 'pointer guard must precede the pointer load'
print('PASS: pointer guard order and NEW publication')
