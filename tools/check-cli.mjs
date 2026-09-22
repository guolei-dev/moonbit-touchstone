import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {run} from '../_build/js/release/build/cmd/bridge/bridge.js';

const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'moon-touchstone-cli-'));
let checks=0;
function cli(args,success=true) {
  const p=spawnSync(process.execPath,['tools/touchstone.mjs',...args],{encoding:'utf8',timeout:15000});
  assert.equal(p.status,success?0:2,p.stderr); checks++; return p;
}
try {
  const source='examples/attenuator.s2p';
  assert.equal(JSON.parse(cli(['inspect',source]).stdout).ports,2);
  const delay=JSON.parse(cli(['delay',source,'{"input":0,"output":1}']).stdout);
  assert.ok(delay.every(x=>Math.abs(x-1e-9)<1e-20)); checks++;
  const out=path.join(scratch,'normalized.ts');
  cli(['normalize',source,'{}',out]);
  const before=fs.readFileSync(out);
  cli(['normalize',source,'{}',out],false);
  assert.deepEqual(fs.readFileSync(out),before); checks++;
  cli(['normalize',source,'{}',source],false);
  cli(['validate',out]);
  cli(['convert',source,'{"parameter":"UNKNOWN"}'],false);
  cli(['select',source,'{"selection":[0,0]}'],false);
  cli(['cascade',source,JSON.stringify({right_file:source})]);
  const binary=path.join(scratch,'nul.s2p');
  fs.writeFileSync(binary,'# Hz S RI R 50\n1 0 0 0 0 0 0 0 0\x00');
  cli(['validate',binary],false);
  fs.writeFileSync(binary,Buffer.from([0xff]));
  cli(['validate',binary],false);
  assert.throws(()=>run(fs.readFileSync(source,'ascii'),'{"command":"metrics","ports":2,"input":-1,"output":1}','',''));
  checks++;
  console.log(JSON.stringify({checks,status:'passed'}));
} finally {
  // Only this uniquely created test directory, never a supplied output path.
  fs.rmSync(scratch,{recursive:true,force:true});
}
