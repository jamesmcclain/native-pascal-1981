import re
import sys

ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
assert re.search(r'%file_initck[0-9]* = alloca i1,', probe)
assert re.search(r'%file_initck[0-9]* = alloca \[2 x i1\]', probe)
assert 'store i32 2, ptr' in probe
assert probe.index('@pas_file_put(') > probe.index('initck.ready')
