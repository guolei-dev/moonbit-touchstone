"""Independent scikit-rf/NumPy checks; run after release bridge build.

Generated fixtures stay in a temporary directory. Only the explicit evidence
path is written. No downloaded circuits, credentials or network access needed.
"""
import argparse
import hashlib
import io
import json
import platform
import subprocess
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
checks = 0
cases = 0
maximum_absolute_error = 0.0
start = time.perf_counter()
rng = np.random.default_rng(20260922)


def ask(text, command='dump', ports=None, reject=False, **options):
    global checks
    left = options.pop('left', '')
    right = options.pop('right', '')
    options['command'] = command
    if ports is not None:
        options['ports'] = ports
    host.stdin.write(json.dumps(dict(text=text, options=options, left=left, right=right))+'\n')
    host.stdin.flush()
    line = host.stdout.readline()
    assert line, 'reference bridge stopped unexpectedly'
    response = json.loads(line)
    if reject:
        assert not response['ok'], f'accepted invalid input for {command}'
        checks += 1
        return
    assert response['ok'], response.get('error')
    return response['result']


def close(actual, expected, label, rtol=3e-8, atol=3e-10):
    global checks, maximum_absolute_error
    a = np.asarray(actual)
    e = np.asarray(expected)
    assert a.shape == e.shape, f'{label}: {a.shape} != {e.shape}'
    np.testing.assert_allclose(a, e, rtol=rtol, atol=atol, err_msg=label)
    maximum_absolute_error = max(maximum_absolute_error, float(np.max(np.abs(a-e), initial=0)))
    checks += 1


def values(dump):
    n = dump['ports']
    return np.array([[z['re']+1j*z['im'] for z in row] for row in dump['values']]).reshape(-1,n,n)


def write(net, version='2.1', form='ri', parameter='S'):
    return net.write_touchstone(return_string=True, version=version, form=form, parameter=parameter)


def read(text):
    stream = io.StringIO(text)
    stream.name = 'reference.ts'
    return rf.Network(stream)


def transformed(text, command, **kwargs):
    result = ask(text, command, **kwargs)['text']
    return result, ask(result)


