import re
import sys

ir = open(sys.argv[1]).read()


def body(name):
    b = ir[ir.index(f'define {name}'):]
    return b[:b.index('\n}')]


probe = body('void @probe(')
i_tag = probe.index('store ptr @pset, ptr @pas_initck_callee')
i_ack = probe.index('ptr @pas_initck_ack', i_tag)
i_call = probe.index('call void @pset(', i_ack)
i_acked = probe.index('load i1, ptr %initck.ack', i_call)
i_clear = probe.index('store ptr null, ptr @pas_initck_callee', i_call)
i_rel = probe.index('call void @pas_initck_release_unacked(', i_acked)
assert i_clear < i_rel
cset = probe.index('call void @cset(')
assert re.search(r'store i1 true, ptr %initck\.x,[^\n]*\n *call void @cset\(',
                 probe)
assert 'call void @pas_initck_fill(ptr %initck.a' in probe[:probe.index(
    'call void @cfill(')]
assert 'store ptr @cset' not in probe  # [C] routines take no part
cb = body('void @cb(')
mine = re.search(r'%initck\.mine[0-9]* = icmp eq ptr %initck\.tag[0-9]*, @cb',
                 cb)
assert mine and mine.start() < cb.index('@pas_initck_args')
assert re.search(r'%initck\.argok[0-9]* = select i1 %initck\.mine', cb)
