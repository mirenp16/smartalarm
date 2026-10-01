#!/usr/bin/env python3
"""Compile production Monkey C and run regression tests in Garmin's simulator."""
import os
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
config = Path.home() / 'Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg'
sdk = Path(os.environ['CIQ_SDK']) if 'CIQ_SDK' in os.environ else Path(config.read_text().strip())
out = ROOT / 'bin' / 'validation'
out.mkdir(parents=True, exist_ok=True)
key = out / 'test-key.der'
if not key.exists():
    pem = out / 'test-key.pem'
    subprocess.run(['openssl', 'genrsa', '-out', str(pem), '4096'], check=True, capture_output=True)
    subprocess.run(['openssl', 'pkcs8', '-topk8', '-inform', 'PEM', '-outform', 'DER',
                    '-in', str(pem), '-out', str(key), '-nocrypt'], check=True)
    pem.unlink()

for jungle, name, extra in [('monkey.jungle', 'smartalarm', ['-r']), ('tests.jungle', 'tests', ['-t'])]:
    subprocess.run([str(sdk / 'bin/monkeyc'), '-f', jungle, '-o', str(out / (name + '.prg')),
                    '-y', str(key), '-d', 'fr265s', '-w', *extra], cwd=ROOT, check=True)
subprocess.run([str(sdk / 'bin/connectiq')], check=True)
# Reusing tests.prg can run an older simulator-loaded suite after rebuilding.
# A content-specific name ensures a different binary has a different identity.
compiled = out / 'tests.prg'
digest = hashlib.sha256(compiled.read_bytes()).hexdigest()[:16]
run_prg = out / f'tests-{digest}.prg'
shutil.copyfile(compiled, run_prg)
debug = out / 'tests.prg.debug.xml'
if debug.exists():
    shutil.copyfile(debug, Path(str(run_prg) + '.debug.xml'))
runs = int(sys.argv[1]) if len(sys.argv) > 1 else 1
expected = sum(len(re.findall(r'\(:test\)\s*function\s+', path.read_text()))
               for path in (ROOT / 'tests').glob('*.mc'))
if runs < 1:
    raise SystemExit('At least one run is required')
for run in range(1, runs + 1):
    # macOS open returns before the simulator starts listening. Retry only a
    # connection failure, never a test failure or an incomplete test execution.
    for attempt in range(10):
        result = subprocess.run([str(sdk / 'bin/monkeydo'), str(run_prg), 'fr265s', '-t'],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        if 'Unable to connect to simulator.' not in result.stdout or 'Executing test' in result.stdout:
            break
        if attempt < 9:
            time.sleep(2)
    print(result.stdout, flush=True)
    (out / f'tests-{run}.log').write_text(result.stdout)
    # SDK 9.2 monkeydo exits 1 even on success. Require the full result footer,
    # positive test count and zero failures/errors; a crash or empty run fails.
    match = re.search(r'PASSED \(passed=(\d+), failed=0, errors=0\)', result.stdout)
    if not match or int(match[1]) != expected or expected == 0:
        raise SystemExit(f'Simulator regression run {run} failed or was incomplete')
print(f'PASS: release build and {runs} simulator run(s), {expected} tests per run')
