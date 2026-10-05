import re
import sys

path, mutation = sys.argv[1:]
ir = open(path).read()
if mutation == 'release':
    ir, n = re.subn(r'\n *call void @pas_initck_release_unacked\([^\n]*', '',
                    ir)
elif mutation == 'heap':
    ir, n = re.subn(r'\n *call void @pas_initck_heap_release\([^\n]*', '', ir)
elif mutation == 'tag':
    ir, n = re.subn(
        r'(%initck\.mine[0-9]* = )icmp eq ptr %initck\.tag[0-9]*, @cb\b',
        r'\1icmp ne ptr null, @cb', ir)
else:
    ir, n = re.subn(r'xor i1 %initck\.acked[0-9]*, true', 'xor i1 true, true',
                    ir)
assert n >= 1, mutation
open(path, 'w').write(ir)
