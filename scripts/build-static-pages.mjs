import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

const buildRoot = process.env.BUILD_OUT_DIR || "dist";
const outDir = join(buildRoot, "client");

await rm(buildRoot, { recursive: true, force: true });
await rm(".wrangler", { recursive: true, force: true });
await mkdir(outDir, { recursive: true });
await cp("public", outDir, { recursive: true });

const html = String.raw`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Macro Europe Monitor</title>
    <link rel="icon" href="/favicon.svg" />
    <style>
      :root { --bg:#f7f7f5; --paper:#ffffff; --ink:#191919; --muted:#707070; --line:#e4e1da; --line-strong:#c9c4b8; --brand:#191919; --teal:#11675f; --red:#a83f39; }
      * { box-sizing: border-box; }
      body { margin:0; background:var(--bg); color:var(--ink); font-family:Inter,Segoe UI,Arial,sans-serif; }
      .shell { width:min(1480px, calc(100vw - 32px)); margin:0 auto; padding:22px 0 48px; }
      .topbar { display:flex; justify-content:space-between; align-items:flex-start; gap:18px; padding:0; border:0; border-radius:0; background:transparent; box-shadow:none; }
      .brand { margin:0; color:var(--ink); font-size:.92rem; font-weight:760; letter-spacing:.12em; line-height:1.2; text-align:left; text-transform:uppercase; }
      .status { display:flex; flex-wrap:wrap; gap:10px; justify-content:flex-end; color:var(--muted); font-size:.68rem; letter-spacing:.08em; text-transform:uppercase; }
      .pill { border:0; border-radius:0; padding:0; background:transparent; }
      .tabs { display:flex; justify-content:flex-start; gap:28px; margin:14px 0 24px; overflow-x:auto; padding:0 0 8px; border-bottom:1px solid var(--line); }
      button { font:inherit; cursor:pointer; }
      .tab,.legend-button,.window-button { border:1px solid var(--line); border-radius:999px; background:#fff; color:var(--muted); min-height:34px; padding:0 12px; font-weight:650; }
      .tab { min-height:30px; border:0; border-radius:0; background:transparent; padding:0; color:#333; font-size:.78rem; font-weight:760; letter-spacing:.14em; text-transform:uppercase; }
      .tab.active { border-bottom:1px solid var(--ink); background:transparent; color:var(--ink); }
      .grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px; align-items:stretch; }
      .panel { min-width:0; border:1px solid var(--line); border-radius:4px; background:var(--paper); box-shadow:0 12px 34px rgba(32,32,32,.045); padding:18px; }
      .wide { grid-column:1/-1; }
      .head { display:flex; justify-content:space-between; align-items:flex-start; gap:14px; margin-bottom:14px; }
      .kicker { margin:0 0 5px; color:var(--muted); font-size:.78rem; font-weight:750; text-transform:uppercase; }
      h2 { margin:0; font-size:1.18rem; }
      .window { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:6px; }
      .window-button.active { border-color:var(--teal); color:var(--teal); background:rgba(17,103,95,.1); }
      .legend { display:flex; flex-wrap:wrap; justify-content:center; gap:7px; margin:8px 0 4px; }
      .legend-button { display:inline-flex; align-items:center; gap:7px; font-size:.8rem; }
      .legend-button.hidden { opacity:.45; }
      .swatch { width:9px; height:9px; border-radius:999px; display:inline-block; }
      svg { display:block; width:100%; height:auto; min-height:330px; overflow:visible; }
      .grid-line { stroke:#dedbd2; stroke-width:1; }
      .axis-line { stroke:#bfb9aa; stroke-width:1.2; }
      .tick { fill:var(--muted); font-size:12px; }
      .sentix-pmi-left-tick { fill:#204f86; }
      .sentix-pmi-right-tick { fill:#c47a20; }
      .line { fill:none; stroke-width:2.6; stroke-linecap:round; stroke-linejoin:round; }
      .source { margin:6px 0 0; color:var(--muted); font-size:.74rem; line-height:1.45; }
      .source a { color:var(--brand); font-weight:650; text-decoration:none; }
      .source a:hover { text-decoration:underline; }
      .plot { position:relative; }
      .chart-tooltip { position:absolute; z-index:4; min-width:190px; max-width:280px; border:1px solid var(--line); border-radius:8px; background:rgba(255,253,250,.98); box-shadow:0 16px 40px rgba(41,36,25,.14); padding:10px 11px; pointer-events:none; transform:translate(-50%, calc(-100% - 10px)); font-size:.82rem; }
      .tooltip-date { margin-bottom:7px; color:var(--muted); font-size:.78rem; font-weight:750; }
      .tooltip-row { display:grid; grid-template-columns:10px 1fr auto; align-items:center; gap:8px; }
      .tooltip-row + .tooltip-row { margin-top:4px; }
      table { width:100%; min-width:980px; border-collapse:collapse; table-layout:fixed; font-size:.86rem; }
      th:nth-child(1),td:nth-child(1){width:10%} th:nth-child(2),td:nth-child(2){width:18%} th:nth-child(3),td:nth-child(3){width:18%} th:nth-child(4),td:nth-child(4){width:34%;font-size:inherit} th:nth-child(5),td:nth-child(5){width:9%} th:nth-child(6),td:nth-child(6){width:11%}
      th { border-top:1px solid var(--ink); border-bottom:1px solid var(--line-strong); background:#fff; color:var(--ink); font-size:.72rem; letter-spacing:.08em; padding:8px 10px; text-align:left; text-transform:uppercase; }
      td { border-bottom:1px solid var(--line); padding:10px; vertical-align:top; line-height:1.42; }
      tr:nth-child(even) td { background:rgba(222,219,210,.28); }
      td.priority-policy-comment { color:var(--red); font-weight:650; }
      .table-wrap { overflow-x:auto; }
      .bias { border-radius:999px; padding:4px 8px; font-size:.76rem; font-weight:700; }
      .hawkish { background:rgba(168,63,57,.12); color:var(--red); }
      .mildly-hawkish { background:rgba(168,63,57,.08); color:var(--red); }
      .dovish { background:rgba(17,103,95,.12); color:var(--teal); }
      .mildly-dovish { background:rgba(17,103,95,.08); color:var(--teal); }
      .neutral { background:rgba(109,106,99,.12); color:var(--muted); }
      .footer { margin:20px 0 0; color:var(--muted); font-size:.82rem; }
      @media (max-width:940px){ .shell{width:min(100% - 20px,1480px);padding-top:16px}.topbar,.head{flex-direction:column}.brand{text-align:left}.status,.window{justify-content:flex-start}.tabs{gap:20px;justify-content:flex-start}.grid{grid-template-columns:1fr}.panel{padding:14px} svg{min-height:300px} table{min-width:900px;font-size:.84rem} }
    </style>
  </head>
  <body>
    <main class="shell">
      <header class="topbar"><p class="brand">Macro Europe Monitor</p><div class="status" id="status"></div></header>
      <nav class="tabs" id="tabs"></nav>
      <section class="grid" id="content"></section>
      <p class="footer" id="footer"></p>
    </main>
    <script>
      const charts = [
        ["pmi_composite","activity","PMI Composite","Activity","Index",null,false,["pmi_ea","pmi_de","pmi_fr","pmi_es","pmi_uk","pmi_it"],null,"10y"],
        ["pmi_gdp","activity","PMI Composite vs GDP","Growth","PMI","% q/q SA",false,["pmi_ea_gdp","gdp_qoq_sa_ea"],{left:{min:35,max:65},right:{min:-2.5,max:2.5}},"all"],
        ["pmi_manufacturing","activity","PMI Manufacturing","Activity","Index",null,false,["pmi_mfg_ea","pmi_mfg_de","pmi_mfg_fr","pmi_mfg_es","pmi_mfg_uk","pmi_mfg_it"],null,"10y"],
        ["pmi_services","activity","PMI Services","Activity","Index",null,false,["pmi_srv_ea","pmi_srv_de","pmi_srv_fr","pmi_srv_es","pmi_srv_uk","pmi_srv_it"],null,"10y"],
        ["sentix_pmi","activity","Sentix vs PMI Composite","Sentiment","PMI","Sentix",false,["pmi_ea_sentix","sentix_ea"],{left:{min:40,max:64},right:{min:-55,max:50}}],
        ["zew_sentiment","activity","ZEW Indicator","Sentiment","Balance",null,false,["zew_de"]],
        ["weekly_activity","activity","Germany Weekly Activity Index","High frequency","%",null,false,null,null,"2y"],
        ["toll_mileage","activity","Toll Mileage","Mobility","Index",null,false,["toll_de","toll_de_daily"],null,"6m"],
        ["hicp_headline_core","inflation","HICP","Headline and core","% y/y"],
        ["hicp_components","inflation","HICP core goods and services","Components","% y/y"],
        ["expected_selling_prices","inflation","Services HICP vs EC Services Survey","Price pressures","Survey balance","% y/y",false,["esp_services","core_services_expected"],{left:{min:-15,max:40},right:{min:-1,max:7}}],
        ["wage_tracker","inflation","Wage Tracker","Wages","% y/y"]
      ].map(([id,tab,title,kicker,yLeft,yRight,wide,order,fixedDomains,defaultWindow]) => ({id,tab,title,kicker,yLeft,yRight,wide,order,fixedDomains,defaultWindow}));
      const tabs = [{id:"speakers",label:"ECB Speakers"},{id:"activity",label:"Activity Monitor"},{id:"inflation",label:"Inflation Monitor"}];
      const palette = ["#204f86","#c47a20","#11675f","#a83f39","#3f7f52","#6c5f8d","#111111","#8c7b57"];
      const windows = [{key:"all",label:"All"},{key:"10y",label:"10Y",years:10},{key:"5y",label:"5Y",years:5},{key:"2y",label:"2Y",years:2},{key:"1y",label:"1Y",years:1},{key:"6m",label:"6M",months:6}];
      let activeTab = "speakers", allRows = [], speakers = [], metadata = {}, state = new Map();

      Promise.all([text("/data/activity_series.csv"), text("/data/inflation_series.csv"), text("/data/ecb_speakers.csv"), fetch("/data/metadata.json",{cache:"no-store"}).then(r => r.ok ? r.json() : {})])
        .then(([a,i,s,m]) => { allRows = [...parseCsv(a), ...parseCsv(i)].map(seriesRow); speakers = parseCsv(s); metadata = m; render(); });

      async function text(path){ const r = await fetch(path,{cache:"no-store"}); if(!r.ok) throw new Error(path); return r.text(); }
      function parseCsv(text){ const rows=[]; let row=[], field="", q=false; for(let n=0;n<text.length;n++){ const c=text[n], nx=text[n+1]; if(q){ if(c=='"'&&nx=='"'){field+='"';n++;} else if(c=='"') q=false; else field+=c; } else if(c=='"') q=true; else if(c==","){row.push(field);field="";} else if(c=="\n"){row.push(field);rows.push(row);row=[];field="";} else if(c!="\r") field+=c; } if(field||row.length){row.push(field);rows.push(row);} const h=rows.shift()||[]; return rows.filter(r=>r.some(Boolean)).map(r=>Object.fromEntries(h.map((x,n)=>[x,r[n]||""]))); }
      function seriesRow(r){ return {...r, value:Number(r.value), time:new Date(r.date+"T00:00:00").getTime(), axis:r.axis==="right"?"right":"left"}; }
      function render(){ renderTabs(); document.getElementById("status").innerHTML = '<span class="pill">Updated: '+(metadata.last_updated||"pending")+'</span><span class="pill">'+new Set(allRows.map(r=>r.series_id)).size+' series</span>'; document.getElementById("footer").textContent = 'Data mode: '+(metadata.data_mode||"source linked")+'. Data contract: CSVs in public/data.'; const el=document.getElementById("content"); el.innerHTML=""; if(activeTab==="speakers") renderSpeakers(el); else charts.filter(c=>c.tab===activeTab).forEach(c=>renderChart(el,c)); }
      function renderTabs(){ const el=document.getElementById("tabs"); el.innerHTML=""; tabs.forEach(t=>{ const b=document.createElement("button"); b.className="tab"+(t.id===activeTab?" active":""); b.textContent=t.label; b.onclick=()=>{activeTab=t.id;render();}; el.appendChild(b); }); }
      function defaultHidden(chart){ return chart.id==="pmi_gdp" ? [] : chart.id.startsWith("pmi_") ? (chart.order||[]).filter(id=>!id.endsWith("_ea")) : []; }
      function chartState(chart){ if(!state.has(chart.id)) state.set(chart.id,{window:chart.defaultWindow||"all",hidden:new Set(defaultHidden(chart))}); return state.get(chart.id); }
      function buildSeries(rows, chart){ const map=new Map(); rows.forEach(r=>{ if(!map.has(r.series_id)) map.set(r.series_id,{id:r.series_id,name:r.series_name,country:r.country,axis:r.axis,unit:r.unit,source:r.source,source_url:r.source_url,frequency:r.frequency,source_note:r.source_note,points:[]}); map.get(r.series_id).points.push(r); }); return [...map.values()].map((s,i)=>({...s,points:s.points.sort((a,b)=>a.time-b.time)})).sort((a,b)=>{ const o=chart.order||[], ai=o.indexOf(a.id), bi=o.indexOf(b.id); return ai<0&&bi<0?a.name.localeCompare(b.name):ai<0?1:bi<0?-1:ai-bi; }).map((s,i)=>({...s,color:palette[i%palette.length]})); }
      function renderChart(root, chart){ const st=chartState(chart), panel=document.createElement("article"); panel.className="panel"+(chart.wide?" wide":""); const rows=allRows.filter(r=>r.chart_id===chart.id); let series=buildSeries(rows,chart); panel.innerHTML='<div class="head"><div><p class="kicker">'+chart.kicker+'</p><h2>'+chart.title+'</h2></div><div class="window"></div></div><div class="legend"></div><div class="plot"></div><p class="source"></p>'; const win=panel.querySelector(".window"); windows.forEach(w=>{ const b=document.createElement("button"); b.className="window-button"+(st.window===w.key?" active":""); b.textContent=w.label; b.onclick=()=>{st.window=w.key;render();}; win.appendChild(b); }); const legend=panel.querySelector(".legend"); series.forEach(s=>{ const b=document.createElement("button"); b.className="legend-button"+(st.hidden.has(s.id)?" hidden":""); b.innerHTML='<span class="swatch" style="background:'+s.color+'"></span>'+s.name; b.onclick=()=>{ st.hidden.has(s.id)?st.hidden.delete(s.id):st.hidden.add(s.id); render(); }; legend.appendChild(b); }); const w=windows.find(x=>x.key===st.window); if(w?.years||w?.months){ const max=Math.max(...series.flatMap(s=>s.points.map(p=>p.time))); const min=new Date(max); if(w.years) min.setFullYear(min.getFullYear()-w.years); else min.setMonth(min.getMonth()-w.months); series=series.map(s=>({...s,points:s.points.filter(p=>p.time>=min.getTime())})); } draw(panel.querySelector(".plot"), series.filter(s=>!st.hidden.has(s.id)), chart); const sm=new Map(); series.forEach(s=>sm.set(s.source+"|"+s.source_url+"|"+(s.frequency||"")+"|"+(s.source_note||""),s)); panel.querySelector(".source").innerHTML='Source: '+[...sm.values()].map(s=>{ const label=s.source+(s.frequency?' ('+titleCase(s.frequency)+')':'')+(s.source_note?' '+s.source_note:''); return s.source_url?'<a target="_blank" rel="noreferrer" href="'+s.source_url+'">'+label+'</a>':label; }).join("; "); root.appendChild(panel); }
      function draw(root, series, chart){ const W=920,H=470,m={t:30,r:54,b:42,l:50}, iw=W-m.l-m.r, ih=H-m.t-m.b, pts=series.flatMap(s=>s.points); if(!pts.length){root.textContent="Waiting for data";return;} const tx=domain(pts.map(p=>p.time)), left=series.filter(s=>s.axis!=="right").flatMap(s=>s.points.map(p=>p.value)), right=series.filter(s=>s.axis==="right").flatMap(s=>s.points.map(p=>p.value)), ly=chart.fixedDomains?.left||domain(left.length?left:right), ry=chart.fixedDomains?.right||(right.length?domain(right):ly); const sx=t=>m.l+(t-tx.min)/(tx.max-tx.min)*iw, sy=(v,a)=>{const d=a==="right"?ry:ly; return m.t+(1-(v-d.min)/(d.max-d.min))*ih}; let svg='<svg viewBox="0 0 '+W+' '+H+'" role="img" aria-label="'+chart.title+'"><defs><clipPath id="'+chart.id+'-plot-clip"><rect x="'+m.l+'" y="'+m.t+'" width="'+iw+'" height="'+ih+'"/></clipPath></defs>'; ticks(ly,5).forEach(t=>{const y=sy(t,"left"); svg+='<line class="grid-line" x1="'+m.l+'" x2="'+(W-m.r)+'" y1="'+y+'" y2="'+y+'"/><text class="tick '+(chart.id==="sentix_pmi"?"sentix-pmi-left-tick":"")+'" text-anchor="end" x="'+(m.l-10)+'" y="'+(y+4)+'">'+fmt(t)+'</text>';}); if(right.length) ticks(ry,5).forEach(t=>{const y=sy(t,"right"); svg+='<text class="tick '+(chart.id==="sentix_pmi"?"sentix-pmi-right-tick":"")+'" text-anchor="start" x="'+(W-m.r+10)+'" y="'+(y+4)+'">'+fmt(t)+'</text>';}); ticks(tx,7).forEach(t=>{const x=sx(t); svg+='<line class="grid-line" x1="'+x+'" x2="'+x+'" y1="'+m.t+'" y2="'+(H-m.b)+'"/><text class="tick" text-anchor="middle" x="'+x+'" y="'+(H-m.b+24)+'">'+new Date(t).getFullYear().toString().slice(2)+'</text>';}); svg+='<line class="axis-line" x1="'+m.l+'" x2="'+m.l+'" y1="'+m.t+'" y2="'+(H-m.b)+'"/><line class="axis-line" x1="'+m.l+'" x2="'+(W-m.r)+'" y1="'+(H-m.b)+'" y2="'+(H-m.b)+'"/>'; if(chart.yRight) svg+='<line class="axis-line" x1="'+(W-m.r)+'" x2="'+(W-m.r)+'" y1="'+m.t+'" y2="'+(H-m.b)+'"/>'; svg+='<text class="tick" x="'+m.l+'" y="20">'+chart.yLeft+'</text>'; if(chart.yRight) svg+='<text class="tick '+(chart.id==="sentix_pmi"?"sentix-pmi-right-tick":"")+'" text-anchor="end" x="'+(W-m.r)+'" y="20">'+chart.yRight+'</text>'; series.forEach(s=>{ if(s.id.endsWith("_daily")){ s.points.forEach(p=>{ svg+='<circle class="point" clip-path="url(#'+chart.id+'-plot-clip)" fill="'+s.color+'" cx="'+sx(p.time).toFixed(2)+'" cy="'+sy(p.value,s.axis).toFixed(2)+'" r="2.2"/>'; }); } else { svg+='<path class="line" clip-path="url(#'+chart.id+'-plot-clip)" stroke="'+s.color+'" d="'+s.points.map((p,i)=>(i?'L':'M')+sx(p.time).toFixed(2)+','+sy(p.value,s.axis).toFixed(2)).join(' ')+'"/>'; } }); root.innerHTML=svg+'</svg><div class="chart-tooltip" hidden></div>'; const tip=root.querySelector('.chart-tooltip'), svgEl=root.querySelector('svg'); svgEl.addEventListener('mouseleave',()=>{tip.hidden=true}); svgEl.addEventListener('mousemove',ev=>{ const rect=svgEl.getBoundingClientRect(), x=(ev.clientX-rect.left)/rect.width*W, y=(ev.clientY-rect.top)/rect.height*H; if(x<m.l||x>W-m.r||y<m.t||y>H-m.b){tip.hidden=true;return;} const target=tx.min+(x-m.l)/iw*(tx.max-tx.min); const nearest=series.map(s=>{ const p=s.points.reduce((a,b)=>Math.abs(b.time-target)<Math.abs(a.time-target)?b:a); return {s,p,x:sx(p.time),y:sy(p.value,s.axis)}; }); const anchor=nearest.reduce((a,b)=>Math.abs(b.p.time-target)<Math.abs(a.p.time-target)?b:a); tip.innerHTML='<div class="tooltip-date">'+dateLabel(anchor.p.date,chart.id)+'</div>'+nearest.map(n=>'<div class="tooltip-row"><span class="swatch" style="background:'+n.s.color+'"></span><span>'+n.s.name+'</span><strong>'+fmt(n.p.value)+'</strong></div>').join(''); tip.style.left=(anchor.x/W*100)+'%'; tip.style.top=(Math.min(...nearest.map(n=>n.y))/H*100)+'%'; tip.hidden=false; }); }
      function titleCase(v){ return String(v||"").split(/\s+/).filter(Boolean).map(w=>w.charAt(0).toUpperCase()+w.slice(1).toLowerCase()).join(" "); }
      function domain(v){ let min=Math.min(...v), max=Math.max(...v); if(min===max){min-=1;max+=1;} const p=(max-min)*.12; return {min:min-p,max:max+p}; }
      function ticks(d,n){ const min=d.min??d, max=d.max, step=(max-min)/Math.max(1,n-1); return Array.from({length:n},(_,i)=>min+i*step); }
      function fmt(v){ const a=Math.abs(v), d=a>=100?0:a>=10?1:2; return v.toLocaleString("en-US",{minimumFractionDigits:d,maximumFractionDigits:d}); }
      function dateLabel(date,chartId){ return new Intl.DateTimeFormat(chartId==="weekly_activity"?"en-GB":"en-US",chartId==="weekly_activity"?{day:"2-digit",month:"2-digit",year:"numeric"}:{month:"2-digit",year:"numeric"}).format(new Date(date+"T00:00:00")); }
      function isPriorityEcbMember(member){ return ["lagarde","lane","schnabel"].includes(String(member||"").trim().toLowerCase()); }
      function biasClassName(bias){ return String(bias||"neutral").replace(/\s+/g,"-"); }
      function renderSpeakers(root){ const panel=document.createElement("article"); panel.className="panel wide"; panel.innerHTML='<div class="head"><div><p class="kicker">Communication</p><h2>ECB Speakers</h2></div></div><div class="table-wrap"><table><thead><tr><th>Date</th><th>Member</th><th>Position</th><th>Policy Comments</th><th>Bias</th><th>vs Previous</th></tr></thead><tbody>'+speakers.map(s=>'<tr><td>'+s.date+'</td><td>'+(s.source_url?'<a target="_blank" rel="noreferrer" href="'+s.source_url+'">'+s.member+' ('+s.country+')</a>':s.member+' ('+s.country+')')+'</td><td>'+s.position+'</td><td class="'+(isPriorityEcbMember(s.member)?'priority-policy-comment':'')+'">'+s.policy_comments+'</td><td><span class="bias '+biasClassName(s.bias)+'">'+s.bias+'</span></td><td>'+s.stance_change+'</td></tr>').join("")+'</tbody></table></div>'; root.appendChild(panel); }
    </script>
  </body>
</html>`;

await writeFile(join(outDir, "index.html"), html);





