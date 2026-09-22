#!/usr/bin/env node
import fs from 'node:fs';
import {run} from '../_build/js/release/build/cmd/bridge/bridge.js';

const usage = `Usage: node tools/touchstone.mjs COMMAND INPUT [OPTIONS-JSON] [OUTPUT]
Commands: inspect validate dump normalize legacy convert renormalize select
          interpolate cascade deembed diagnostics metrics delay
Legacy INPUT.sNp supplies its port count; otherwise OPTIONS needs "ports".
Options: parameter, reference_ohms, selection, frequency_hz, input/output (ports),
         tolerance, format, unit, left_file/right_file (fixtures).
Output files are created exclusively: existing files are never overwritten.
Reports print JSON; file transformations print Touchstone if OUTPUT is absent.`;

function read(file) {
  // Open before fstat to avoid path-swap races; bound allocation and reject
  // non-ASCII bytes instead of silently replacing them during UTF-8 decoding.
  const fd = fs.openSync(file, 'r');
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || stat.size > 64_000_000) throw new Error('input must be a file <=64 MB');
    const data = Buffer.alloc(stat.size + 1);
    let size = 0, count;
    while (size < data.length && (count = fs.readSync(fd, data, size, data.length-size, null))) size += count;
    if (size > stat.size) throw new Error('input grew while reading; retry a stable file');
    for (let i=0;i<size;i++) if (data[i]>127) throw new Error('Touchstone input must be ASCII');
    return data.subarray(0,size).toString('ascii');
  } finally { fs.closeSync(fd); }
}

function infer(file, options, key) {
  const match = /\.s(\d+)p$/i.exec(file);
  if (match && options[key] === undefined) options[key] = Number(match[1]);
}

try {
  const args = process.argv.slice(2);
  if (args.length===1 && ['--help','-h'].includes(args[0])) { console.log(usage); }
  else {
    if (args.length<2 || args.length>4) throw new Error(usage);
    const [command, input, optionsText='{}', output] = args;
    if (optionsText.length>1_000_000) throw new Error('options too large');
    const options = JSON.parse(optionsText);
    if (!options || typeof options!=='object' || Array.isArray(options)) throw new Error('options must be an object');
    options.command = command;
    infer(input,options,'ports');
    let left='',right='';
    for (const side of ['left','right']) {
      const file=options[`${side}_file`];
      if (file!==undefined) {
        if (typeof file!=='string') throw new Error(`${side}_file must be a path`);
        infer(file,options,`${side}_ports`);
        if (side==='left') left=read(file); else right=read(file);
        delete options[`${side}_file`];
      }
    }
    const result = JSON.parse(run(read(input),JSON.stringify(options),left,right));
    const content = result && typeof result.text==='string' ? result.text : JSON.stringify(result,null,2)+'\n';
    if (output!==undefined) fs.writeFileSync(output,content,{encoding:'utf8',flag:'wx'});
    else process.stdout.write(content);
  }
} catch (error) {
  console.error(`touchstone: ${error.message}`);
  process.exitCode = 2;
}
