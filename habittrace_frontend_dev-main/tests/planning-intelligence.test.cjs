const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {test}=require('node:test');
const Module=require('node:module');
const ts=require('typescript');
const React=require('react');
const {renderToStaticMarkup}=require('react-dom/server');
const frontend=path.resolve(__dirname,'..');
for(const ext of ['.ts','.tsx']) require.extensions[ext]=(module,filename)=>module._compile(ts.transpileModule(fs.readFileSync(filename,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,filename);
const load=Module._load;
let refreshes=0;
Module._load=function(request,...args){
 if(request==='./supabase')return {supabase:{auth:{getSession:async()=>({data:{session:{access_token:'test-token'}}})}}};
 if(request==='./refresh' || request==='@/lib/refresh')return {notifyDataChanged(){refreshes++},useDataRefresh(){}};
 if(request.startsWith('@/'))return load.call(this,path.join(frontend,request.slice(2)),...args);
 return load.call(this,request,...args);
};
const api=require('../lib/api.ts');
const {buildOutcomeInput,EMPTY_OUTCOME_DRAFT,outcomeConfirmation}=require('../lib/outcome.ts');
const PlanDecisions=require('../components/plan-decisions.tsx').default;
const ProjectForecast=require('../components/group/project-forecast.tsx').default;
const Evaluation=require('../components/prediction-evaluation.tsx').default;

const block={planned_start:'2099-09-06T16:00:00Z',duration_minutes:60,daily_minutes:120,deadline_slack_minutes:1440,
 success_probability:.72,factors:[],actions:[]};
const comparison={id:'c1',task_title:'Write the draft',timezone_name:'UTC',warnings:[],
 evidence:{history_samples:2,history_factors:[],duration:{available:false,sample_count:1},progress_ratio:.4,
 remaining_minutes:60,continuation:true,note:'Evidence size is not validated accuracy.'},
 options:[{id:'current',title:'Plan remaining work',description:'Same work scope.',available:true,unavailable_reasons:[],blocks:[block],total_minutes:60},
 {id:'split',title:'Two shorter blocks',description:'Same total duration with a break.',available:true,unavailable_reasons:[],
 blocks:[{...block,duration_minutes:30},{...block,duration_minutes:30,planned_start:'2099-09-06T16:45:00Z'}],total_minutes:60},
 {id:'buffer',title:'Give it more time',description:'Extra time.',available:false,unavailable_reasons:['Overlaps: Team review'],blocks:[block],total_minutes:75}]};
const task={id:'t1',title:'Write the draft',task_status:'failed'};
const project={tasks:[{task_id:'t1',title:'Research <private>',status:'at_risk',reasons:['Estimated finish is after deadline.'],remaining_minutes:90,
 forecast_finish:'2099-09-09T18:00:00Z',downstream_count:2,predecessor_ids:[],blocked_by:[],assignee_ids:['me']}],
 dependencies:[],milestones:[{id:'m1',title:'Draft ready',due_date:'2099-09-10',completion_criteria:'Every section can be reviewed.',status:'unknown',
 task_ids:['t1'],forecast_finish:null,slack_minutes:null,missing_task_ids:[]}],
 workload:[{user_id:'me',name:'Alex',minutes_per_day:null,available_until:null,remaining_minutes:90,has_unknown_work:false,capacity_minutes:null,spare_minutes:null}],
 suggestions:[],help_requests:[],assumptions:['Only shared information is used.'],generated_at:'2099-09-06T10:00:00Z',timezone_name:'UTC'};
function renderStates(Component,props,states){
 const useState=React.useState;let index=0;
 React.useState=function(value){const i=index++;return useState(Object.hasOwn(states,i)?states[i]:value)};
 try{return renderToStaticMarkup(React.createElement(Component,props));}finally{React.useState=useState;}
}

test('plan choices show full scope, disabled conflicts, private evidence and explicit confirmation',()=>{
 const html=renderStates(PlanDecisions,{task,onClose(){},onApplied(){}},{0:comparison,1:'current'});
 assert.match(html,/Choose an approach/);assert.match(html,/radio/);
 assert.match(html,/Two shorter blocks/);assert.match(html,/Block 2/);
 assert.match(html,/Overlaps: Team review/);assert.match(html,/Confirm this plan/);
 assert.match(html,/little history/);assert.match(html,/not prediction accuracy/);
 assert.match(html,/creates a next attempt/);
 assert.doesNotMatch(html,/team success probability|overall success/);
 if(process.env.PLANNING_QA_DIR){fs.mkdirSync(process.env.PLANNING_QA_DIR,{recursive:true});fs.writeFileSync(path.join(process.env.PLANNING_QA_DIR,'personal.html'),html.replace('<dialog ','<dialog open '));}
});
test('project view explains missing data, workflow, checkpoints and opt-in sharing without private scores',()=>{
 const html=renderStates(ProjectForecast,{groupId:'g1',userId:'me',tasks:[{id:'t1',title:'Research <private>',assigned_to_ids:['me']}],isAdmin:true},{0:project});
 assert.match(html,/Map the work/);assert.match(html,/Check milestones/);assert.match(html,/Find bottlenecks/);
 assert.match(html,/Availability not shared/);assert.match(html,/Needs more information/);
 assert.match(html,/Stop sharing availability/);assert.match(html,/Accepting records an agreement/);
 assert.match(html,/Research &lt;private&gt;/);assert.doesNotMatch(html,/<private>/);
 assert.match(html,/not a team success probability/);
 if(process.env.PLANNING_QA_DIR)fs.writeFileSync(path.join(process.env.PLANNING_QA_DIR,'project.html'),html);
});
test('evaluation does not invent quality from a sparse sample',()=>{
 const html=renderStates(Evaluation,{}, {0:{shown:2,selected:1,evaluated:{count:1,brier_score:.1},earlier:{count:0,brier_score:null},later:{count:1,brier_score:.1},note:'Missing excluded',window:'Bounded records',by_model:[]}});
 assert.match(html,/Too few matched results/);assert.doesNotMatch(html,/Estimate error:/);
});
test('comparison writes metadata without refreshing plans; only apply refreshes plan data',async()=>{
 const calls=[];global.fetch=async(url,options)=>{calls.push({url,options});return new Response('{}',{status:200,headers:{'content-type':'application/json'}})};
 const before=refreshes;
 await api.comparePlanChoices('t1',45,4,2);await api.recordComparisonViewed('c1');
 assert.equal(refreshes,before);
 assert.deepEqual(JSON.parse(calls[0].options.body),{task_id:'t1',remaining_minutes:45,expected_energy:4,expected_focus:2});
 await api.applyPlanChoice('c1','split');assert.equal(refreshes,before+1);
 assert.deepEqual(JSON.parse(calls[2].options.body),{option_id:'split',confirmed:true});
});
test('partial progress and actual minutes are preserved on first recording',()=>{
 const result=buildOutcomeInput({...EMPTY_OUTCOME_DRAFT,choice:'not_completed',minutesSpent:'25',progressPercent:'40'});
 assert.equal(result.ok,true);assert.equal(result.input.outcome_status,'partial');assert.equal(result.input.completion_ratio,.4);
 assert.equal(result.input.active_minutes,25);assert.equal(result.input.actual_start_time,undefined);
 assert.match(outcomeConfirmation(result.input,null),/40% progress/);
 assert.equal(buildOutcomeInput({...EMPTY_OUTCOME_DRAFT,choice:'not_completed',progressPercent:'100'}).ok,false);
});
test('reported start can be matched prospectively without inventing an end',()=>{
 const result=buildOutcomeInput({...EMPTY_OUTCOME_DRAFT,choice:'completed',actualStartAt:'2026-11-20T10:00',minutesSpent:'35'}, {now:new Date('2026-11-24T12:00:00Z')});
 assert.equal(result.ok,true);assert.ok(result.input.actual_start_time);assert.equal(result.input.actual_end_time,undefined);
 assert.equal(result.input.active_minutes,35);assert.equal(result.input.actual_end_unknown,true);
});
