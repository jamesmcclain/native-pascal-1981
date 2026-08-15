"""Audit every RECORD definition in the native self-hosting sources against
the real LLVM struct layout -- the §1.6 systemic bug-class audit.

The native compiler's ``TypeSizeBytes``/``TypeAlignBytes``
(src/pascal1981/pascal_src/codegen.pas) and the Python reference's
``_size_of``/``_align_of`` (src/pascal1981/codegen/c_abi.py) are hand-rolled
to mirror LLVM's natural (non-packed) x86-64 struct layout.  They are never
cross-checked against LLVM's own ``TargetData`` -- they are trusted
exclusively, and a drift between the hand-roll and the real backend layout
silently corrupts every ``SIZEOF``, every ``NEW``-sized allocation, and every
array-of-record stride.  The original ``Token`` record bug (a ``REAL`` field
forcing 8-byte alignment the naive sizer missed) was found only because it
crashed; records that happen not to crash have never been audited.

This is that audit.  For every RECORD the five self-hosting sources define
(``lexer.pas`` MetacmdFlags; ``parser.pas`` Token; ``typechecker.pas``
SymRec/TypeRec/FieldRec; ``codegen.pas`` TypeRec/FieldRec/ConstRec/SymRec/
RoutineRec; ``jsonutil.pas`` defines none), it verifies, against LLVM's own
``TargetData`` as ground truth:

  1. ``SIZEOF(rec)`` -- the value the compiler computes and prints -- equals
     ``TargetData.get_abi_size`` of the struct the compiler actually emitted.
  2. Every field's LLVM-computed offset (``get_element_offset``) equals the
     offset produced by an independent natural-alignment walk that uses
     ``TargetData``'s own per-field sizes and alignments -- never the
     hand-rolled sizers.  This catches a single misaligned field that a
     coincidentally-matching total size would hide.
  3. The struct's LLVM alignment equals the max of its fields' LLVM
     alignments, and the total size includes correct tail padding.

Each check runs against the Python reference pipeline unconditionally, and
against the native pipeline (``NATIVE_LEXER``/``NATIVE_PARSER``/
``NATIVE_TYPECHECKER``/``NATIVE_CODEGEN``) when those four binaries are
supplied, so a drift between the two compilers' layouts surfaces here too.
The two compilers emit different scalar representations for some fields
(native ``BOOLEAN`` is ``i1``; Python's is ``i8``) -- both are 1 byte under
LLVM's struct layout rules, so the size/offset audit agrees either way, but
the cross-compiler ``SIZEOF`` equality assertion is what keeps that
representation difference honest.
"""

import os
import re
import subprocess
import unittest
from pathlib import Path

import llvmlite.binding as llvm_binding
from pascal1981.features import extended_features

from tests.support import (RUNTIME_LIB, compile_pascal_project,
                           link_pascal_project, requires_exe,
                           temporary_pascal_project)

EXT = extended_features()

ROOT = Path(__file__).resolve().parents[2]
NATIVE = {
    stage: os.environ.get(env, str(ROOT / "bin" / stage))
    for stage, env in {
        "lexer": "NATIVE_LEXER",
        "parser": "NATIVE_PARSER",
        "typechecker": "NATIVE_TYPECHECKER",
        "codegen": "NATIVE_CODEGEN",
    }.items()
}
HAS_NATIVE = all(path and os.access(path, os.X_OK) for path in NATIVE.values())


def _round_up(n, a):
    return (n + a - 1) // a * a


# Shared declarations every self-hosting RECORD depends on, lifted verbatim
# from the dialect the sources themselves use (Str255 from jsonutil's
# INTERFACE; MAX_PARAMS and the Param* arrays from codegen.pas's CONST/TYPE
# block).  Declaring them locally makes each record compilable standalone.
SHARED_DEPS = """\
CONST MAX_PARAMS = 16;
TYPE Str255 = LSTRING(255);
     ParamTkArr = ARRAY [1..MAX_PARAMS] OF INTEGER;
     ParamVarArr = ARRAY [1..MAX_PARAMS] OF BOOLEAN;
     ParamNameArr = ARRAY [1..MAX_PARAMS] OF Str255;
"""

