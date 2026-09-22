"""Independent scikit-rf/NumPy sampled-band reference and real-file CLI checks.

No MoonBit-derived metrics are used as the oracle. Fixtures are synthetic,
written/read by scikit-rf; masks, extrema and limit violations use NumPy.
Run after a release JS build. Only --evidence writes a persistent receipt.
"""
import argparse
import csv
import io
import json
import platform
import subprocess
import tempfile
import time
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
checks = cases = cli_checks = 0
rng = np.random.default_rng(20260923)
metrics = ['reflection_magnitude', 'transmission_magnitude', 'return_loss_db',
           'insertion_loss_db', 'vswr']


def ask(text, limits, reject=False, **options):
    global checks
    request = {'text': text, 'options': {'command': 'band-check', 'limits': limits, **options}}
    host.stdin.write(json.dumps(request) + '\n')
    host.stdin.flush()
    line = host.stdout.readline()
    assert line, 'bridge stopped unexpectedly'
    response = json.loads(line)
    if reject:
        assert not response['ok'], 'invalid request accepted'
        checks += 1
        return
    assert response['ok'], response.get('error')
    return response['result']


def observation(point, freq, values):
    value = float(values[point])
    return {'point': int(point), 'frequency_hz': float(freq[point]),
            'value': value if np.isfinite(value) else None,
            'state': 'undefined' if np.isnan(value) else 'infinite' if np.isinf(value) else 'finite'}


def expected_report(net, limits, budget):
    results = []
    remaining = budget
    # Independent RF properties from scikit-rf, not the MoonBit bridge.
    with np.errstate(divide='ignore', invalid='ignore'):
        mags, db, vswr = net.s_mag, net.s_db, net.s_vswr
    for rule in limits:
        inp, out = rule['input'], rule['output']
        metric = rule['metric']
        values = {
            'reflection_magnitude': mags[:, inp, inp],
            'transmission_magnitude': mags[:, out, inp],
            'return_loss_db': -db[:, inp, inp],
            'insertion_loss_db': -db[:, out, inp],
            # Algebraic negative VSWR from skrf is physically undefined for
            # active reflection in our explicitly documented contract.
            'vswr': np.where(mags[:, inp, inp] > 1, np.nan, vswr[:, inp, inp]),
        }[metric]
        selected = np.flatnonzero((net.f >= rule['start_hz']) & (net.f <= rule['end_hz']))
        lower = rule.get('minimum', -np.inf)
        upper = rule.get('maximum', np.inf)
        failed = selected[(values[selected] < lower) | (values[selected] > upper)]
        undefined = selected[np.isnan(values[selected])]
        valid = selected[~np.isnan(values[selected])]
        problem = np.union1d(failed, undefined)
        retained = problem[:remaining]
        remaining -= len(retained)
        covered = bool(net.f[0] <= rule['start_hz'] and net.f[-1] >= rule['end_hz'])
        status = 'fail' if len(failed) else 'inconclusive' if (
            not covered or not len(selected) or len(undefined)) else 'pass'
        result = {**rule, 'minimum': rule.get('minimum'), 'maximum': rule.get('maximum'),
                  'status': status, 'range_covered': covered,
                  'start_sampled': bool(np.any(net.f == rule['start_hz'])),
                  'end_sampled': bool(np.any(net.f == rule['end_hz'])),
                  'sample_count': len(selected), 'failed_count': len(failed),
                  'undefined_count': len(undefined),
                  'lowest': observation(valid[np.argmin(values[valid])], net.f, values) if len(valid) else None,
                  'highest': observation(valid[np.argmax(values[valid])], net.f, values) if len(valid) else None,
                  'issues': [{'observation': observation(p, net.f, values),
                              'reason': 'undefined' if np.isnan(values[p]) else
                              'below_minimum' if values[p] < lower else 'above_maximum'} for p in retained],
                  'issues_truncated': bool(len(retained) < len(problem))}
        results.append(result)
    statuses = [r['status'] for r in results]
    return {'scope': 'sampled_points_only',
            'status': 'fail' if 'fail' in statuses else 'inconclusive' if 'inconclusive' in statuses else 'pass',
            'reference_ohms': net.z0[0].real.tolist(), 'max_details': budget, 'results': results}


