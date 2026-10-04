import json
import sys

x = json.load(open(sys.argv[1]))


def strip(v):
    if isinstance(v, dict):
        v.pop('read_flags', None)
        for a in v.values():
            strip(a)
    elif isinstance(v, list):
        for a in v:
            strip(a)


strip(x)
json.dump(x, sys.stdout)
