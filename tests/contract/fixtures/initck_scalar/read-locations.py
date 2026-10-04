import json
import sys

for path in sys.argv[1:3]:
    tree = json.load(open(path))
    found = []

    def walk(v):
        if isinstance(v, dict):
            if v.get('name') == 'unset' and 'read_flags' in v:
                found.append(v)
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)

    walk(tree)
    assert len(found) == 1
    assert found[0]['read_location'] == {'line': 6, 'column': 12}
    assert found[0]['read_flags']['INITCK'] is True
# Exercise the zero-selector Designator lowering as well as Identifier.
found[0]['__node_type__'] = 'Designator'
found[0]['selectors'] = []
json.dump(tree, open(sys.argv[4], 'w'))


# Keep enabled flags, remove only the coordinates.
def strip(v):
    if isinstance(v, dict):
        v.pop('read_location', None)
        for x in v.values():
            strip(x)
    elif isinstance(v, list):
        for x in v:
            strip(x)


strip(tree)
json.dump(tree, open(sys.argv[3], 'w'))
