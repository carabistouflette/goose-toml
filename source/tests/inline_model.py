#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent inline replacement model: exact constructed bytes + tomllib tree."""
import json
import math
from pathlib import Path
import random
import struct
import subprocess
import sys
import tomllib

if not __debug__:
    raise SystemExit('Do not use -O: assertions are required')
rng = random.Random(20261109)
q = lambda text: json.dumps(text, ensure_ascii=False).replace('\x7f', '\\u007f')
keys = ['', 'plain', 'a.b', '世界', '🦆', 'quote"slash\\', '\x00\x7f', '\n\t']
old_values = ['0x10', 'true', "'old'", '[1, 2]', "{nested='old'}", "'''line\n], { = not syntax\n'''", '1979-05-27', '-0.0']
new_values = ['0x2A', 'false', "'世界'", '[3,4]', "{k='new'}", "'''new\ntext'''", '[\n1,# comment\n2\n]', '1979-05-27 07:32:00Z', '0.0']


def same(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in b)
    if isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(b, float):
        return math.isnan(a) if math.isnan(b) else struct.pack('>d', a) == struct.pack('>d', b)
    return a == b


assert not same(True, 1) and not same(-0.0, 0.0)
cases = []
for index in range(640):
    owner, outer, leaf, sibling = rng.sample(keys, 4)
    old, new = rng.choice(old_values), rng.choice(new_values)
    style = index % 8
    lead = '# protected\r\nprior=[{same=1},2]\r\n' if index % 2 else '# protected\nprior=1\n'
    tail = " # trailing\n[unrelated]\ntext='''[fake], { path=1 }'''\n"
    if style == 0:
        prefix = lead + q(owner) + ' = { ' + q(leaf) + ' = '
        suffix = ', ' + q(sibling) + ' = 1 }' + tail
        path = [owner, leaf]
    elif style in (1, 7):
        prefix = lead + q(owner) + ' = { ' + q(outer) + ' = {' + q(leaf) + '='
        suffix = ', ' + q(sibling) + "=[{text='}, ='},2]}, outside=1}" + tail
        path = [owner, outer, leaf]
    elif style == 2:
        prefix = lead + q(owner) + ' = { ' + q(outer) + '.' + q(leaf) + ' = '
        suffix = ', ' + q(outer) + '.' + q(sibling) + '=1 }' + tail
        path = [owner, outer, leaf]
    elif style == 3:
        prefix = lead + '[context]\n' + q(owner) + '={' + q(leaf) + '='
        suffix = ', ' + q(sibling) + '=1}' + tail
        path = ['context', owner, leaf]
    elif style == 4:
        prefix = lead + q(owner) + '={before=[{a=1},2], inner={' + q(leaf) + '='
        suffix = ', ' + q(sibling) + '=1},after="}, ="}' + tail
        path = [owner, 'inner', leaf]
    elif style == 5:
        prefix = lead + '[context.child]\nz=3\n[context]\n' + q(owner) + '={' + q(leaf) + '='
        suffix = ', ' + q(sibling) + '=1}' + tail
        path = ['context', owner, leaf]
    else:
        prefix = lead + 'context.' + q(owner) + '={' + q(leaf) + '='
        suffix = ', ' + q(sibling) + '=1}' + tail
        path = ['context', owner, leaf]
    source, expected = prefix + old + suffix, prefix + new + suffix
    original = tomllib.loads(source)
    model = tomllib.loads(expected)
    selected = original
    for key in path[:-1]:
        selected = selected[key]
    selected[path[-1]] = tomllib.loads('v=' + new)['v']
    assert same(original, model)
    cases.append((10, source, path, new, expected))
cases += [
    (10, 'v={x=1}', ['v', 'absent'], '2', 'v={\"absent\" = 2, x=1}'),
    (11, 'v={\r\n# keep\r\n x={a=1,}, # after\r\n y=2,\r\n}', ['v', 'x', 'a'], '3', 'v={\r\n# keep\r\n x={a=3,}, # after\r\n y=2,\r\n}'),
    (11, 'v={"\\x78"=1,}', ['v', 'x'], '"\\e"', 'v={"\\x78"="\\e",}'),
    (11, 'v={x=1,y=2}', ['v', 'x'], '2 # new\n', 'v={x=2 # new\n,y=2}'),
]
for source, path, value in [
    ('v={a.b=1,a.c=2}', ['v', 'a'], '2'),
    ('v={x=[{a=1}]}', ['v', 'x', 'a'], '2'),
    ('v={x=1}', ['v', 'x'], '2 # eats closing brace'),
    ('v={x=1}', ['v', 'x'], '1\nextra=2'),
    ('v={x=1,y=}', ['v', 'x'], '2'),
    ('v={x=1,}', ['v', 'x'], '2'),
]:
    cases.append((10, source, path, value, None))
hx = lambda text: text.encode().hex()
single_frames = ['\t'.join(['P1' if version == 11 else 'P0', hx(source), hx(value), *(hx(k) for k in path)]) + '\n'
                 for version, source, path, value, _ in cases]
batch_frames = ['\t'.join([str(version), hx(source), '1', 'P', hx(value), str(len(path)), *(hx(k) for k in path)]) + '\n'
                for version, source, path, value, _ in cases]
# Siblings share one owner; another owner and ordinary span exercise caching
# and source-order rendering independent of request order.
for index in range(128):
    a, b = rng.sample(keys, 2)
    source = 'v={' + q(a) + '=1,' + q(b) + "='old'}\nw={x=true}\nplain=1 # keep\n"
    expected = 'v={' + q(a) + '=2,' + q(b) + "='new'}\nw={x=false}\nplain=3 # keep\n"
    requests = [(['w', 'x'], 'false'), (['v', b], "'new'"), (['plain'], '3'), (['v', a], '2')]
    fields = ['10', hx(source), str(len(requests))]
    for path, value in requests:
        fields += ['P', hx(value), str(len(path)), *(hx(k) for k in path)]
    batch_frames.append('\t'.join(fields) + '\n')
    cases.append((10, source, [], '', expected))


def run(binary, frames, selected):
    result = subprocess.run([str(Path(binary).resolve())], input=''.join(frames), text=True,
                            capture_output=True, timeout=180)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr[:4096])
    lines = result.stdout.splitlines()
    assert len(lines) == len(selected), (len(lines), len(selected))
    for index, (line, case) in enumerate(zip(lines, selected)):
        version, source, path, value, expected = case
        status, output, error = line.split('\t')
        output, error = bytes.fromhex(output), bytes.fromhex(error)
        if expected is None:
            assert status == 'E' and not output and error, (index, case, line)
        else:
            assert status == 'O' and not error and output == expected.encode(), (index, case, output, error)
            if version == 10:
                assert same(tomllib.loads(output.decode()), tomllib.loads(expected))


run(sys.argv[1], single_frames, cases[:len(single_frames)])
run(sys.argv[2], batch_frames, cases)
print(f'{len(single_frames)} inline put + {len(batch_frames)} inline batch exact/model cases passed')