def compare(actual, expected, label='report'):
    # Recursive TYPE-aware comparison prevents [number] from broadcasting as
    # number and rejects omitted nulls, nonfinite JSON, or unexpected keys.
    if isinstance(expected, dict):
        assert isinstance(actual, dict) and actual.keys() == expected.keys(), label
        for key in expected:
            compare(actual[key], expected[key], label + '.' + key)
    elif isinstance(expected, list):
        assert isinstance(actual, list) and len(actual) == len(expected), label
        for i, (a, e) in enumerate(zip(actual, expected)):
            compare(a, e, f'{label}[{i}]')
    elif isinstance(expected, (float, np.floating)):
        assert type(actual) in (float, int) and np.isfinite(actual), (label, actual)
        np.testing.assert_allclose(actual, expected, rtol=3e-10, atol=3e-10, err_msg=label)
    else:
        assert type(actual) is type(expected) and actual == expected, (label, actual, expected)


def run_case(net, limits, budget=256, version='2.1', form='ri', parameter='S'):
    global checks, cases
    text = net.write_touchstone(return_string=True, version=version, form=form, parameter=parameter)
    stream = io.StringIO(text)
    stream.name = f'synthetic.s{net.nports}p'
    reread = rf.Network(stream)
    result = ask(text, limits, max_details=budget, ports=net.nports)
    compare(result, expected_report(reread, limits, budget))
    cases += 1
    checks += 1
    return text, result


def rule(metric, start, end, inp=0, out=0, **limits):
    return dict(metric=metric, start_hz=float(start), end_hz=float(end), input=inp, output=out, **limits)


def cli(command, source, options, exit_code, output=None):
    global cli_checks
    argv = ['node', 'tools/touchstone.mjs', command, str(source),
            options if isinstance(options, str) else json.dumps(options)]
    if output is not None:
        argv.append(str(output))
    result = subprocess.run(argv, cwd=ROOT, text=True, capture_output=True, timeout=15)
    assert result.returncode == exit_code, (result.returncode, exit_code, result.stderr)
    cli_checks += 1
    return result


