#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Constructed exact bytes and independent semantic trees for inline insertion."""
import copy
import json
from pathlib import Path
import random
import subprocess
import sys
import tomllib
if not __debug__:
    raise SystemExit('Assertions required; do not use -O')
rng = random.Random(20261110)
q = lambda text: json.dumps(text, ensure_ascii=False).replace('\x7f', '\\u007f')
hx = lambda text: text.encode().hex()
keys = ['', 'plain', 'a.b', '世界', '🦆', 'quote"slash\\', '\x00\x7f', '\n\t']
values = ['0x2A', 'true', "'世界'", '[1, 2]', "{nested='kept'}", '[\n1,# array comment\n2\n]']
singles, batches = [], []
def same(a, b):
    if type(a) is not type(b): return False
    if isinstance(b, dict): return a.keys() == b.keys() and all(same(a[k], b[k]) for k in b)
    if isinstance(b, list): return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b

def add(version, source, requests, expected, single=False):
    if version == 10 and expected is not None:
        model = copy.deepcopy(tomllib.loads(source))
        for path, raw in requests:
            parent = model
            for key in path[:-1]: parent = parent.setdefault(key, {})
            parent[path[-1]] = tomllib.loads('v=' + raw)['v']
        assert same(model, tomllib.loads(expected)), (source, requests, expected)
    row = version, source, requests, expected
    if single: singles.append(row)
    batches.append(row)

for i in range(640):
    owner, key = rng.sample(keys, 2); value = rng.choice(values); style = i % 8
    prefix = '# keep\r\n' + q(owner) + '={'
    inside, suffix, relative, path = 'old=1', '} # tail\r\n', [key], [owner, key]
    if style == 0: inside = ''
    if style == 1: inside = '  '
    if style == 2: inside = "old=[{text='}, ='},2]"
    if style == 3:
        prefix += 'nest={'; suffix = '},other=2}' + suffix[1:]; path = [owner, 'nest', key]
    if style == 4:
        inside = 'nest.old=1'; relative = ['nest', key]; path = [owner, 'nest', key]
    if style == 5:
        relative = ['missing', key]; path = [owner, 'missing', key]
    if style == 6:
        prefix = '# keep\n[top.child]\nx=2\n[top]\n' + q(owner) + '={'
        path = ['top', owner, key]
    if style == 7:
        prefix = '# keep\nroot.' + q(owner) + '={'
        path = ['root', owner, key]
    entry = '.'.join(map(q, relative)) + ' = ' + value
    separator = ', ' if inside.strip() else ''
    add(10, prefix + inside + suffix, [(path, value)], prefix + entry + separator + inside + suffix, True)
for i in range(128):
    a, b = rng.sample(keys, 2); empty = i % 2 == 0
    body = ' ' if empty else 'old=1'
    path_a, path_b = ['v', 'nested', a], ['v', 'nested', b]
    requests = [(path_b, '2'), (path_a, 'true')]
    entries = q('nested') + '.' + q(b) + ' = 2, ' + q('nested') + '.' + q(a) + ' = true'
    source = 'v={' + body + '}\nw={old=1}\n'
    expected = 'v={' + entries + ('' if empty else ', ') + body + '}\nw={"new" = 3, old=1}\n'
    requests.append((['w', 'new'], '3'))
    add(10, source, requests, expected)
for source, expected in [
    ('v={old=1,}', 'v={"x" = 2, old=1,}'),
    ('v={#keep\n}', 'v={"x" = 2#keep\n}'),
    ('v={#keep\nold=1,#tail\n}', 'v={"x" = 2, #keep\nold=1,#tail\n}'),
]: add(11, source, [(['v', 'x'], '2')], expected, True)
for source, path, raw in [
    ('v={old=1}', ['v', 'new'], '2 #eats comma'),
    ('v={x=1}', ['v', 'x', 'child'], '2'),
    ('v={x=[{}]}', ['v', 'x', 'child'], '2'),
    ('v={x=1,}', ['v', 'new'], '2'),
    ('v={x=}', ['v', 'new'], '2'),
    ('v={}', ['v', 'new'], '1\nextra=2'),
]: add(10, source, [(path, raw)], None, True)

def run(binary, rows, single):
    frames = []
    for version, source, requests, expected in rows:
        if single:
            path, raw = requests[0]; fields = ['P1' if version == 11 else 'P0', hx(source), hx(raw), *(hx(k) for k in path)]
        else:
            fields = [str(version), hx(source), str(len(requests))]
            for path, raw in requests: fields += ['P', hx(raw), str(len(path)), *(hx(k) for k in path)]
        frames.append('\t'.join(fields) + '\n')
    r = subprocess.run([str(Path(binary).resolve())], input=''.join(frames), text=True, capture_output=True, timeout=180)
    assert r.returncode == 0 and not r.stderr, (r.returncode, r.stderr[:4000])
    lines = r.stdout.splitlines(); assert len(lines) == len(rows)
    for row, line in zip(rows, lines):
        status, output, error = line.split('\t'); output, error = bytes.fromhex(output), bytes.fromhex(error); expected = row[3]
        if expected is None: assert status == 'E' and not output and error, (row, line)
        else: assert status == 'O' and not error and output == expected.encode(), (row, output, error)
run(sys.argv[1], singles, True); run(sys.argv[2], batches, False)
print(f'{len(singles)} inline insertion put + {len(batches)} batch exact/model cases passed')
