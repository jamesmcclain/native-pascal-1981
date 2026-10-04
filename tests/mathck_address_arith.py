#!/usr/bin/env python3
"""Address arithmetic and [C] values at MATHCK's boundary.

Pointer/ADRMEM `+ offset` is an element-scaled (byte-scaled for ADRMEM)
non-inbounds GEP: address arithmetic, not MATHCK, never trapping and never
LLVM UB. The offset is widened by its own signedness, so a WORD offset of
40000 addresses element 40000. Arithmetic *inside* an offset expression is
ordinary MATHCK arithmetic at its own operators. Other pointer operators are
typecheck errors. Arithmetic inside a [C] routine is outside MATHCK; a [C]
result used in Pascal arithmetic is checked like any other value.
"""
import resource
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, run

WORD_OFFSET = """{{$MATHCK{flag}}}
PROGRAM WordOffset(output);
VAR big: ARRAY [0..40001] OF CHAR; pc, base: ^CHAR; w: WORD; a: ADRMEM;
BEGIN
  base := ADR big;
  big[40000] := 'Z'; big[1] := 'a'; big[32768] := 'm';
  w := 40000; pc := base + w; WRITELN(pc^);
  w := 32768; pc := w + base; WRITELN(pc^);
  w := 1; pc := base + w; WRITELN(pc^);
  a := ADR big; a := a + 40000; pc := a; WRITELN(pc^)
END.
"""
C_VALUE = """{{$MATHCK{flag}}}
PROGRAM CValue(output);
VAR c: CINT;
FUNCTION abs(x: CINT): CINT [C]; EXTERN;
BEGIN
  c := abs(-2147483647);
  WRITELN('prefix');
  WRITELN(c + 1)
END.
"""
IR_SOURCE = """{$MATHCK+}
PROGRAM Gep(output);
TYPE PI = ^INTEGER;
VAR p, q: PI; n: INTEGER32;
BEGIN
  NEW(p); n := 2147483647;
  q := p + n;
  q := p + (n - 1)
END.
"""
REJECTED = [
    'q := p - 1', 'q := p * 2', 'q := p DIV 2', 'q := 2 - p', 'q := p + 1.5'
]


def build(work, name, source, opt, extra=()):
    path = work / f'{name}.pas'
    out = work / name
    path.write_text(source)
    return run([
        'bin/pascal1981', '--dialect', 'extended', f'-O{opt}', *extra,
        str(path), '-o',
        str(out)
    ]), out


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    cells = 0
    with tempfile.TemporaryDirectory(prefix='mathck-address-') as tmp:
        work = Path(tmp)
        for flag in ['+', '-']:
            for opt in OPTS:
                built, exe = build(work, f'word_{flag == "+"}_{opt}',
                                   WORD_OFFSET.format(flag=flag), opt)
                assert built.returncode == 0, built.stderr
                result = run([str(exe)])
                assert (result.returncode, result.stdout,
                        result.stderr) == (0, 'Z\nm\na\nZ\n', ''), result
                cells += 1
                built, exe = build(work, f'c_{flag == "+"}_{opt}',
                                   C_VALUE.format(flag=flag), opt)
                assert built.returncode == 0, built.stderr
                result = run([str(exe)])
                if flag == '+':
                    column = '  WRITELN(c + 1)'.index('+') + 1
                    want = ('prefix\n',
                            'runtime error: MATHCK signed overflow in + at '
                            f'line 8 column {column} (left=2147483647, '
                            'right=1)\n')
                    assert result.returncode != 0, result
                else:
                    want = ('prefix\n-2147483648\n', '')
                    assert result.returncode == 0, result
                assert (result.stdout, result.stderr) == want, result
                cells += 1
        built, ll = build(work, 'gep.ll', IR_SOURCE, 0, ['-S'])
        assert built.returncode == 0, built.stderr
        text = ll.read_text()
        # Two GEPs with i64 offsets; only the offset expression's `-` is
        # checked (one overflow intrinsic), never the address step.
        assert text.count('getelementptr i16, ptr') == 2, text
        assert 'getelementptr inbounds' not in text, text
        assert text.count(
            'call { i32, i1 } @llvm.ssub.with.overflow.i32') == 1, text
        assert 'sadd.with.overflow' not in text, text
        cells += 1
        for index, statement in enumerate(REJECTED):
            source = IR_SOURCE.replace('q := p + (n - 1)', statement)
            built, _ = build(work, f'rej{index}.ll', source, 0, ['-S'])
            assert built.returncode != 0, statement
            assert ('Pointer arithmetic supports only pointer + integer '
                    'offset') in built.stderr, (statement, built.stderr)
            cells += 1
    print(f'PASS: MATHCK address arithmetic boundary: {cells} cells (WORD/'
          'ADRMEM GEP offsets at O0-O3 under both settings, unchecked GEP '
          'with checked offset expressions, [C] results checked in Pascal, '
          'non-+ pointer operators rejected)')


if __name__ == '__main__':
    main()