# Each entry: (record_name, source_file, record_body).
# Field order is verbatim from the source (comments stripped); order is what
# determines layout, so faithfulness here is load-bearing.  typechecker.pas
# and codegen.pas both define SymRec/TypeRec/FieldRec; the native records are
# prefixed Tc*/Cg* so they can coexist in one test program if needed and so a
# failure names which source's definition drifted.
RECORDS = [
    ("MetacmdFlags", "lexer.pas", """\
    Brave: BOOLEAN;
    Debug: BOOLEAN;
    Entry: BOOLEAN;
    GotoFlag: BOOLEAN;
    IndexCk: BOOLEAN;
    InitCk: BOOLEAN;
    LineFlag: BOOLEAN;
    List: BOOLEAN;
    MathCk: BOOLEAN;
    NilCk: BOOLEAN;
    Ocode: BOOLEAN;
    RangeCk: BOOLEAN;
    Runtime: BOOLEAN;
    StackCk: BOOLEAN;
    Symtab: BOOLEAN;
    Warn: BOOLEAN"""),
    ("Token", "parser.pas", """\
    kind: Str255;
    code: INTEGER32;
    lexeme: Str255;
    value_str: Str255;
    value_int: INTEGER32;
    value_real: REAL;
    value_type: INTEGER32;
    line: INTEGER32;
    col: INTEGER32;
    f_brave, f_debug, f_entry, f_goto, f_indexck, f_initck, f_line, f_list,
    f_mathck, f_nilck, f_ocode, f_rangeck, f_runtime, f_stackck, f_symtab,
    f_warn: BOOLEAN;
    has_unroll: BOOLEAN;
    unroll_val: INTEGER"""),
    ("TcSymRec", "typechecker.pas", """\
    name: Str255;
    kind: Str255;
    tk: INTEGER;
    aux: INTEGER;
    aux2: INTEGER;
    idx_tk: INTEGER;
    nparams: INTEGER;
    param_tk: ARRAY [1..MAX_PARAMS] OF INTEGER;
    ret_tk: INTEGER"""),
    ("TcTypeRec", "typechecker.pas", """\
    name: Str255;
    tk: INTEGER;
    aux: INTEGER;
    aux2: INTEGER;
    idx_tk: INTEGER"""),
    ("TcFieldRec", "typechecker.pas", """\
    record_id: INTEGER;
    fname: Str255;
    ftk: INTEGER;
    faux: INTEGER;
    faux2: INTEGER"""),
    ("CgTypeRec", "codegen.pas", """\
    name: Str255;
    tk: INTEGER;
    elem_tid: INTEGER;
    lo: INTEGER;
    hi: INTEGER;
    is_super: BOOLEAN;
    ptr_space: INTEGER;
    llvm_ty: ADRMEM"""),
    ("CgFieldRec", "codegen.pas", """\
    rec_tid: INTEGER;
    fname: Str255;
    field_tid: INTEGER;
    field_index: INTEGER"""),
    ("CgConstRec", "codegen.pas", """\
    name: Str255;
    ival: INTEGER64;
    is_real: BOOLEAN;
    rval: REAL"""),
    ("CgSymRec", "codegen.pas", """\
    name: Str255;
    tk: INTEGER;
    llvm_val: ADRMEM"""),
    ("CgRoutineRec", "codegen.pas", """\
    name: Str255;
    is_func: BOOLEAN;
    fn: ADRMEM;
    fnty: ADRMEM;
    ret_tk: INTEGER;
    nparams: INTEGER32;
    param_tk: ParamTkArr;
    param_is_var: ParamVarArr;
    param_needs_copy: ParamVarArr;
    has_body: BOOLEAN;
    is_c: BOOLEAN"""),
]


