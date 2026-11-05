import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
export function suiCli(){
  const pins=JSON.parse(fs.readFileSync(new URL('../toolchains/sui.json',import.meta.url)));
  const cli=process.env.SUI||new URL('../.toolchains/sui',import.meta.url).pathname;
  assert.equal(createHash('sha256').update(fs.readFileSync(cli)).digest('hex'),pins.binary_sha256,'Sui executable checksum');
  assert.equal(execFileSync(cli,['--version'],{encoding:'utf8'}).trim(),pins.version,'Sui executable version');
  return cli;
}
