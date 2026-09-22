// JSON-lines adapter for the independent Python oracle, not library logic.
import readline from 'node:readline';
import {run} from '../_build/js/release/build/cmd/bridge/bridge.js';
for await (const line of readline.createInterface({input:process.stdin,crlfDelay:Infinity})) {
  try {
    const q=JSON.parse(line);
    const result=JSON.parse(run(q.text,JSON.stringify(q.options??{}),q.left??'',q.right??''));
    console.log(JSON.stringify({ok:true,result}));
  } catch(error) { console.log(JSON.stringify({ok:false,error:error.message})); }
}
