import json
import sys

source, dest, mode = sys.argv[1:]
ast = json.load(open(source))
count = 0


def strip(node):
    global count
    if isinstance(node, dict):
        # Return read sites (ReturnStmt, a body's closing END) are always
        # stripped so the alternation keeps addressing expression consumers.
        if node.get('__node_type__') in ('Block', 'ReturnStmt'):
            node.pop('read_flags', None)
        elif 'read_flags' in node:
            count += 1
            if mode == 'legacy' or count % 2:
                del node['read_flags']
        for value in node.values():
            strip(value)
    elif isinstance(node, list):
        for value in node:
            strip(value)


strip(ast)
assert count > 1
with open(dest, 'w') as out:
    json.dump(ast, out)
