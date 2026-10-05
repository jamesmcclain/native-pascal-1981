import re
import sys

ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
assert probe.count('store ptr %initck.x, ptr @pas_initck_args') == 1
assert len(re.findall(r'store ptr %[^,]+, ptr @pas_initck_args',
                      probe)) == 1  # none for g
assert '%initck.actual' not in probe
callee = ir[ir.index('define void @bump('):]
callee = callee[:callee.index('\n}')]
assert re.search(
    r'%initck\.n\.ref = select i1 %\d+, ptr %initck\.n, ptr %initck\.arg',
    callee)
guard = callee.index('load i1, ptr %initck.n.ref')
data = callee.index('load i16, ptr %0')
assert guard < data
assert re.search(r'store i1 [^,]+, ptr %initck\.n\.ref,', callee[data:])
