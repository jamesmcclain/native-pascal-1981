import re
import sys

# huge-ir.py IR: no stack shadow proportional to an untracked referent.
ir = open(sys.argv[1]).read()
for m in re.finditer(r'= alloca \[(\d+) x i8\]', ir):
    assert int(m.group(1)) <= 65536, 'oversized stack slot: ' + m.group()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
# Only Small's referent is looked up (its store and its read), each site
# with its own 8-leaf fallback.
looks = re.findall(r'call ptr @pas_initck_heap_at\(ptr [^,]+, i64 (\d+), ', f)
assert looks == ['8', '8'], looks
assert '@pas_initck_heap_part_at(' not in f, 'no SUPER element lookup'
slots = re.findall(r'%initck\.untracked\S* = alloca \[(\d+) x i8\]', f)
assert slots == ['8', '8'], slots
main = re.search(r'define [^@]*@main\(.*?\n\}', ir, re.S).group()
# NEW registers only Small (8 leaves).
regs = re.findall(r'call void @pas_initck_heap_new\(ptr [^,]+, i64 ([^)]+)\)',
                  main)
assert regs == ['8'], regs
print('PASS: huge referents untracked; no oversized INITCK stack slot')
