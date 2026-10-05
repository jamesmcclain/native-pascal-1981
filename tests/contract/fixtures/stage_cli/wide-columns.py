import json
import sys

narrow, wide = (json.load(open(p)) for p in sys.argv[1:])
columns = []


def strip(node, keep):
    if isinstance(node, dict):
        for key in ('read_location', 'op_location', 'location'):
            loc = node.get(key)
            if isinstance(loc, dict) and 'column' in loc:
                keep.append(loc.pop('column'))
        for value in node.values():
            strip(value, keep)
    elif isinstance(node, list):
        for value in node:
            strip(value, keep)


strip(narrow, [])
strip(wide, columns)
sys.exit(0 if narrow == wide and columns and set(columns) == {40000} else 1)
