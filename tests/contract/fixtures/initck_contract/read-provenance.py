import json
import sys


def provenance(node):
    result = []

    def walk(value):
        if isinstance(value, dict):
            # Include absent snapshots on every node, not just known read kinds.
            result.append(
                (value.get('__node_type__'), value.get('name'), 'read_flags'
                 in value, value.get('read_flags')))
            for key, child in value.items():
                if key not in ('read_flags', 'resolved_type'):
                    walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(node)
    return result


before, after = (provenance(json.load(open(p))) for p in sys.argv[1:3])
assert before == after, 'typechecker changed read-site provenance'
present = [entry for entry in after if entry[2]]
if sys.argv[3] == 'legacy':
    assert not present
else:
    assert present and any(not entry[2] for entry in after)
    assert {entry[3]['INITCK'] for entry in present} == {False, True}
