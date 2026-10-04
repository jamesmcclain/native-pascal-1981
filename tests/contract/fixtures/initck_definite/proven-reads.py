import re
import sys

on, fail = (open(p).read() for p in sys.argv[1:])


def body(ir, name):
    return re.search(r'define [^\n]*@' + name + r'\(.*?^}', ir,
                     re.M | re.S).group()


# Before LLVM optimization: proven assignment RHS/IF reads lack guards.
# Output calls remain barriers, so their unproven reads keep guards.
for name, count in [('Straight', 1), ('Joined', 1), ('Scalars', 1)]:
    b = body(on, name)
    assert b.count('call void @pas_initck_error') == count, (name, b)
    assert 'alloca i1' in b and 'store i1' in b
# All unknown cases retain a metadata guard before the native load.
for name in [
        'OneBranch', 'GotoSkip', 'ZeroLoop', 'UncheckedCopy', 'CallEffect'
]:
    b = body(fail, name)
    state = b.index('load i1, ptr %initck.x,')
    load = b.index('load i16, ptr %x,')
    assert state < b.index('call void @pas_initck_error') < load
    assert 'unreachable' in b[state:load]
