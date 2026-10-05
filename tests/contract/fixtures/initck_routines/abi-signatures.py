import re
import sys

ir = open(sys.argv[1]).read()
names = 'echo|swap|view|noint|nobool|nochar|noreal|noptr|nopair|nobig|early|fact|outer|inner'
for line in ir.splitlines():
    for kind in ('define', 'call'):
        m = re.search(kind + r' (.*?) @(' + names + r')\((.*)\)', line)
        if m:
            args = re.sub(r'%\d+', '%', m.group(3))
            print(f'{kind} {m.group(1)} {m.group(2)}({args})')
