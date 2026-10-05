import re
import sys

ir = open(sys.argv[1]).read()
# x, y and one accumulator (not the predeclared files' buffer states)
assert len(re.findall(r'%(?!file_initck)[\w.]+ = alloca i1,', ir)) == 3, ir
assert 'store i1 true, ptr %initck.x' in ir
assert 'pas_initck_error' not in ir
src = ir.index('load i1, ptr %initck.x')
data = ir.index('store i16 %', src)
publish = re.search(r'store i1 %initck\.value\d*, ptr %initck\.y', ir)
assert publish and src < data < publish.start()
