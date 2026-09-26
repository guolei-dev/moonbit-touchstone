"""Independent NumPy/scikit-rf ripple contract checks; no network required."""
import argparse
import io
import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import skrf as rf

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--evidence', type=Path)
args = parser.parse_args()
host = subprocess.Popen(['node', 'tools/oracle-host.mjs'], cwd=ROOT,
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, encoding='utf-8')
cases = rejects = cli_checks = 0


def ask(text, **options):
    host.stdin.write(json.dumps({'text': text, 'options': {
        'command': 'ripple-check', 'ports': 2, **options}}) + '\n')
    host.stdin.flush()
    line = host.stdout.readline()
    assert line, 'MoonBit bridge stopped'
    return json.loads(line)


def check(net, lo, hi, bound, inp=0, out=1, form='ri'):
    global cases
    text = net.write_touchstone(return_string=True, version='2.1', form=form)
    stream = io.StringIO(text)
    stream.name = 'reference.s2p'
    net = rf.Network(stream)
    result = ask(text, start_hz=lo, end_hz=hi, input=inp,
                 output=out, maximum_ripple_db=bound)
    assert result['ok'], result
    actual = result['result']
    selected = np.flatnonzero((net.f >= lo) & (net.f <= hi))
    with np.errstate(divide='ignore', invalid='ignore'):
        loss = -net.s_db[:, out, inp]
        delta = float(np.ptp(loss[selected])) if len(selected) else float('nan')
    state = 'undefined' if np.isnan(delta) else 'infinite' if np.isinf(delta) else 'finite'
    covered = bool(net.f[0] <= lo and net.f[-1] >= hi)
    status = 'fail' if delta > bound else 'inconclusive' if (
        state == 'undefined' or len(selected) < 2 or not covered) else 'pass'
    assert actual['status'] == status and actual['ripple_state'] == state, actual
    assert actual['sample_count'] == len(selected)
    assert actual['range_covered'] is covered
    assert actual['start_sampled'] is bool(np.any(net.f == lo))
    assert actual['end_sampled'] is bool(np.any(net.f == hi))
    if np.isfinite(delta):
        np.testing.assert_allclose(actual['ripple_db'], delta, rtol=3e-10, atol=3e-10)
    else:
        assert actual['ripple_db'] is None
    for key, operation in [('lowest_loss', np.argmin), ('highest_loss', np.argmax)]:
        if not len(selected):
            assert actual[key] is None
            continue
        point = int(selected[operation(loss[selected])])
        witness = actual[key]
        assert witness['point'] == point and witness['frequency_hz'] == net.f[point]
        if np.isfinite(loss[point]):
            np.testing.assert_allclose(witness['value'], loss[point], rtol=3e-10, atol=3e-10)
        else:
            assert witness['value'] is None and witness['state'] == 'infinite'
    cases += 1
    return text


try:
    rng = np.random.default_rng(20260927)
    for trial in range(8):
        f = np.cumsum(rng.integers(10, 50, 25)).astype(float) * 1e6
        s = (rng.normal(size=(25, 2, 2)) + 1j*rng.normal(size=(25, 2, 2))) / 4
        net = rf.Network(f=f, s=s, z0=50, name='ripple_reference')
        for lo, hi in [(f[0], f[-1]), (f[3]+1, f[19]-1), (f[6], f[6]),
                       (f[6]+1, f[7]-1), (0, f[-1]+1)]:
            for inp, out in [(0, 1), (1, 0)]:
                for bound in [1.0, 100.0]:
                    check(net, float(lo), float(hi), bound, inp, out,
                          form=['ri', 'ma', 'db'][trial % 3])
    for amplitudes in [[0, 0, 0], [0, .5, 0], [.5, .25, .5], [.5, .5, .5]]:
        s = np.zeros((3, 2, 2), dtype=complex)
        s[:, 1, 0] = amplitudes
        net = rf.Network(f=[1e6, 2e6, 3e6], s=s, z0=50, name='ripple_reference')
        for bound in [0.0, 6.0, 100.0]:
            check(net, 1e6, 3e6, bound)
    valid = dict(start_hz=1e6, end_hz=3e6, input=0, output=1, maximum_ripple_db=1)
    text = check(net, 1e6, 3e6, 1.0)
    for change in [{'maximum_ripple_db': -1}, {'maximum_ripple_db': None},
                   {'maximum_ripple_db': '1'}, {'input': .5}, {'input': True},
                   {'output': 2}, {'end_hz': 0}, {'max_ripple_db': 1}]:
        assert not ask(text, **(valid | change))['ok'], change
        rejects += 1
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / 'sample.s2p'
        source.write_text(text, encoding='ascii')
        for options, expected in [(valid, 0), (valid | {'end_hz': 4e6}, 4),
                                  (valid | {'input': .5}, 2)]:
            result = subprocess.run(['node', 'tools/touchstone.mjs', 'ripple-check',
                                     str(source), json.dumps(options)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=15)
            assert result.returncode == expected, result.stderr
            cli_checks += 1
        s[:, 1, 0] = [.5, .25, .5]
        net.s = s
        source.write_text(net.write_touchstone(return_string=True, version='2.1'), encoding='ascii')
        result = subprocess.run(['node', 'tools/touchstone.mjs', 'ripple-check',
                                 str(source), json.dumps(valid)], cwd=ROOT,
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == 3 and json.loads(result.stdout)['status'] == 'fail'
        cli_checks += 1
finally:
    host.stdin.close()
    host.wait(timeout=10)

report = {'reference': 'NumPy/scikit-rf independent peak-to-peak S dB',
          'numpy': np.__version__, 'scikit_rf': rf.__version__,
          'synthetic_cases': cases, 'rejected_options': rejects,
          'cli_exit_checks': cli_checks, 'passed': True}
if args.evidence:
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
print(json.dumps(report))
