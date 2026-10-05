import json
import sys

tree = json.load(open(sys.argv[1]))
stripped = 0


def walk(v):
    global stripped
    if isinstance(v, dict):
        if v.get('__node_type__') in ('ReturnStmt', 'Block') and v.get(
                'read_flags', {}).get('INITCK'):
            del v['read_flags']
            stripped += 1
        for x in v.values():
            walk(x)
    elif isinstance(v, list):
        for x in v:
            walk(x)


walk(tree)
assert stripped == 2
json.dump(tree, sys.stdout)
