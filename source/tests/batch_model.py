#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic snapshot-edit oracle, independent of editor offsets/planning."""
import copy
import json
import random
import subprocess
import sys
import tomllib
from pathlib import Path

if not __debug__:
    raise SystemExit('Do not use -O: assertions are required')

rng = random.Random(20261108)
quote = lambda text: json.dumps(text, ensure_ascii=False).replace("\x7f", "\\u007f")
cases = []

def add(source, edits, expected, protected=(), exact=None, error=None):
    cases.append((source, edits, expected, protected, exact, error))

# All selected paths refer to original, explicitly declared table bodies. Changes
# to independent leaves commute semantically; compare against Python's own tree.
keys = ['plain', 'dot.key', '', '世界', '🦆', 'quote"slash\\', '\x00\x7f']
values = ['0x2A', "'café'", '[1, 2, 3]', "{path='世界/🦆'}", 'true', '"a\\nb"']
for index in range(640):
    eol = rng.choice(['\n', '\r\n'])
    tables = rng.sample(keys, 4)
    lines = [f'# PROTECTED-{index}-lead', 'keep=0x10']
    selections = []
    for n, table in enumerate(tables):
        entries = rng.sample(keys, 4)
        lines += ['[' + quote(table) + ']']
        for j, key in enumerate(entries):
            lines.append(quote(key) + ' = ' + str(n * 10 + j) + f' # PROTECTED-{index}-{n}-{j}')
        selections += [(table, key) for key in entries]
        selections += [(table, 'missing.' + str(n))]
    lines += ['[unrelated]', "text='''[fake.header] # inside value'''", f'# PROTECTED-{index}-tail']
    source = eol.join(lines) + (eol if index % 3 else '')
    expected = copy.deepcopy(tomllib.loads(source))
    rng.shuffle(selections)
    edits = []
    for table, key in selections[:rng.randint(1, 16)]:
        op = rng.choice(['P', 'R'])
        value = rng.choice(values) if op == 'P' else ''
        edits.append((op, [table, key], value))
        if op == 'P':
            expected[table][key] = tomllib.loads('v=' + value)['v']
        else:
            expected[table].pop(key, None)
    protected = [line[line.index('# PROTECTED-'):] for line in lines if '# PROTECTED-' in line]
    add(source, edits, expected, protected)

# Different missing prefixes share one insertion anchor, without creating a
# sequential dependency. Empty/dotted/escaped names must remain decoded keys.
for index in range(96):
    root, a, b = rng.sample(keys, 3)
    eol = '\r\n' if index % 2 else '\n'
    source = '# PROTECTED-shared' + eol
    edits = [('P', [root, a], '1'), ('P', [root, b], '2')]
    exact = quote(root) + '.' + quote(a) + ' = 1' + eol + quote(root) + '.' + quote(b) + ' = 2' + eol + source
    # JSON's U+007F literal needs TOML's escape; editor emits lowercase escape.
    exact = exact.replace('\x7f', '\\u007f')
    add(source, edits, {root: {a: 1, b: 2}}, ['# PROTECTED-shared'], exact)

# Subtree spans can be interleaved with independent values and repeated AoTs.
for index in range(64):
    source = '# PROTECTED\n[a.b]\nx=1\n[z]\ny=2 # PROTECTED-z\n[a.c]\nx=3\n[[rows]]\nv=1\n[[rows]]\nv=2\n'
    edits = [('R', ['a'], ''), ('P', ['z', 'y'], str(index)), ('R', ['rows'], ''), ('P', ['fresh'], 'false')]
    add(source, edits, {'z': {'y': index}, 'fresh': False}, ['# PROTECTED', '# PROTECTED-z'])

add('x=1', [], {'x': 1}, exact='x=1')
add('x=1', [('R', ['missing'], '')], {'x': 1}, exact='x=1')
add('', [('P', ['a.b'], '1'), ('P', ['a', 'b'], '2')], {'a.b': 1, 'a': {'b': 2}})
for path, other in [(['a'], ['a']), (['a'], ['a', 'b']), (['a', 'b'], ['a'])]:
    add('x=1', [('P', path, '2'), ('R', other, '')], None, error='overlapping batch paths')
for value in ['[', '1\nextra=2', '# absent', '"\\uD800"', '{x=1,}']:
    add('x=1', [('P', ['x'], '2'), ('P', ['bad'], value)], None, error='batch edit 1:')
add('a={x=1}\nb=2', [('P', ['b'], '3'), ('R', ['a', 'x'], '')], None, error='batch edit 1:')
add('[a]\nb=1', [('P', ['a'], '2')], None, error='directly assigned')
add('a=[', [], None)
add('a=[', [('P', [], '[')], None, error='batch edit 0:')
add('', [('R', [str(i)], '') for i in range(65)], None, error='exceeds 64 edits')

# Hex transport covers invalid UTF-8 without argv or Unicode replacement.
add(b'x=1', [('R', [b'\xff'], b'')], None, error='UTF-8')
add(b'x=1', [('P', [b'x'], b'"\xff"')], None, error='UTF-8')

def hx(value):
    return (value if isinstance(value, bytes) else value.encode()).hex()

frames = []
for source, edits, *_ in cases:
    fields = ['10', hx(source), str(len(edits))]
    for op, path, value in edits:
        fields += [op, hx(value), str(len(path)), *(hx(key) for key in path)]
    frames.append('\t'.join(fields) + '\n')
run = subprocess.run([str(Path(sys.argv[1]).resolve())], input=''.join(frames), text=True,
                     capture_output=True, timeout=180)
if run.returncode:
    sys.stderr.write(run.stderr[:4096])
    run.check_returncode()
lines = run.stdout.splitlines()
assert len(lines) == len(cases), (len(lines), len(cases), run.stderr[:1000])
for index, (case, line) in enumerate(zip(cases, lines)):
    source, edits, expected, protected, exact, error = case
    status, output_hex, error_hex = line.split('\t')
    output, diagnostic = bytes.fromhex(output_hex), bytes.fromhex(error_hex)
    if expected is None:
        assert status == 'E' and not output and diagnostic, (index, case, line)
        if error:
            assert error.encode() in diagnostic, (index, case, diagnostic)
    else:
        assert status == 'O' and not diagnostic, (index, case, diagnostic)
        text = output.decode()
        assert tomllib.loads(text) == expected, (index, case, text)
        for comment in protected:
            assert text.count(comment) == source.count(comment), (index, comment, text)
        if exact is not None:
            assert text == exact, (index, text, exact)
print(f'{len(cases)} atomic batch semantic/preservation/failure cases passed')
