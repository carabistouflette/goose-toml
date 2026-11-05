import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.build/toml-ann-01'
OUT.mkdir(exist_ok=True)
START = time.monotonic()
DEADLINE = START + 1500
utc = lambda: dt.datetime.now(dt.timezone.utc).isoformat()
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
report = {'reservation': 'TOML-ANN-01', 'task': 'GL-DOCSTOML-01',
          'started_utc': utc(), 'max_wall_seconds': 1500, 'controller_pid': os.getpid(),
          'controller_pgid': os.getpgrp(), 'commands': [], 'exit_code': None}
children = []

def save():
    (OUT / 'controller.json').write_text(json.dumps(report, indent=2) + '\n')

def group_members(pgid):
    found = []
    for p in Path('/proc').iterdir():
        if not p.name.isdigit():
            continue
        try:
            fields = (p / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == pgid:
                found.append({'pid': int(p.name), 'state': fields[0]})
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found

def stop_group(p):
    if group_members(p.pid):
        try: os.killpg(p.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: p.wait(timeout=min(2, max(.01, DEADLINE-time.monotonic())))
        except subprocess.TimeoutExpired: pass
        if group_members(p.pid):
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
    if p.poll() is None:
        p.wait(timeout=2)

def run(command, label, limit=30):
    remaining = DEADLINE - time.monotonic() - 5
    if remaining <= 0:
        raise TimeoutError('controller deadline before ' + label)
    logfile = OUT / (str(len(report['commands'])) + '-' + label + '.log')
    row = {'label': label, 'argv': command, 'started_utc': utc(), 'log': str(logfile.relative_to(ROOT))}
    report['commands'].append(row)
    with logfile.open('w') as log:
        p = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                             start_new_session=True, env={**os.environ, 'CARGO_BUILD_JOBS': '1'})
        children.append(p); row['pid_pgid'] = p.pid; save()
        try:
            code = p.wait(timeout=min(limit, remaining))
        except subprocess.TimeoutExpired:
            stop_group(p); row['timeout'] = True; code = 124
        row.update(exit_code=code, ended_utc=utc(), remaining_group_members=group_members(p.pid))
    save()
    print(label, 'EXIT', code, 'UTC', row['ended_utc'], flush=True)
    if row['remaining_group_members']:
        stop_group(p)
        raise RuntimeError('child group remained after ' + label)
    if code:
        raise RuntimeError(label + ' exited ' + str(code))
    return logfile.read_text().strip()

def verify():
    data = json.loads((ROOT/'docs/announcement-readiness-inputs.json').read_text())
    assert all(sha(ROOT/p) == h for p,h in data['source_sha256'].items()), '22-input drift'
    assert sha(ROOT/'.toolchain/goose/build/goose') == '3cad45a18356bf97f4732f1da2012252afd77a652932ddb9c91c5551c04904be'
    report['input_sha256'] = data['source_sha256']
    report['compiler_sha256'] = sha(ROOT/'.toolchain/goose/build/goose')
    assert platform.machine() == 'x86_64'
    assert 'Intel(R) Core(TM) Ultra 7 258V' in Path('/proc/cpuinfo').read_text()

def interrupted(signum, frame):
    raise RuntimeError('controller interrupted by signal ' + str(signum))

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
save()
try:
    verify()
    report['platform'] = platform.platform()
    assert 3 in os.sched_getaffinity(0), 'CPU3 unavailable'
    os.sched_setaffinity(0, {3}); report['cpu_affinity'] = sorted(os.sched_getaffinity(0))
    assert run(['git','rev-parse','HEAD'], 'docs-head') == '6be3e2cf1c777887efed1a3fc2ad7183be8d0608'
    assert not run(['git','status','--porcelain'], 'docs-clean')
    assert run(['git','-C','.toolchain/goose','rev-parse','HEAD'], 'compiler-head') == 'eadca409f68210893f366e60d0c2f0dc29a339be'
    assert not run(['git','-C','.toolchain/goose','status','--porcelain','--untracked-files=no'], 'compiler-clean')
    assert run(['git','-C','.toolchain/tomlplusplus','rev-parse','HEAD'], 'cpp-head') == '30172438cee64926dc41fdd9c11fb3ba5b2ba9de'
    assert not run(['git','-C','.toolchain/tomlplusplus','status','--porcelain','--untracked-files=no'], 'cpp-clean')
    for tool in ['gcc','g++']:
        version = run([tool,'--version'], tool+'-version')
        assert '16.2.1' in version
        report[tool+'_version'] = version
    base = [sys.executable,'scripts/compare.py','--cpu','3','--corpus','extended']
    run(base+['--build-only'], 'one-build', 1495)
    verify()
    for mode in ['full','write']:
        target = '.build/compare/announcement-'+mode+'.json'
        run(base+['--mode',mode,'--no-build','--iterations','100000','--rounds','9',
                  '--seed','20261104','--timezone','UTC','--output',target], mode+'-series',1495)
        verify()
        result = json.loads((ROOT/target).read_text())
        assert result['rounds']==9 and result['mode']==mode and result['corpus']=='extended'
        assert len(result['manifest']['cases'])==12
        report[mode+'_report_sha256'] = sha(ROOT/target)
    report['exit_code'] = 0
except BaseException as exc:
    report['error'] = type(exc).__name__ + ': ' + str(exc)
    report['exit_code'] = 1
finally:
    for p in children:
        if group_members(p.pid): stop_group(p)
    report['cleanup_groups'] = {str(p.pid): group_members(p.pid) for p in children}
    report['all_owned_groups_absent'] = not any(report['cleanup_groups'].values())
    report['ended_utc'] = utc()
    report['elapsed_wall_seconds'] = time.monotonic()-START
    report['controller_source_sha256'] = sha(Path(__file__))
    save()
print(json.dumps({k:report.get(k) for k in ['started_utc','ended_utc','exit_code','elapsed_wall_seconds','all_owned_groups_absent','error']}), flush=True)
sys.exit(report['exit_code'])
