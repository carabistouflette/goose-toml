# SPDX-License-Identifier: Apache-2.0
"""Exact legacy output/diagnostic fixtures and independent insertion checks."""
import base64
import json
import random
import subprocess
from pathlib import Path


def run(executable):
    fixture = json.loads(Path(__file__).with_name('legacy-contract.json').read_text())
    assert fixture['legacy_revision'] == 'cedb2c3c98affbeb45bd34bc7a6618f5a9b75ad0'
    cases = []
    for case in fixture['cases']:
        assert case['status'] in (0, 1)
        assert bool(case['status']) == bool(case['error']), case['case']
        decode = lambda name: base64.b64decode(case[name + '_b64'], validate=True)
        cases.append((case['case'], case['mode'], decode('source'), [p.encode() for p in case['path']],
                      decode('value'), decode('output'), case['error'].encode()))
    # Independent byte model: header/root insertion, quoting and trivia retention.
    rng = random.Random(20261107)
    for n in range(512):
        key = rng.choice(['new', 'é🦆', 'a.b', '', 'quote"slash\\', '\x7f', '\x0b', '\0'])
        quoted = json.dumps(key, ensure_ascii=False).replace('\\u000b', '\\u000B').replace('\x7f', '\\u007F')
        value = rng.choice([b'1', b"'hello'", b'[1,\n # inner\n 2]', b'{a=1}', b'1 \t'])
        eol = rng.choice([b'\n', b'\r\n'])
        header = b'[a] # header' + eol
        body = b'# lead' + eol + b'x=1 # keep' + eol
        addition = quoted.encode() + b' = ' + value + eol
        if n % 2:
            source = b'# title' + eol + header + body
            path = [b'a', key.encode()]
            output = b'# title' + eol + header + addition + body
        else:
            source = b'# title' + eol + b'x=1' + eol
            path = [key.encode()]
            output = addition + source
        cases.append((f'generated-{n}', 'set', source, path, value, output, b''))
    payload = ''.join('\t'.join(['LS' if mode == 'set' else 'LR', source.hex(), value.hex(),
                               *[key.hex() for key in path]]) + '\n'
                      for _, mode, source, path, value, _, _ in cases)
    result = subprocess.run([str(Path(executable).resolve())], input=payload, text=True,
                            capture_output=True, timeout=120)
    if result.returncode:
        raise AssertionError(result.stderr[:4096])
    lines = result.stdout.splitlines()
    assert len(lines) == len(cases), (len(lines), len(cases), result.stderr[:1000])
    for case, line in zip(cases, lines):
        name, _, _, _, _, expected_output, expected_error = case
        status, output, error = line.split('\t')
        actual = status, bytes.fromhex(output), bytes.fromhex(error)
        expected = 'E' if expected_error else 'O', expected_output, expected_error
        assert actual == expected, (name, actual, expected)
    print(f'{len(cases)} legacy-profile byte/diagnostic checks passed')