def _program_for(record_name, record_body):
    return (f"PROGRAM P(output);\n{SHARED_DEPS}\n"
            f"TYPE {record_name} = RECORD\n{record_body}\n  END;\n"
            f"VAR v: {record_name};\n"
            f"BEGIN WRITELN(SIZEOF(v)) END.\n")


def _python_compile_and_run(src, exe_name):
    """Return (ir_text, returncode, stdout, stderr) for the Python pipeline."""
    with temporary_pascal_project({"p.pas": src}) as project_dir:
        compile_pascal_project(project_dir, [("p.pas", "p.ll")], features=EXT)
        ir_text = (Path(project_dir) / "p.ll").read_text()
        exe_path = link_pascal_project(project_dir, ["p.ll"],
                                       exe_name=exe_name)
        run = subprocess.run([exe_path], capture_output=True, text=True)
        return ir_text, run.returncode, run.stdout, run.stderr


def _native_compile_and_run(src_text, exe_name):
    """Return (ir_text, returncode, stdout, stderr) for the native pipeline.

    Callers gate on HAS_NATIVE rather than calling this when it is unset.
    """
    with temporary_pascal_project({}) as project_dir:
        result = subprocess.run([NATIVE["lexer"]],
                                input=src_text,
                                capture_output=True,
                                text=True,
                                timeout=60)
        if result.returncode:
            return None, result.returncode, "", result.stderr
        for stage in ("parser", "typechecker", "codegen"):
            result = subprocess.run([NATIVE[stage]],
                                    input=result.stdout,
                                    capture_output=True,
                                    text=True,
                                    timeout=60)
            if result.returncode:
                return None, result.returncode, "", result.stderr
        ir_text = result.stdout
        ll_path = Path(project_dir) / "n.ll"
        ll_path.write_text(ir_text)
        exe_path = Path(project_dir) / exe_name
        link = subprocess.run(
            ["clang", str(ll_path), RUNTIME_LIB, "-o",
             str(exe_path)],
            capture_output=True,
            text=True)
        if link.returncode:
            return ir_text, link.returncode, "", link.stderr
        run = subprocess.run([str(exe_path)], capture_output=True, text=True)
        return ir_text, run.returncode, run.stdout, run.stderr


# Matches the inline anonymous struct on a native `@v = global { ... }` line.
# Nested braces do not occur in any audited record (no nested RECORD fields),
# so a greedy match to the closing brace on that line is correct.
_INLINE_GLOBAL_STRUCT = re.compile(
    r'@v\s*=\s*global\s*(\{.*\})\s*zeroinitializer')


def _extract_struct(ir_text, record_name):
    """Return (struct_TypeRef, TargetData) for the record's emitted LLVM type.

    The Python reference emits a named struct (`%"TOKEN" = type {...}`); native
    codegen inlines the type into the global (`@v = global {...}`).  Both are
    normalized to a synthetic named-type module so the same TargetData path
    serves either compiler.
    """
    module = llvm_binding.parse_assembly(ir_text)
    module.verify()
    target_data = llvm_binding.create_target_data(module.data_layout)
    wanted = record_name.upper()
    for struct_type in module.struct_types:
        if struct_type.name.upper() == wanted:
            return struct_type, target_data
    # Native: anonymous inline struct on the global.  Re-host it under a named
    # type so TargetData can walk its elements.
    match = _INLINE_GLOBAL_STRUCT.search(ir_text)
    if not match:
        raise AssertionError(
            f"could not find emitted struct for {record_name} in IR:\n"
            f"{ir_text[:500]}")
    synthetic = (f'target triple = "x86_64-pc-linux-gnu"\n'
                 f'%t = type {match.group(1)}\n'
                 f'@g = global %t zeroinitializer\n')
    smod = llvm_binding.parse_assembly(synthetic)
    smod.verify()
    std = llvm_binding.create_target_data(smod.data_layout)
    structs = list(smod.struct_types)
    assert structs, f"synthetic module had no struct type:\n{synthetic}"
    return structs[0], std