try:
    # Files genuinely written by scikit-rf, and MoonBit output read independently.
    for n in [1,2,3,4,8]:
        for trial in range(3):
            f = np.array([1e6,1.7e6,2.5e6,4e6,6e6])
            s = (rng.normal(size=(len(f),n,n))+1j*rng.normal(size=(len(f),n,n)))/(5*n)
            refs = np.linspace(35,90,n)
            net = rf.Network(name='oracle',frequency=rf.Frequency.from_f(f,unit='Hz'),
                             s=s,z0=np.tile(refs,(len(f),1)))
            for version in ['1.0','2.0','2.1']:
                source = net.copy()
                if version == '1.0':
                    source.renormalize(50)
                for form in ['ri','ma','db']:
                    text = write(source,version,form)
                    dump = ask(text,ports=n)
                    close(values(dump),source.s,f'parse {n}/{version}/{form}')
                    close(dump['reference_ohms'],source.z0[0].real,'references')
                    close(dump['frequency_hz'],source.f,'frequency')
                    normalized = ask(text,'normalize',ports=n)['text']
                    reread = read(normalized)
                    close(reread.s,source.s,'MoonBit write/scikit-rf read')
                    close(reread.z0,source.z0,'write reference')
                    cases += 1
            text = write(net)
            for kind in ['S','Y','Z']+(['H','G'] if n==2 else []):
                out,dump = transformed(text,'convert',parameter=kind)
                close(values(dump),getattr(net,kind.lower()),'convert '+kind)
                close(read(out).s,net.s,'independent read converted '+kind)
                # Independently written legacy normalized physical Y/Z/H/G.
                if kind!='S':
                    equal = net.copy(); equal.renormalize(50)
                    legacy = write(equal,'1.0','ri',kind)
                    close(values(ask(legacy,ports=n)),getattr(equal,kind.lower()),'legacy physical '+kind)
                    own = ask(out,'legacy')['text']
                    close(values(ask(own,ports=n)),getattr(net,kind.lower()),'multi-reference legacy '+kind)
                cases += 1
            refs2 = np.linspace(60,100,n)
            expected = net.copy(); expected.renormalize(np.tile(refs2,(len(f),1)))
            _,dump = transformed(text,'renormalize',reference_ohms=refs2.tolist())
            close(values(dump),expected.s,'renormalize')
            selection = list(range(n-1,-1,-2))
            _,dump = transformed(text,'select',selection=selection)
            close(values(dump),net.subnetwork(selection).s,'matched select')
            queries = [f[0],1.3e6,2e6,f[-1]]
            _,dump = transformed(text,'interpolate',frequency_hz=queries)
            close(values(dump),net.interpolate(queries).s,'interpolate')
            delay = ask(text,'delay',input=0,output=n-1)
            close(delay,net.group_delay[:,n-1,0].real,'group delay',atol=1e-18)
            diag = ask(text,'diagnostics')
            for p,item in enumerate(diag):
                eig = np.linalg.eigvalsh(np.eye(n)-net.s[p].conj().T@net.s[p]).min()
                wanted = 'passive' if eig>1e-9 else ('active' if eig<=-1e-9 else 'boundary')
                assert item['passivity']==wanted,(item,eig)
                close(item['reciprocity_error'],np.abs(net.s[p]-net.s[p].T).max(),'reciprocity')
                checks += 1
            metrics = ask(text,'metrics',input=0,output=n-1)
            close([m['insertion_loss_db'] for m in metrics],-net.s_db[:,n-1,0],'insertion loss')
            close([m['return_loss_db'] for m in metrics],-net.s_db[:,0,0],'return loss')
            close([m['vswr'] for m in metrics],net.s_vswr[:,0,0],'vswr')
            cases += 7
            if n==2:
                # Nonreciprocal complex fixtures exercise all chain terms.
                other = net.copy(); other.s = s*.7; other.z0 = net.z0[:,::-1]
                joined = net ** other
                out,dump=transformed(text,'cascade',right=write(other))
                close(values(dump),joined.s,'cascade')
                measured = net ** other ** net
                _,dump=transformed(write(measured),'deembed',left=text,right=text)
                close(values(dump),other.s,'deembed')
                cases += 2

    # Spectral counterexamples and exact lossless networks, including complex S.
    for scale in [0.1,0.8,1.0,1.2,2.0]:
        for n in [1,2,4,8]:
            a=rng.normal(size=(n,n))+1j*rng.normal(size=(n,n))
            u=np.linalg.qr(a)[0]
            s=np.stack([scale*u,scale*a/np.linalg.norm(a,2)])
            net=rf.Network(name='passivity',f=[1,2],s=s,z0=50)
            result=ask(write(net),'diagnostics')
            for item in result:
                assert item['passivity']==('passive' if scale<1 else 'active' if scale>1 else 'boundary')
                checks+=1
            cases+=1

    noise=rf.Network(name='noise',f=[1e9,2e9,3e9],s=np.array([[[.1,.2],[.6,.1]]]*3),z0=50)
    noise.set_noise_a(noise_freq=noise.frequency,nfmin_db=1.3,gamma_opt=.2+.1j,rn=7)
    for version in ['1.0','2.0','2.1']:
        text=write(noise,version)
        report=ask(text,'inspect',ports=2)
        close([x['resistance_ohms'] for x in report['noise']],noise.rn,'noise R')
        close([x['minimum_figure_db'] for x in report['noise']],noise.nfmin_db,'noise figure')
        close([x['gamma_opt']['re']+1j*x['gamma_opt']['im'] for x in report['noise']],noise.g_opt,'noise optimum')
        normalized=ask(text,'normalize',ports=2)['text']
        other=read(normalized)
        close(other.rn,noise.rn,'noise writer R')
        close(other.nfmin_db,noise.nfmin_db,'noise writer figure')
        ask(text,'convert',ports=2,parameter='Z',reject=True)
        cases+=1

    # Independent reader checks for symmetric (not Hermitian) packed matrices.
    for n in [2,3,4,5]:
        for layout in ['Upper','Lower']:
            a=rng.normal(size=(n,n))+1j*rng.normal(size=(n,n))
            a=(a+a.T)/10
            order='[Two-Port Data Order] 12_21\n' if n==2 else ''
            tokens=[]
            for i in range(n):
                for j in range(n):
                    if (layout=='Upper' and j>=i) or (layout=='Lower' and j<=i):
                        tokens.extend([str(a[i,j].real),str(a[i,j].imag)])
            text=(f'[Version] 2.1\n# Hz S RI R 50\n[Number of Ports] {n}\n'+order+
                  f'[Number of Frequencies] 1\n[Matrix Format] {layout}\n[Network Data]\n1 '+
                  ' '.join(tokens)+'\n[End]\n')
            close(values(ask(text)),read(text).s,'packed layout independent read')
            close(read(ask(text,'normalize')['text']).s,np.array([a]),'packed writer')
            cases+=1
    mixed=('[Version] 2.1\n# Hz S RI R 50\n[Number of Ports] 2\n'+
           '[Two-Port Data Order] 12_21\n[Number of Frequencies] 1\n'+
           '[Reference] 50 50\n[Mixed-Mode Order] D1,2 C1,2\n'+
           '[Network Data]\n1 .1 .2 .3 .4 .5 .6 .7 .8\n[End]\n')
    canonical=ask(mixed,'normalize')['text']
    close(read(canonical).s,read(mixed).s,'mixed raw matrices preserved')
    close(read(canonical).z0,read(mixed).z0,'mixed effective references preserved')
    assert ask(canonical,'inspect')['mixed_mode_order']==['D1,2','C1,2']
    checks+=1
    ask(mixed,'diagnostics',reject=True)
    cases+=1

    # Bounds and syntax failures are deterministic, not delay-based tests.
    valid=(ROOT/'examples/attenuator.s2p').read_text(encoding='ascii')
    invalid=[valid+'\0',valid.replace('# MHz','# parsec'),valid.replace('0.4045084971874737','NaN',1),
             valid.replace('200 0 0','100 0 0'),valid[:-4],
             '[Version] 2.1\n# Hz S RI R 50\n[Number of Ports] 9999999999\n[End]\n',
             '#'+(' '*262145)+'\n', '\n'*1000000,
             mixed.replace('[Reference] 50 50','[Reference] '+('50 '*1500))]
    for text in invalid:
        ask(text,ports=2,reject=True)
    # Seeded single-token mutations have an externally known violated invariant.
    for i in range(200):
        bad=valid.replace('100 0 0',f'100 {rng.choice(["NaN","Infinity","1e999","x","1_0"])} 0',1)
        ask(bad,ports=2,reject=True)
    cases+=len(invalid)+200

    # Bounded workload, no throughput promises or comparison to another language.
    samples=2000
    f=np.arange(1,samples+1,dtype=float)*1e6
    bulk=rf.Network(name='benchmark',frequency=rf.Frequency.from_f(f,unit='Hz'),
                    s=np.tile(np.array([[.1,.3],[.4,.2]],complex),(samples,1,1)),z0=50)
    bulktext=write(bulk)
    begin=time.perf_counter()
    result=ask(bulktext,'diagnostics')
    elapsed=time.perf_counter()-begin
    assert len(result)==samples
    checks+=1
    tracked={}
    for file in sorted(ROOT.rglob('*')):
        if any(p in {'_build','.git','.mooncakes','work','__pycache__','evidence'} for p in file.relative_to(ROOT).parts):
            continue
        if file.is_file() and (file.suffix in {'.mbt','.mbti','.mjs','.py','.pkg','.mod'}):
            tracked[file.relative_to(ROOT).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
    evidence=dict(status='passed',cases=cases,checks=checks,seed=20260922,
                  maximum_absolute_error=maximum_absolute_error,
                  elapsed_seconds=time.perf_counter()-start,
                  benchmark=dict(points=samples,ports=2,operation='parse + full diagnostics + JSON IPC',seconds=elapsed),
                  versions=dict(python=platform.python_version(),numpy=np.__version__,scikit_rf=rf.__version__,
                                node=subprocess.check_output(['node','--version'],text=True).strip(),platform=platform.platform()),
                  source_sha256=tracked,
                  limits=['positive real references','well-conditioned randomized matrices',
                          'pointwise spectral diagnostics, not broadband causality',
                          'mixed-mode descriptors preserved, no mixed-mode conversion'])
    if args.evidence:
        args.evidence.parent.mkdir(parents=True,exist_ok=True)
        args.evidence.write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in evidence.items() if k!='source_sha256'},indent=2))
finally:
    host.stdin.close()
    try:
        host.wait(timeout=10)
    except subprocess.TimeoutExpired:
        host.kill()
        host.wait()
