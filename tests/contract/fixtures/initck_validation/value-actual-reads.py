import re
import sys

on, off = (open(p).read() for p in sys.argv[1:])
# A value actual is a read even when the callee ignores it. Verify the
# metadata-only branch and terminating failure precede the FIRST data load,
# and that the native load precedes the call. Disabled IR retains that same
# unsafe read but no guard: it is evidence about lowering, not program output.
probe = re.search(r'define void @probe\(.*?^}', on, re.M | re.S).group()
state = probe.index('load i1, ptr %initck.unset,')
load = probe.index('load i16, ptr %unset,')
call = probe.index('call void @ignore(')
assert state < load < call
assert 'load i16, ptr %unset,' not in probe[:state]
region = probe[state:load]
assert re.search(
    r'br i1 %initck.ready\d*, label %initck.ok\d*, label %initck.bad\d*',
    region)
assert 'call void @pas_initck_error' in region
assert 'unreachable' in region
assert re.search(r'initck.ok\d*:', region)
assert 'load i16, ptr %unset,' in off
assert not re.search(r'call void @pas_initck_(error|fail)', off)
