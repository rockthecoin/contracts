import {execFileSync} from 'node:child_process';
if(!process.argv.includes('--verify'))throw Error('Published programs are immutable. Use --verify to reproduce in a temporary directory.');
execFileSync(process.env.RTC_ALGORAND_PYTHON||'python3',['scripts/rebuild-algorand.py','--package','algorand-suite-v1'],{stdio:'inherit'});
