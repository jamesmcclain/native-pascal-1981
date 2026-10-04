import re
import sys

on, off = (open(p).read() for p in sys.argv[1:])
# Replacement for the metadata-only baseline's on/off identical-IR oracle:
# supported source reads now have guards, while opt-out keeps state tracking.
assert on != off
assert not re.search(r'call void @pas_initck_(error|fail)', off)
# Coordinates refer to the persistent values fixture: scalar and pointer
# reads, whole-record copy, array element, heap leaf, formal and result.
for helper, line, column in (
    ('error', 17, 11),
    ('error', 17, 57),
    ('fail', 24, 45),
    ('fail', 26, 11),
    ('fail', 28, 28),
    ('fail', 6, 19),
    ('fail', 6, 21),
):
    assert re.search(
        r'call void @pas_initck_' + helper + r'\([^\n]*i32 ' + str(line) +
        r', i32 ' + str(column) + r'\)', on), (helper, line, column)
# INITCK- is not a switch that removes instrumentation: unchecked producers
# and copies must retain state for later enabled reads and routine boundaries.
for ir in (on, off):
    for slot, shape in (('x', 'i1'), ('p', 'i1'), ('v', 'i1'),
                        ('result', 'i1'), ('a', '[2 x i1]'), ('values',
                                                              '[2 x i1]')):
        assert '%initck.' + slot + ' = alloca ' + shape in ir
    for helper in ('copy', 'heap_new', 'heap_at', 'heap_dispose'):
        assert re.search(r'call (?:void|ptr) @pas_initck_' + helper + r'\(',
                         ir)
    assert 'store i1' in ir and 'ptr @pas_initck_ret' in ir
