"""Read a user-downloaded public manufacturer sample; never redistribute it.

Compare all complex values and band/ripple results with scikit-rf/NumPy.
This is a data processing reproduction, not a device certification.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
import skrf as rf

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://www.johansontechnology.com/docs/1886/5500BP41A0665_sT2aflU.s2p'
SHA = '404804182b54e3c37d4438b9b685ddb16d264768c8f1368ddd14f494d55310e6'
parser = argparse.ArgumentParser()
parser.add_argument('sample', type=Path)
parser.add_argument('--evidence', type=Path)
args = parser.parse_args()
raw = args.sample.read_bytes()
assert hashlib.sha256(raw).hexdigest() == SHA, 'Different source revision; review it before comparing'
text = raw.decode('ascii')
net = rf.Network(str(args.sample))
host = subprocess.Popen(['node', 'tools/oracle-host.mjs'], cwd=ROOT,
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, encoding='utf-8')


def ask(command, **options):
    host.stdin.write(json.dumps({'text': text, 'options': {'command': command, 'ports': 2, **options}})+'\n')
    host.stdin.flush()
    reply = json.loads(host.stdout.readline())
    assert reply['ok'], reply
    return reply['result']


try:
    dump = ask('dump')
    actual = np.array([[z['re']+1j*z['im'] for z in row] for row in dump['values']]).reshape(-1,2,2)
    np.testing.assert_allclose(actual, net.s, rtol=3e-10, atol=3e-12)
    np.testing.assert_array_equal(dump['frequency_hz'], net.f)
    np.testing.assert_array_equal(dump['reference_ohms'], net.z0[0].real)
    rules = []
    def rule(metric, start, end, inp, out, **bounds):
        rules.append(dict(metric=metric, start_hz=start*1e6, end_hz=end*1e6,
                          input=inp, output=out, **bounds))
    rule('insertion_loss_db', 5170, 5835, 0, 1, maximum=2.5)
    for port in [0, 1]:
        rule('return_loss_db', 5170, 5835, port, port, minimum=9.5)
    for start, end, threshold in [(2400,2500,25), (6095,7125,30), (10340,11670,20)]:
        rule('insertion_loss_db', start, end, 0, 1, minimum=threshold)
    bands = ask('band-check', limits=rules, max_details=10)
    summaries = []
    for specification, result in zip(rules, bands['results'], strict=True):
        selected = np.flatnonzero((net.f >= specification['start_hz']) & (net.f <= specification['end_hz']))
        loss = -net.s_db[:, specification['output'], specification['input']]
        failed = selected[(loss[selected] < specification.get('minimum', -np.inf)) |
                          (loss[selected] > specification.get('maximum', np.inf))]
        assert result['sample_count'] == len(selected) and result['failed_count'] == len(failed)
        assert result['status'] == ('fail' if len(failed) else 'pass')
        for key, operation in [('lowest', np.argmin), ('highest', np.argmax)]:
            point = int(selected[operation(loss[selected])])
            assert result[key]['point'] == point
            np.testing.assert_allclose(result[key]['value'], loss[point], atol=3e-10, rtol=3e-10)
        summaries.append({key: value for key, value in result.items() if key not in ['issues']})
    ripple = ask('ripple-check', start_hz=5170e6, end_hz=5835e6, input=0, output=1, maximum_ripple_db=2.0)
    selected = (net.f >= 5170e6) & (net.f <= 5835e6)
    independent_ripple = float(np.ptp(-net.s_db[selected,1,0]))
    np.testing.assert_allclose(ripple['ripple_db'], independent_ripple, rtol=3e-10, atol=3e-10)
    assert ripple['status'] == ('pass' if independent_ripple <= 2 else 'fail')
    assert not ripple['end_sampled'], '5835 MHz must not be invented as a measured point'
finally:
    host.stdin.close()
    host.wait(timeout=10)

report = {'source': SOURCE, 'sha256': SHA, 'bytes': len(raw),
          'measurement_date_from_header': '2020-02-12',
          'reference_datasheet_revision': 'Rev 2.0, copyright 2025',
          'instrument_port_mapping': {'logical_0': 'instrument port 1', 'logical_1': 'instrument port 4'},
          'points': len(net.f), 'complex_values_compared': int(net.s.size),
          'maximum_complex_error': float(np.max(np.abs(actual-net.s))),
          'reference': {'scikit_rf': rf.__version__, 'numpy': np.__version__},
          'band_results': summaries, 'ripple': ripple, 'independent_checks_passed': True,
          'limits': ['sampled points only; no interpolation or continuous-band proof',
                     '2020 example and 2025 datasheet are different dated artifacts',
                     'does not establish temperature, evaluation-board or production-device compliance',
                     'public sample is not customer adoption; source is not bundled or relicensed']}
if args.evidence:
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
print(json.dumps({key: report[key] for key in ['points', 'complex_values_compared', 'maximum_complex_error', 'independent_checks_passed']}))
print(json.dumps({'band_statuses': [r['status'] for r in summaries], 'ripple_db': ripple['ripple_db'], 'ripple_status': ripple['status']}))
