"""Private process workspace for Python harnesses, including signal cleanup.

Import before creating any tempfile objects. Never remove the shared namespace
or another process's workspace. SIGKILL and power loss cannot be cleaned up.
"""
import atexit
import os
from pathlib import Path
import shutil
import signal
import tempfile

BASE = Path('/tmp/native-pascal-1981')
OWNER = os.getpid()
WORK = None
SIGNALS = {signal.SIGHUP, signal.SIGINT, signal.SIGTERM}


def cleanup():
    if os.getpid() == OWNER and WORK:
        shutil.rmtree(WORK, ignore_errors=True)


def terminate(signum, frame):
    raise SystemExit(128 + signum)


# Do not leave a signal-sized gap between allocation and cleanup registration.
previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, SIGNALS)
try:
    BASE.mkdir(mode=0o700, exist_ok=True)
    if (BASE.is_symlink() or BASE.stat().st_uid != os.getuid()
            or BASE.stat().st_mode & 0o022):
        raise RuntimeError(f'unsafe temporary root: {BASE}')
    WORK = tempfile.mkdtemp(prefix='python-', dir=BASE)
    atexit.register(cleanup)
    for sig in (signal.SIGHUP, signal.SIGTERM):
        signal.signal(sig, terminate)
    tempfile.tempdir = WORK
    os.environ['TMPDIR'] = WORK
finally:
    signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
