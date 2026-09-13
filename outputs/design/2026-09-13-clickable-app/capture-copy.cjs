// Render the local template functions to review copy, including collapsed rules.
// This has no browser, network, or product effects.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const here = __dirname;
const ref = fs.readFileSync(path.join(here,'reference.html'),'utf8');
const extension = fs.readFileSync(path.join(here,'screens.js'),'utf8');
let source = ref.slice(ref.indexOf('const root=document'), ref.indexOf('function render()'));
source += '\nconst fieldworkArtAssets = {};\n' + extension.slice(0,extension.indexOf("root.addEventListener('input'"));
const context = vm.createContext({document:{getElementById:()=>({})}});
vm.runInContext(source,context);
const rendered = vm.runInContext(`
design.art='none';
const samples={};
for (const [key,fn] of Object.entries({home,challenges:challengeIndex,detail:challengeDetail,create:flow,lobby,invitePreview,invitation,agreement,scheduled,goal:goalDetail,result,review,reviewReceipt,community,you,health,privacy,support,profile,existing,leave,left})) samples[key]=fn();
for (let step=2;step<=5;step++){draft.step=step;samples['create-'+step]=flow();}
for (const activity of Object.keys(activityInfo)) for (const who of ['friends','personal']) for(const format of ['goals','leaderboard']) {
 draft.activity=activity;draft.who=who;draft.format=format;draft.target=activity==='timed'?'25:00':'150';draft.distance='5';appState.personalTarget=draft.target;
 samples['agreement-'+activity+'-'+who+'-'+format]=agreement();
}
appState.reviewContext='invitation';samples['agreement-invitation']=agreement();
samples;
`,context);
const rewrites = JSON.parse(fs.readFileSync(path.join(here,'copy-rewrites.json'),'utf8'));
for (const key in rendered) for (const item of rewrites) rendered[key]=rendered[key].split(item.before).join(item.after);
fs.mkdirSync(path.join(here,'copy-audit'),{recursive:true});
fs.writeFileSync(path.join(here,'copy-audit','screens-after.json'),JSON.stringify(rendered,null,2));
console.log('Captured '+Object.keys(rendered).length+' screen and agreement variants.');
