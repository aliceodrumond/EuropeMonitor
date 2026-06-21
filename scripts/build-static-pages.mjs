import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

const outDir = join("dist", "client");

await rm("dist", { recursive: true, force: true });
await rm(".wrangler", { recursive: true, force: true });
await mkdir(outDir, { recursive: true });
await cp("public", outDir, { recursive: true });

const html = String.raw`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Legacy - Europe Monitor</title>
    <link rel="icon" href="/favicon.svg" />
    <style>
      :root { --bg:#f6f5f1; --paper:#fffdfa; --ink:#151515; --muted:#6d6a63; --line:#dedbd2; --brand:#203764; --teal:#11675f; --red:#a83f39; }
      * { box-sizing: border-box; }
      body { margin:0; background:var(--bg); color:var(--ink); font-family:Inter,Segoe UI,Arial,sans-serif; }
      .shell { width:min(1480px, calc(100vw - 32px)); margin:0 auto; padding:28px 0 48px; }
      .topbar { display:flex; justify-content:space-between; gap:18px; align-items:center; padding:10px 16px; border-radius:4px; background:var(--brand); color:#fff; }
      .brand { margin:0; font-size:clamp(1.05rem,1.65vw,1.45rem); font-weight:750; text-transform:uppercase; letter-spacing:.06em; }
      .status { display:flex; flex-wrap:wrap; gap:8px; justify-content:flex-end; font-size:.78rem; }
      .pill { border:1px solid rgba(255,255,255,.35); border-radius:999px; padding:5px 9px; background:rgba(255,255,255,.12); }
      .tabs { display:flex; gap:8px; margin:24px 0; overflow-x:auto; }
      button { font:inherit; cursor:pointer; }
      .tab,.legend-button,.window-button { border:1px solid var(--line); border-radius:999px; background:#fff; color:var(--muted); min-height:34px; padding:0 12px; font-weight:650; }
      .tab { min-height:42px; padding:0 16px; }
      .tab.active { border-color:var(--ink); background:var(--ink); color:#fff; }
      .grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px; }
      .panel { min-width:0; border:1px solid var(--line); border-radius:8px; background:rgba(255,253,250,.92); box-shadow:0 18px 55px rgba(41,36,25,.08); padding:18px; }
      .wide { grid-column:1/-1; }
      .head { display:flex; justify-content:space-between; align-items:flex-start; gap:14px; margin-bottom:14px; }
      .kicker { margin:0 0 5px; color:var(--muted); font-size:.78rem; font-weight:750; text-transform:uppercase; }
      h2 { margin:0; font-size:1.18rem; }
      .window { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:6px; }
      .window-button.active { border-color:var(--teal); color:var(--teal); background:rgba(17,103,95,.1); }
      .legend { display:flex; flex-wrap:wrap; justify-content:center; gap:7px; margin:10px 0 6px; }
      .legend-button { display:inline-flex; align-items:center; gap:7px; font-size:.8rem; }
      .legend-button.hidden { opacity:.45; }
      .swatch { width:9px; height:9px; border-radius:999px; display:inline-block; }
      svg { width:100%; height:auto; min-height:280px; overflow:visible; }
      .grid-line { stroke:#dedbd2; stroke-width:1; }
      .axis-line { stroke:#bfb9aa; stroke-width:1.2; }
      .tick { fill:var(--muted); font-size:12px; }
      .line { fill:none; stroke-width:2.6; stroke-linecap:round; stroke-linejoin:round; }
      .source { margin:8px 0 0; color:var(--muted); font-size:.74rem; line-height:1.45; }
      .source a { color:var(--brand); font-weight:650; text-decoration:none; }
      .source a:hover { text-decoration:underline; }
      table { width:100%; min-width:980px; border-collapse:collapse; font-size:.9rem; }
      th { background:#123f73; color:#fff; font-size:.78rem; padding:8px 10px; text-align:left; text-transform:uppercase; }
      td { border-bottom:1px solid var(--line); padding:10px; vertical-align:top; line-height:1.42; }
      tr:nth-child(even) td { background:rgba(222,219,210,.28); }
      .table-wrap { overflow-x:auto; }
      .bias { border-radius:999px; padding:4px 8px; font-size:.76rem; font-weight:700; }
      .hawkish { background:rgba(168,63,57,.12); color:var(--red); }
      .dovish { background:rgba(17,103,95,.12); color:var(--teal); }
      .neutral { background:rgba(109,106,99,.12); color:var(--muted); }
      .footer { margin:20px 0 0; color:var(--muted); font-size:.82rem; }
      @media (max-width:940px){ .shell{width:min(100% - 20px,1480px);padding-top:16px}.topbar,.head{flex-direction:column;align-items:stretch}.status,.window{justify-content:flex-start}.grid{grid-template-columns:1fr}.panel{padding:14px} }
    </style>
  </head>
  <body>
    <main class="shell">
      <header class="topbar"><p class="brand">Legacy - Europe Monitor</p><div class="status" id="status"></div></header>
      <nav class="tabs" id="tabs"></nav>
      <section class="grid" id="content"></section>
      <p class="footer" id="footer"></p>
    </main>
    <script>
      const charts = [
        ["pmi_composite","activity","PMI Composite","Activity","Index",null,true,["pmi_ea","pmi_de","pmi_fr","pmi_es","pmi_uk","pmi_it"]],
        ["pmi_manufacturing","activity","PMI Manufacturing","Activity","Index",null,true,["pmi_mfg_ea","pmi_mfg_de","pmi_mfg_fr","pmi_mfg_es","pmi_mfg_uk","pmi_mfg_it"]],
        ["pmi_services","activity","PMI Services","Activity","Index",null,true,["pmi_srv_ea","pmi_srv_de","pmi_srv_fr","pmi_srv_es","pmi_srv_uk","pmi_srv_it"]],
        ["sentix_pmi","activity","Sentix vs PMI Composite","Sentiment","PMI","Sentix",true,["pmi_ea_sentix","sentix_ea"]],
        ["weekly_activity","activity","Weekly Activity Index","High frequency","z-score"],
        ["toll_mileage","activity","Toll Mileage","Mobility","Index"],
        ["financial_conditions","activity","Financial Conditions","Markets","z-score"],
        ["gdp","activity","GDP","National accounts","% y/y"],
        ["expected_selling_prices","inflation","Expected Selling Prices","Price pressures","Balance",null,true],
        ["wage_tracker","inflation","Wage Tracker","Wages","% y/y",null,true],
        ["regional_inflation","inflation","Regional Inflation","Countries","% y/y",null,true,["hicp_de","hicp_fr","hicp_it","hicp_es"]],
        ["hicp_headline_core","inflation","HICP","Headline and core","% y/y"],
        ["hicp_components","inflation","HICP core goods and services","Components","% y/y"]
      ].map(([id,tab,title,kicker,yLeft,yRight,wide,order]) => ({id,tab,title,kicker,yLeft,yRight,wide,order}));
      const tabs = [{id:"activity",label:"Activity Monitor"},{id:"inflation",label:"Inflation Monitor"},{id:"speakers",label:"ECB Speakers"}];
      const palette = ["#204f86","#c47a20","#11675f","#a83f39","#3f7f52","#6c5f8d","#111111","#8c7b57"];
      const windows = [{key:"all",label:"All"},{key:"10y",label:"10Y",years:10},{key:"5y",label:"5Y",years:5},{key:"2y",label:"2Y",years:2}];
      let activeTab = "activity", allRows = [], speakers = [], metadata = {}, state = new Map();

      Promise.all([text("/data/activity_series.csv"), text("/data/inflation_series.csv"), text("/data/ecb_speakers.csv"), fetch("/data/metadata.json",{cache:"no-store"}).then(r => r.ok ? r.json() : {})])
        .then(([a,i,s,m]) => { allRows = [...parseCsv(a), ...parseCsv(i)].map(seriesRow); speakers = parseCsv(s); metadata = m; render(); });

      async function text(path){ const r = await fetch(path,{cache:"no-store"}); if(!r.ok) throw new Error(path); return r.text(); }
      function parseCsv(text){ const rows=[]; let row=[], field="", q=false; for(let n=0;n<text.length;n++){ const c=text[n], nx=text[n+1]; if(q){ if(c=='"'&&nx=='"'){field+='"';n++;} else if(c=='"') q=false; else field+=c; } else if(c=='"') q=true; else if(c==","){row.push(field);field="";} else if(c=="\n"){row.push(field);rows.push(row);row=[];field="";} else if(c!="\r") field+=c; } if(field||row.length){row.push(field);rows.push(row);} const h=rows.shift()||[]; return rows.filter(r=>r.some(Boolean)).map(r=>Object.fromEntries(h.map((x,n)=>[x,r[n]||""]))); }
      function seriesRow(r){ return {...r, value:Number(r.value), time:new Date(r.date+"T00:00:00").getTime(), axis:r.axis==="right"?"right":"left"}; }
      function render(){ renderTabs(); document.getElementById("status").innerHTML = '<span class="pill">Updated: '+(metadata.last_updated||"pending")+'</span><span class="pill">'+new Set(allRows.map(r=>r.series_id)).size+' series</span>'; document.getElementById("footer").textContent = 'Data mode: '+(metadata.data_mode||"source linked")+'. Data contract: CSVs in public/data.'; const el=document.getElementById("content"); el.innerHTML=""; if(activeTab==="speakers") renderSpeakers(el); else charts.filter(c=>c.tab===activeTab).forEach(c=>renderChart(el,c)); }
      function renderTabs(){ const el=document.getElementById("tabs"); el.innerHTML=""; tabs.forEach(t=>{ const b=document.createElement("button"); b.className="tab"+(t.id===activeTab?" active":""); b.textContent=t.label; b.onclick=()=>{activeTab=t.id;render();}; el.appendChild(b); }); }
      function defaultHidden(chart){ return chart.id.startsWith("pmi_") ? (chart.order||[]).filter(id=>!id.endsWith("_ea")) : []; }
      function chartState(chart){ if(!state.has(chart.id)) state.set(chart.id,{window:"all",hidden:new Set(defaultHidden(chart))}); return state.get(chart.id); }
      function buildSeries(rows, chart){ const map=new Map(); rows.forEach(r=>{ if(!map.has(r.series_id)) map.set(r.series_id,{id:r.series_id,name:r.series_name,country:r.country,axis:r.axis,unit:r.unit,source:r.source,source_url:r.source_url,points:[]}); map.get(r.series_id).points.push(r); }); return [...map.values()].map((s,i)=>({...s,points:s.points.sort((a,b)=>a.time-b.time)})).sort((a,b)=>{ const o=chart.order||[], ai=o.indexOf(a.id), bi=o.indexOf(b.id); return ai<0&&bi<0?a.name.localeCompare(b.name):ai<0?1:bi<0?-1:ai-bi; }).map((s,i)=>({...s,color:palette[i%palette.length]})); }
      function renderChart(root, chart){ const st=chartState(chart), panel=document.createElement("article"); panel.className="panel"+(chart.wide?" wide":""); const rows=allRows.filter(r=>r.chart_id===chart.id); let series=buildSeries(rows,chart); panel.innerHTML='<div class="head"><div><p class="kicker">'+chart.kicker+'</p><h2>'+chart.title+'</h2></div><div class="window"></div></div><div class="legend"></div><div class="plot"></div><p class="source"></p>'; const win=panel.querySelector(".window"); windows.forEach(w=>{ const b=document.createElement("button"); b.className="window-button"+(st.window===w.key?" active":""); b.textContent=w.label; b.onclick=()=>{st.window=w.key;render();}; win.appendChild(b); }); const legend=panel.querySelector(".legend"); series.forEach(s=>{ const b=document.createElement("button"); b.className="legend-button"+(st.hidden.has(s.id)?" hidden":""); b.innerHTML='<span class="swatch" style="background:'+s.color+'"></span>'+s.name; b.onclick=()=>{ st.hidden.has(s.id)?st.hidden.delete(s.id):st.hidden.add(s.id); render(); }; legend.appendChild(b); }); const w=windows.find(x=>x.key===st.window); if(w?.years){ const max=Math.max(...series.flatMap(s=>s.points.map(p=>p.time))); const min=new Date(max); min.setFullYear(min.getFullYear()-w.years); series=series.map(s=>({...s,points:s.points.filter(p=>p.time>=min.getTime())})); } draw(panel.querySelector(".plot"), series.filter(s=>!st.hidden.has(s.id)), chart); const sm=new Map(); series.forEach(s=>sm.set(s.source+"|"+s.source_url,s)); panel.querySelector(".source").innerHTML='Source: '+[...sm.values()].map(s=>s.source_url?'<a target="_blank" rel="noreferrer" href="'+s.source_url+'">'+s.source+'</a>':s.source).join("; "); root.appendChild(panel); }
      function draw(root, series, chart){ const W=920,H=390,m={t:36,r:58,b:48,l:54}, iw=W-m.l-m.r, ih=H-m.t-m.b, pts=series.flatMap(s=>s.points); if(!pts.length){root.textContent="Waiting for data";return;} const tx=domain(pts.map(p=>p.time)), left=series.filter(s=>s.axis!=="right").flatMap(s=>s.points.map(p=>p.value)), right=series.filter(s=>s.axis==="right").flatMap(s=>s.points.map(p=>p.value)), ly=domain(left.length?left:right), ry=right.length?domain(right):ly; const sx=t=>m.l+(t-tx.min)/(tx.max-tx.min)*iw, sy=(v,a)=>{const d=a==="right"?ry:ly; return m.t+(1-(v-d.min)/(d.max-d.min))*ih}; let svg='<svg viewBox="0 0 '+W+' '+H+'" role="img" aria-label="'+chart.title+'">'; ticks(ly,5).forEach(t=>{const y=sy(t,"left"); svg+='<line class="grid-line" x1="'+m.l+'" x2="'+(W-m.r)+'" y1="'+y+'" y2="'+y+'"/><text class="tick" text-anchor="end" x="'+(m.l-10)+'" y="'+(y+4)+'">'+fmt(t)+'</text>';}); ticks(tx,7).forEach(t=>{const x=sx(t); svg+='<line class="grid-line" x1="'+x+'" x2="'+x+'" y1="'+m.t+'" y2="'+(H-m.b)+'"/><text class="tick" text-anchor="middle" x="'+x+'" y="'+(H-m.b+24)+'">'+new Date(t).getFullYear().toString().slice(2)+'</text>';}); svg+='<line class="axis-line" x1="'+m.l+'" x2="'+m.l+'" y1="'+m.t+'" y2="'+(H-m.b)+'"/><line class="axis-line" x1="'+m.l+'" x2="'+(W-m.r)+'" y1="'+(H-m.b)+'" y2="'+(H-m.b)+'"/><text class="tick" x="'+m.l+'" y="24">'+chart.yLeft+'</text>'; if(chart.yRight) svg+='<text class="tick" text-anchor="end" x="'+(W-m.r)+'" y="24">'+chart.yRight+'</text>'; series.forEach(s=>{ svg+='<path class="line" stroke="'+s.color+'" d="'+s.points.map((p,i)=>(i?'L':'M')+sx(p.time).toFixed(2)+','+sy(p.value,s.axis).toFixed(2)).join(' ')+'"/>'; }); root.innerHTML=svg+'</svg>'; }
      function domain(v){ let min=Math.min(...v), max=Math.max(...v); if(min===max){min-=1;max+=1;} const p=(max-min)*.12; return {min:min-p,max:max+p}; }
      function ticks(d,n){ const min=d.min??d, max=d.max, step=(max-min)/Math.max(1,n-1); return Array.from({length:n},(_,i)=>min+i*step); }
      function fmt(v){ const a=Math.abs(v), d=a>=100?0:a>=10?1:2; return v.toLocaleString("en-US",{minimumFractionDigits:d,maximumFractionDigits:d}); }
      function renderSpeakers(root){ const panel=document.createElement("article"); panel.className="panel wide"; panel.innerHTML='<div class="head"><div><p class="kicker">Communication</p><h2>ECB Speakers</h2></div></div><div class="table-wrap"><table><thead><tr><th>Date</th><th>Member</th><th>Position</th><th>Policy Comments</th><th>Bias</th><th>vs Previous</th></tr></thead><tbody>'+speakers.map(s=>'<tr><td>'+s.date+'</td><td>'+(s.source_url?'<a target="_blank" rel="noreferrer" href="'+s.source_url+'">'+s.member+' ('+s.country+')</a>':s.member+' ('+s.country+')')+'</td><td>'+s.position+'</td><td>'+s.policy_comments+'</td><td><span class="bias '+s.bias+'">'+s.bias+'</span></td><td>'+s.stance_change+'</td></tr>').join("")+'</tbody></table></div>'; root.appendChild(panel); }
    </script>
  </body>
</html>`;

await writeFile(join(outDir, "index.html"), html);
