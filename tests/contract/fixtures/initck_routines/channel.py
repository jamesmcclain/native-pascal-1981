import re
import sys

ir = open(sys.argv[1]).read()
assert '@pas_initck_args = external thread_local global [16 x ptr]' in ir
assert '@pas_initck_ret = external thread_local global i1' in ir
callee = ir[ir.index('define i16 @f('):]
callee = callee[:callee.index('\n}')]
recv = callee.index('%initck.arg = load ptr, ptr @pas_initck_args')
clear = callee.index('store ptr null, ptr @pas_initck_args', recv)
first_call = callee.index('call ')
assert recv < clear < first_call
assert 'select i1' in callee[clear:first_call]
# Only the tracked INTEGER formal is received; REAL r has no slot.
assert callee.count('@pas_initck_args') == 2 and not re.search(
    r'%initck\.r[ ,]', callee)
assert re.search(r'store i1 %initck\.result\d*, ptr @pas_initck_ret', callee)
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
calls = [m.start() for m in re.finditer(r'call i16 @f\(', probe)]
assert len(calls) == 2
prev = 0
for at in calls:
    window = probe[prev:at]  # since the previous call (or entry)
    pub = re.findall(r'store ptr (%initck\.actual\d*), ptr @pas_initck_args',
                     window)
    assert len(pub) == 1, window  # one tracked actual, published once
    # The actual's state is stored, then published, then the flag reset.
    publish = window.index(f'store ptr {pub[0]}, ptr @pas_initck_args')
    assert re.search(r'store i1 [^,]+, ptr ' + re.escape(pub[0]) + ',',
                     window[:publish])
    assert window.rindex('store i1 true, ptr @pas_initck_ret') > publish
    after = probe[at:]
    clear = after.index('store ptr null, ptr @pas_initck_args')
    assert clear < after.index('load i1, ptr @pas_initck_ret')
    prev = at + 1
# The inner call's result state feeds the outer actual's accumulator.
inner, outer = calls
seg = probe[inner:outer]
assert re.search(r'%initck\.returned\d* = load i1, ptr @pas_initck_ret', seg)
