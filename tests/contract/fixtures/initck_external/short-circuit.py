import json
import sys

# The grammar takes AND THEN/OR ELSE only as a condition's top operator, so a
# short-circuit inside a call's actuals exists only as a typed AST: turn every
# eager AND/OR into AND_THEN/OR_ELSE.
x = json.load(open(sys.argv[1]))


def flip(v):
    if isinstance(v, dict):
        if v.get('__node_type__') == 'BinOp' and v.get('op') in ('AND', 'OR'):
            v['op'] = {'AND': 'AND_THEN', 'OR': 'OR_ELSE'}[v['op']]
        for a in v.values():
            flip(a)
    elif isinstance(v, list):
        for a in v:
            flip(a)


flip(x)
json.dump(x, sys.stdout)
