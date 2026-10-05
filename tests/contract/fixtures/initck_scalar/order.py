import re
import sys

ir = open(sys.argv[1]).read()
assert len(re.findall(r'call void @pas_initck_error', ir)) == 3
assert len(re.findall(r'load i1, ptr %initck\.', ir)) == 3
for name, ty, value in [('x', 'i16', '0'), ('b', 'i1', 'false'),
                        ('c', 'i8', '122')]:
    store = ir.index(f'store {ty} {value}, ptr %{name},')
    publish = ir.index(f'store i1 true, ptr %initck.{name},')
    state = ir.index(f'load i1, ptr %initck.{name},')
    data = ir.index(f'load {ty}, ptr %{name},')
    assert store < publish < state < data
    region = ir[state:data]
    assert re.search(
        r'br i1 %initck.ready\d*, label %initck.ok\d*, label %initck.bad\d*',
        region)
    assert 'call void @pas_initck_error' in region
    assert 'unreachable' in region
    assert re.search(r'initck.ok\d*:', region)
