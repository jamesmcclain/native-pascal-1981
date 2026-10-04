import sys

ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
rel = probe.index('call void @pas_initck_heap_release(')
assert rel < probe.index('@pas_dev_launch(')
