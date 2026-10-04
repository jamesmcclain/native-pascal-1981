#!/usr/bin/env python3
"""MATHCK on/off twins: programs that never overflow behave identically.

Corpus twin: every single-file fixture under tests/golden, tests/integration
and tests/dialect is compiled and run twice, with `{$MATHCK+}` and with
`{$MATHCK-}` written in front of its first line (so line numbers do not
move), at O0 and O2. Compile status and diagnostics, exit code, stdout and
stderr must match. A fixture whose MATHCK+ run reports a MATHCK error is an
overflowing program; its disabled twin is not an oracle here (§1 defines the
wrap, the dedicated MATHCK suites pin it) and it is counted, not compared.

Feature twin: tests/fixtures/mathck/twin_extended.pas exercises every
extended width, the scoped builtins, the SADDOK family, VECTOR lanes and
reductions and FOR loops ending at each type's maximum, with no overflow;
it must print twin_extended.out under both settings at O0-O3.
"""
import resource
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, ROOT, run

CORPUS_DIRS = ['tests/golden', 'tests/integration', 'tests/dialect']
CORPUS_OPTS = (0, 2)


def fixture_dialect(src):
    for line in src.read_text(errors='replace').splitlines():
        text = line.strip()
        if text.startswith('{') and text.endswith('}'):
            body = text[1:-1].strip()
            if body.startswith('DIALECT:'):
                return body.split(':', 1)[1].strip()
    sidecar = src.with_suffix('.dialect')
    if sidecar.exists():
        return sidecar.read_text().strip()
    return None


def corpus():
    for directory in CORPUS_DIRS:
        for src in sorted((ROOT / directory).glob('*.pas')):
            if src.with_suffix('.build.sh').exists():
                continue
            yield src


def build_and_run(work, src, flag, opt):
    tag = f'{src.parent.name}_{src.stem}_{flag == "+"}_O{opt}'
    path = work / f'{tag}.pas'
    exe = work / tag
    text = src.read_text(errors='surrogateescape')
    path.write_text(f'{{$MATHCK{flag}}}' + text, errors='surrogateescape')
    dialect = fixture_dialect(src)
    args = ['bin/pascal1981', f'-O{opt}']
    if dialect:
        args += ['--dialect', dialect]
    built = run(args + [str(path), '-o', str(exe)])
    # Diagnostics name the temporary file; compare them without it.
    compile_err = built.stderr.replace(str(path), '<src>')
    if 'linker command failed' in compile_err:
        # Object names and code offsets differ between the settings; only
        # the outcome is compared (the driver does not link -lm: see the
        # MATHCK gaps record, §8).
        return ('link', built.returncode)
    if built.returncode != 0:
        return ('compile', built.returncode, compile_err)
    stdin = src.with_suffix('.stdin')
    argv = src.with_suffix('.args')
    extra = argv.read_text().splitlines() if argv.exists() else []
    result = subprocess.run([str(exe)] + extra,
                            cwd=src.parent,
                            input=stdin.read_text() if stdin.exists() else '',
                            text=True,
                            errors='surrogateescape',
                            capture_output=True,
                            timeout=60)
    return ('run', result.returncode, result.stdout, result.stderr,
            compile_err)


def check_corpus(work):
    jobs = [(src, opt) for src in corpus() for opt in CORPUS_OPTS]

    def one(job):
        src, opt = job
        on = build_and_run(work, src, '+', opt)
        off = build_and_run(work, src, '-', opt)
        if on[0] == 'run' and 'MATHCK' in on[3]:
            return 'overflowing'
        assert on == off, (str(src), opt, on, off)
        return on[0]

    with ThreadPoolExecutor(max_workers=16) as pool:
        outcomes = list(pool.map(one, jobs))
    return {kind: outcomes.count(kind) for kind in set(outcomes)}


def check_extended(work):
    fixture = ROOT / 'tests/fixtures/mathck/twin_extended.pas'
    expected = fixture.with_suffix('.out').read_text()
    jobs = [(flag, opt) for flag in '+-' for opt in OPTS]

    def one(job):
        flag, opt = job
        tag = f'twin_extended_{flag == "+"}_O{opt}'
        path = work / f'{tag}.pas'
        exe = work / tag
        path.write_text(f'{{$MATHCK{flag}}}\n' + fixture.read_text())
        built = run([
            'bin/pascal1981', '--dialect', 'extended', f'-O{opt}',
            str(path), '-o',
            str(exe)
        ])
        assert built.returncode == 0, (tag, built.stderr)
        result = run([str(exe)])
        assert (result.returncode, result.stdout,
                result.stderr) == (0, expected, ''), (tag, result)

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(one, jobs))
    return len(jobs)


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-twins-') as tmp:
        work = Path(tmp)
        extended = check_extended(work)
        kinds = check_corpus(work)
    print(f'PASS: MATHCK on/off twins: {extended} extended-fixture cells '
          '(all widths, builtins, SADDOK family, VECTOR, FOR to the maximum; '
          'O0-O3); corpus fixtures at O0/O2: '
          f'{kinds.get("run", 0)} runs, {kinds.get("compile", 0)} '
          f'rejections and {kinds.get("link", 0)} link failures identical '
          'under MATHCK+/-, '
          f'{kinds.get("overflowing", 0)} overflowing (not compared)')


if __name__ == '__main__':
    main()
