import re
import sys

ir = open(sys.argv[1]).read()

# 1. probe: INTEGER read (direct destination pointer passed to runtime)
call_int = re.search(r'(%\d+) = call i32 @pas_fread_int16\(', ir)
assert call_int, "missing pas_fread_int16 call"
rest_int = ir[call_int.end():]
ok_int = re.search(
    r'(%\d+) = icmp eq i32 ' + re.escape(call_int.group(1)) + r', 0', rest_int)
assert ok_int, "missing icmp eq for int16 status"
sel_int = re.search(
    r'%initck\.read\d* = select i1 ' + re.escape(ok_int.group(1)) +
    r', i1 true, i1 (%\d+)', rest_int)
assert sel_int, "missing select for int16 shadow"
assert re.search(r'store i1 %initck\.read\d*, ptr %initck\.n',
                 rest_int), "missing shadow store for n"

# 2. probe_bool: BOOLEAN read (scratch tmp32 loaded and stored ONLY in read_ok)
fn_bool = re.search(
    r'define void @probe_bool\([^)]*\)[^{]*\{(?P<body>.*?)\n\}', ir, re.DOTALL)
assert fn_bool, "missing @probe_bool"
body_bool = fn_bool.group('body')
call_bool = re.search(r'(%\d+) = call i32 @pas_fread_enum_name\(', body_bool)
assert call_bool, "missing pas_fread_enum_name in probe_bool"
status_bool = call_bool.group(1)
assert re.search(
    r'icmp eq i32 ' + re.escape(status_bool) +
    r', 0\n\s*br i1 %\d+, label %read_ok\d*, label %read_cont\d*',
    body_bool), "missing gated branch in probe_bool"
ok_blk_bool = re.search(r'read_ok\d*:\s*(.*?)\s*br label %read_cont\d*',
                        body_bool, re.DOTALL)
assert ok_blk_bool, "missing read_ok block in probe_bool"
assert 'store i1 ' in ok_blk_bool.group(
    1), "destination store must be inside read_ok in probe_bool"
assert 'store i1 %' not in body_bool.split('read_ok')[
    0], "destination must not be stored before read_ok in probe_bool"

# The store gate and the INITCK select share one status compare.
assert len(
    re.findall(r'icmp eq i32 ' + re.escape(status_bool) + r', 0\b',
               body_bool)) == 1, "probe_bool must test its status once"
assert re.search(r'select i1 %\d+, i1 true', body_bool), \
    "missing INITCK select in probe_bool"

# 3. probe_enum: ENUM read (the i32 destination itself is passed to the
#    runtime, which leaves it alone on a trapped failure: no scratch, no store)
fn_enum = re.search(
    r'define void @probe_enum\([^)]*\)[^{]*\{(?P<body>.*?)\n\}', ir, re.DOTALL)
assert fn_enum, "missing @probe_enum"
body_enum = fn_enum.group('body')
dest_enum = re.search(r'(%[\w.]+) = alloca i32', body_enum)
assert dest_enum, "missing enum destination alloca in probe_enum"
assert len(re.findall(r'= alloca i32\b', body_enum)) == 1, \
    "enum READ must not allocate a scratch i32 in probe_enum"
assert re.search(r'= call i32 @pas_fread_enum_ord\(ptr %[\w.]+, ptr ' +
                 re.escape(dest_enum.group(1)) + r', i32 0, i32 2\)', body_enum), \
    "pas_fread_enum_ord must read straight into the destination in probe_enum"
assert not re.search(
    r'store i32 [^\n]*, ptr ' + re.escape(dest_enum.group(1)) + r'\b',
    body_enum), "enum destination must not be stored by codegen"

# 4. probe_ptr: POINTER read (scratch tmp64 loaded and stored ONLY in read_ok)
fn_ptr = re.search(r'define void @probe_ptr\([^)]*\)[^{]*\{(?P<body>.*?)\n\}',
                   ir, re.DOTALL)
assert fn_ptr, "missing @probe_ptr"
body_ptr = fn_ptr.group('body')
call_ptr = re.search(r'(%\d+) = call i32 @pas_fread_ptr\(', body_ptr)
assert call_ptr, "missing pas_fread_ptr in probe_ptr"
status_ptr = call_ptr.group(1)
assert re.search(
    r'icmp eq i32 ' + re.escape(status_ptr) +
    r', 0\n\s*br i1 %\d+, label %read_ok\d*, label %read_cont\d*',
    body_ptr), "missing gated branch in probe_ptr"
ok_blk_ptr = re.search(r'read_ok\d*:\s*(.*?)\s*br label %read_cont\d*',
                       body_ptr, re.DOTALL)
assert ok_blk_ptr, "missing read_ok block in probe_ptr"
assert 'store ptr ' in ok_blk_ptr.group(
    1), "destination store must be inside read_ok in probe_ptr"


def only_gated_store(body, ok_blk, ty, var, name):
    """The destination alloca is stored exactly once, and only in read_ok."""
    assert re.search(r'%' + var + r' = alloca ' + ty + r',', body), \
        "missing destination alloca in " + name
    store = r'store ' + ty + r' [^\n]*, ptr %' + var + r','
    assert len(re.findall(store, body)) == 1, \
        "destination must be stored only once in " + name
    assert re.search(store, ok_blk), \
        "destination must be stored only inside read_ok in " + name


only_gated_store(body_bool, ok_blk_bool.group(1), 'i1', 'b', 'probe_bool')
only_gated_store(body_ptr, ok_blk_ptr.group(1), 'ptr', 'p', 'probe_ptr')
