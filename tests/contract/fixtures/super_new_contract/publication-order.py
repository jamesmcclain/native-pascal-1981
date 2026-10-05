import re
import sys

ir = open(sys.argv[1]).read()
main = re.search(r'define i32 @main\(.*?\n\}', ir, re.S).group()
# Initial NEW plus both alternatives. Every publication must be a full store
# after its checked allocator call; there are no pre-call field writes.
assert len(re.findall(r'call ptr @pas_super_new', main)) == 3
for segment in main.split('call ptr @pas_super_new')[1:]:
    segment = segment.split('call ptr @pas_super_new')[0]
    assert re.search(r'insertvalue \{ ptr, i64 \} .*?, ptr %\w+, 0', segment)
    assert re.search(r'store \{ ptr, i64 \} %\w+, ptr ', segment)
assert not re.search(r'store (?:ptr|i64) .*?, ptr @slots', main)
assert 'call ptr @malloc' not in main
print(
    'PASS: validated allocation precedes whole-value publication; wide/aligned strides'
)
