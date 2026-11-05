#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent semantic oracle and preservation of unrelated comments."""
import copy
import json
import random
import subprocess
import sys
import tomllib
from pathlib import Path
if not __debug__:
    raise SystemExit('Do not use -O: assertions are required')
rng = random.Random(20261106)
q = lambda value: json.dumps(value, ensure_ascii=False)
cases = []
for index in range(2400):
    eol = rng.choice(['\r\n', '\n'])
    table = rng.choice(['dependencies', 'dev-dependencies', 'déps.with.dot', ''])
    key = rng.choice(['helper', 'lib.with.dot', '🦆', 'quote"slash\\', ''])
    selected = key if (index // 12) % 3 else key + '_new'
    style = index % 6
    protected = [f'# PROTECTED-{index}-lead', f'# PROTECTED-{index}-tail']
    lines = [protected[0], 'keep=0x10']
    entry = q(key) + " = { path = '../old' }"
    if style == 0:
        lines += ['[' + q(table) + ']', entry + ' ' + protected[1]]
    elif style == 1:
        lines += [q(table) + '.' + entry + ' ' + protected[1]]
    elif style == 2:
        lines += ['[' + q(table) + '.' + q(key) + ']', "path='../old' " + protected[1]]
    elif style == 3:
        lines += [q(table) + ' = { ' + entry + ' } ' + protected[1]]
    elif style == 4:
        lines += ['[' + q(table) + ']', q(key) + ".path='../old' " + protected[1]]
    else:
        lines += [protected[1]]
    lines += ['[unrelated]', "text='''[fake.header] # not a comment'''"]
    source = eol.join(lines) + (eol if index % 4 else '')
    operation = 'R' if (index // 6) % 2 else 'P'
    value = rng.choice(["{path='世界/🦆'}", '[1, 2, 3]', '0x2A', 'true', "'café'", '"quoted\\nvalue"'])
    expected = copy.deepcopy(tomllib.loads(source))
    exists = table in expected and selected in expected[table]
    unsupported = style == 3 and ((operation == 'P' and not exists) or (operation == 'R' and exists))
    unsupported |= operation == 'P' and exists and style in (2, 4)
    if not unsupported:
        if operation == 'P':
            expected.setdefault(table, {})[selected] = tomllib.loads('v=' + value)['v']
        elif exists:
            del expected[table][selected]
            if style in (1, 2) and not expected[table]:
                del expected[table]
    cases.append((operation, source, table, selected, value, None if unsupported else expected, protected))
for value in ['1\nextra=2', '1\n[v.x]\ny=2', '#missing', '"\\ud800"', '\xff']:
    cases.append(('P', '[dependencies]\nx=1\n', 'dependencies', 'new', value, None, []))
payload = ''.join('\t'.join([op, source.encode().hex(), table.encode().hex(), key.encode().hex(), value.encode().hex()]) + '\n'
                  for op, source, table, key, value, expected, comments in cases)
run = subprocess.run([str(Path(sys.argv[1]).resolve())], input=payload, text=True, capture_output=True, timeout=120)
if run.returncode:
    sys.stderr.write(run.stderr[:4096]); run.check_returncode()
lines = run.stdout.splitlines()
assert len(lines) == len(cases), (len(lines), len(cases), run.stderr[:1000])
for case, line in zip(cases, lines):
    op, source, table, key, value, expected, comments = case
    status, data = line.split('\t')
    output = bytes.fromhex(data).decode()
    if expected is None:
        assert status == 'E' and not output, (case, status, output)
    else:
        assert status == 'O', case
        actual = tomllib.loads(output)
        assert actual == expected, (case, actual, expected, output)
        for comment in comments:
            assert output.count(comment) == source.count(comment), (case, comment, output)
        assert "[unrelated]" in output and "text='''[fake.header] # not a comment'''" in output
print(f'{len(cases)} source-edit model/preservation cases passed')

import compatibility
compatibility.run(sys.argv[1])