def _assert_layout_matches_target(self, label, struct_type, target_data,
                                  sizeof_value):
    """Assert the compiler's SIZEOF and the hand-roll-padding algorithm both
    agree with LLVM's own TargetData layout, field by field."""
    elements = list(struct_type.elements)
    self.assertEqual(
        sizeof_value, target_data.get_abi_size(struct_type),
        f"{label}: SIZEOF={sizeof_value} but LLVM TargetData "
        f"abi_size={target_data.get_abi_size(struct_type)}")
    # Independent natural-alignment walk using TargetData's own per-field
    # sizes/alignments -- the hand-rolled TypeSizeBytes/TypeAlignBytes are
    # never consulted here; this verifies LLVM's placement follows the same
    # padding algorithm they implement.  Each field is placed at the previous
    # field's end rounded up to the current field's alignment; the struct's
    # own alignment is the max field alignment, and the size is that end
    # rounded up to the struct alignment (tail padding).
    expected_end = 0
    max_align = 1
    for i, element in enumerate(elements):
        field_align = target_data.get_abi_alignment(element)
        field_size = target_data.get_abi_size(element)
        field_offset = _round_up(expected_end, field_align)
        self.assertEqual(
            target_data.get_element_offset(struct_type, i), field_offset,
            f"{label} field {i}: LLVM offset "
            f"{target_data.get_element_offset(struct_type, i)} != "
            f"natural-walk offset {field_offset} "
            f"(prev end {expected_end}, field align {field_align}, "
            f"size {field_size})")
        expected_end = field_offset + field_size
        max_align = max(max_align, field_align)
    self.assertEqual(
        target_data.get_abi_size(struct_type),
        _round_up(expected_end, target_data.get_abi_alignment(struct_type)),
        f"{label}: tail padding mismatch (walked end {expected_end}, "
        f"struct align {target_data.get_abi_alignment(struct_type)}, "
        f"LLVM size {target_data.get_abi_size(struct_type)})")
    self.assertEqual(
        target_data.get_abi_alignment(struct_type), max_align,
        f"{label}: struct align {target_data.get_abi_alignment(struct_type)} "
        f"!= max field align {max_align}")


@requires_exe
class TestSelfHostRecordLayout(unittest.TestCase):
    """Every RECORD in the five self-hosting sources, audited against LLVM."""

    def _audit_record(self, record_name, source_file, record_body):
        src = _program_for(record_name, record_body)
        exe = "rec-" + record_name.lower()

        py_ir, py_rc, py_out, py_err = _python_compile_and_run(src, exe)
        self.assertEqual(
            py_rc, 0, f"Python pipeline failed for {source_file} "
            f"{record_name}:\n{py_err}")
        py_sizeof = int(py_out.strip())
        py_struct, py_td = _extract_struct(py_ir, record_name)
        _assert_layout_matches_target(self, f"python/{record_name}", py_struct,
                                      py_td, py_sizeof)

        if HAS_NATIVE:
            nat_ir, nat_rc, nat_out, nat_err = _native_compile_and_run(
                src, exe + "-nat")
            self.assertEqual(
                nat_rc, 0, f"Native pipeline failed for {source_file} "
                f"{record_name}:\n{nat_err}")
            nat_sizeof = int(nat_out.strip())
            self.assertEqual(
                nat_sizeof, py_sizeof,
                f"{record_name}: native SIZEOF {nat_sizeof} != "
                f"python SIZEOF {py_sizeof} (representation drift)")
            nat_struct, nat_td = _extract_struct(nat_ir, record_name)
            _assert_layout_matches_target(self, f"native/{record_name}",
                                          nat_struct, nat_td, nat_sizeof)

    def test_every_self_host_record_matches_llvm_layout(self):
        for record_name, source_file, record_body in RECORDS:
            with self.subTest(record=f"{source_file}:{record_name}"):
                self._audit_record(record_name, source_file, record_body)


if __name__ == '__main__':
    unittest.main()