started = time.perf_counter()
try:
    for n in [1, 2, 4, 8]:
        for trial in range(3):
            f = np.cumsum(rng.integers(1, 10, size=19)).astype(float) * 1e6
            s = (rng.normal(size=(len(f), n, n)) + 1j*rng.normal(size=(len(f), n, n))) / (2*n)
            net = rf.Network(f=f, s=s, z0=np.linspace(35, 90, n), name='band_oracle')
            limits = []
            for metric in metrics:
                for lo, hi in [(f[0], f[-1]), (f[3], f[9]), (f[5]+1, f[6]-1),
                               (0, f[-1]+1), (f[7], f[7]), (f[1]+1, f[-2]-1)]:
                    bounds = {'minimum': 0.1, 'maximum': 0.4} if 'magnitude' in metric else (
                        {'maximum': 2.5} if metric == 'vswr' else {'minimum': 4, 'maximum': 25})
                    limits.append(rule(metric, lo, hi, inp=trial % n, out=(trial+1) % n, **bounds))
            for budget in [0, 7, 100000]:
                run_case(net, limits, budget=budget)
            # Conversions and alternate text representations use independently
            # re-read data, so this is not just own-parser roundtripping.
            for kind in ['Z', 'Y'] + (['H', 'G'] if n == 2 else []):
                run_case(net, limits, parameter=kind)
            for form in ['ma', 'db']:
                run_case(net, limits, form=form)
            equal = net.copy()
            equal.renormalize(50)
            run_case(equal, limits, version='1.0')

    f = np.arange(1, 7, dtype=float)
    s = np.zeros((6, 2, 2), complex)
    s[:, 0, 0] = [0, .5, 1, 1.5, .5, 0]
    s[:, 1, 0] = [.5, 0, 1.25, 0, .5, .25]
    s[:, 0, 1] = .125
    special = rf.Network(f=f, s=s, z0=[50, 75], name='special')
    limits = [rule('return_loss_db', 1, 1, minimum=1000),
              rule('return_loss_db', 1, 6, maximum=1000),
              rule('vswr', 1, 6, maximum=3),
              rule('vswr', 4, 4, minimum=0),
              rule('insertion_loss_db', 1, 6, out=1, minimum=0),
              rule('transmission_magnitude', 2, 5, out=1, minimum=0, maximum=.5)]
    text, _ = run_case(special, limits, budget=3)
    _, full = run_case(special, limits, budget=256)
    minimal = rule('vswr', 1, 6, maximum=3)
    for bad in [[], [1], [dict(minimal, metric='typo')],
                [dict(minimal, start_hz=-1)], [dict(minimal, end_hz=0)],
                [dict(minimal, input=.5)], [dict(minimal, output=2147483648)],
                [dict(minimal, input=2)], [dict(minimal, maximum=None)],
                [dict(minimal, minimum=5)], [dict(minimal, maximum='3')],
                [dict(minimal, maximim=4)], [rule('vswr', 1, 6)], [minimal]*257]:
        ask(text, bad, reject=True)
    for budget in [-1, .5, 100001, 2147483648, None]:
        ask(text, [minimal], max_details=budget, reject=True)
    ask(text, [minimal], max_detials=5, reject=True)

    with tempfile.TemporaryDirectory(prefix='moon-touchstone-bands-') as scratch:
        scratch = Path(scratch)
        source = scratch/'network.ts'
        source.write_text(text, encoding='ascii')
        options = {'limits': limits, 'max_details': 256}
        config = scratch/'options.json'
        config.write_text(json.dumps(options), encoding='ascii')
        compare(json.loads(cli('band-check', source, '@'+str(config), 3).stdout), full)
        rows = list(csv.DictReader(io.StringIO(cli('band-csv', source, options, 3).stdout)))
        expected = [(i, result['metric'], issue) for i, result in enumerate(full['results']) for issue in result['issues']]
        assert len(rows) == len(expected)
        for row, (i, metric, issue) in zip(rows, expected):
            obs = issue['observation']
            assert int(row['rule']) == i and row['metric'] == metric
            assert int(row['point']) == obs['point'] and float(row['frequency_hz']) == obs['frequency_hz']
            assert row['reason'] == issue['reason'] and row['state'] == obs['state']
            assert (not row['value']) if obs['value'] is None else np.isclose(float(row['value']), obs['value'])
        checks += 1
        passed = {'limits': [rule('transmission_magnitude', 1, 6, inp=1, out=0, maximum=.125)]}
        cli('band-check', source, passed, 0)
        cli('band-csv', source, passed, 0)
        incomplete = {'limits': [rule('vswr', 1.2, 1.8, maximum=3)]}
        cli('band-check', source, incomplete, 4)
        cli('band-csv', source, incomplete, 4)
        out = scratch/'report.json'
        cli('band-check', source, options, 3, out)
        before = out.read_bytes()
        cli('band-check', source, passed, 2, out)
        assert out.read_bytes() == before
        cli('band-check', source, options, 2, source)
        cli('band-check', source, {'limits': [dict(minimal, input=.1)]}, 2)
        for command, opts in [('metrics', {'input': .1, 'output': 0}),
                              ('delay', {'input': 0, 'output': .1}),
                              ('select', {'selection': [0.1]}),
                              ('inspect', {'ports': 2.1})]:
            cli(command, source, opts, 2)
        cli('band-check', ROOT/'examples/attenuator.s2p', '@examples/band-limits.json', 0)
        cli('band-check', source, '@'+str(scratch/'missing.json'), 2)
        config.write_bytes(b' '*1_000_001)
        cli('band-check', source, '@'+str(config), 2)

    measurements = []
    for points in [1000, 10000]:
        net = rf.Network(f=np.arange(points, dtype=float), s=np.full((points, 2, 2), .1, complex), z0=50, name='load')
        source = net.write_touchstone(return_string=True, version='2.1', form='ri')
        load_rules = [rule(m, 0, points-1, out=1, maximum=0) for m in metrics]
        then = time.perf_counter()
        result = ask(source, load_rules, max_details=8)
        elapsed = time.perf_counter()-then
        compare(result, expected_report(net, load_rules, 8))
        measurements.append({'points': points, 'rules': 5, 'details': 8,
                             'roundtrip_seconds': elapsed})
        checks += 1
    ask(source, [rule('vswr', 0, 10000, maximum=2)]*201, reject=True)
    receipt = {'status': 'passed', 'python': platform.python_version(), 'numpy': np.__version__,
               'scikit_rf': rf.__version__, 'matrix_cases': cases, 'checks': checks,
               'cli_checks': cli_checks, 'seconds': time.perf_counter()-started,
               'measurements': measurements,
               'scope': 'Synthetic sampled-frequency checks; not continuous band or physical certification.'}
    if args.evidence:
        args.evidence.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(receipt))
finally:
    host.stdin.close()
    try:
        host.wait(timeout=10)
    except subprocess.TimeoutExpired:
        host.kill()
        host.wait()
