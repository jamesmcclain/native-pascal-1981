import re
import sys

ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
at = 0
for name, ty in (('p', 'ptr'), ('s', '{ ptr, i64 }')):
    ready = f.index('load i1, ptr %initck.' + name, at)
    fail = f.index('call void @pas_initck_error', ready)
    load = f.index('load %s, ptr %%%s' % (ty, name), ready)
    retire = f.index('call void @pas_initck_heap_dispose(ptr ', load)
    free = f.index('call void @free(ptr ', retire)
    assert fail < load < retire < free
    arg = re.match(r'call void @pas_initck_heap_dispose\(ptr (%\S+)\)',
                   f[retire:]).group(1)
    assert re.match(r'call void @free\(ptr ' + re.escape(arg) + r'\)',
                    f[free:])
    at = free
print('PASS: DISPOSE guard, retirement before free')
