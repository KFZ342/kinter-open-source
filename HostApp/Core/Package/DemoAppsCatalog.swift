import Foundation

/// 内置示例应用：首次启动时自动安装，让用户开箱就能看到"这玩意儿能干嘛"。
///
/// 内容内嵌在代码里而不是放 Resources 目录，避免资源打包方式（文件夹引用 / 扁平化）
/// 影响可用性；写入的是用户可见的 Documents/Apps，卸载后可从「设置 → 恢复示例应用」重新安装。
enum DemoAppsCatalog {

    struct Demo {
        let appId: String
        let name: String
        let version: String
        let category: String
        let iconSymbol: String
        let iconColor: String
        let html: String
    }

    static let all: [Demo] = [
        .init(appId: "com.demo.calculator", name: "计算器", version: "1.0.0",
              category: "工具", iconSymbol: "plus.forwardslash.minus", iconColor: "#FF9F0A",
              html: calculatorHTML),
        .init(appId: "com.demo.todo", name: "待办清单", version: "1.0.0",
              category: "效率", iconSymbol: "checklist", iconColor: "#30D158",
              html: todoHTML),
        .init(appId: "com.demo.stopwatch", name: "秒表", version: "1.0.0",
              category: "工具", iconSymbol: "timer", iconColor: "#0A84FF",
              html: stopwatchHTML),
        .init(appId: "com.demo.converter", name: "单位换算", version: "1.0.0",
              category: "工具", iconSymbol: "arrow.left.arrow.right", iconColor: "#BF5AF2",
              html: converterHTML),
        .init(appId: "com.demo.guide", name: "能力导览", version: "1.1.0",
              category: "学习", iconSymbol: "book", iconColor: "#64D2FF",
              html: guideHTML)
    ]

    // MARK: - 计算器

    private static let calculatorHTML = """
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>计算器</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none}
body{margin:0;padding:16px;background:#f2f2f7;font-family:-apple-system,sans-serif;min-height:100vh}
@media(prefers-color-scheme:dark){body{background:#000}.key{background:#1c1c1e;color:#fff}.display{color:#fff}}
.display{font-size:40px;font-weight:300;text-align:right;padding:24px 12px;color:#1c1c1e;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pad{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
.key{border:none;border-radius:14px;padding:20px 0;font-size:22px;background:#fff;color:#1c1c1e;
  box-shadow:0 1px 2px rgba(0,0,0,.06);font-weight:500}
.key.op{background:#ff9f0a;color:#fff}
.key.fn{color:#8e8e93}
.key.zero{grid-column:span 2}
.key:active{filter:brightness(.9)}
</style></head><body>
<div class="display" id="d">0</div>
<div class="pad">
<button class="key fn" data-k="C">C</button><button class="key fn" data-k="±">±</button>
<button class="key fn" data-k="%">%</button><button class="key op" data-k="/">÷</button>
<button class="key" data-k="7">7</button><button class="key" data-k="8">8</button>
<button class="key" data-k="9">9</button><button class="key op" data-k="*">×</button>
<button class="key" data-k="4">4</button><button class="key" data-k="5">5</button>
<button class="key" data-k="6">6</button><button class="key op" data-k="-">−</button>
<button class="key" data-k="1">1</button><button class="key" data-k="2">2</button>
<button class="key" data-k="3">3</button><button class="key op" data-k="+">+</button>
<button class="key zero" data-k="0">0</button><button class="key" data-k=".">.</button>
<button class="key op" data-k="=">=</button>
</div>
<script>
var cur='0', prev=null, op=null, fresh=true;
function show(){document.getElementById('d').textContent=cur}
function calc(a,b,o){a=parseFloat(a);b=parseFloat(b);
  if(o==='/')return b===0?'Error':a/b;
  if(o==='*')return a*b; if(o==='-')return a-b; if(o==='+')return a+b; return b}
document.querySelectorAll('.key').forEach(function(btn){
  btn.addEventListener('click',function(){
    var k=btn.dataset.k;
    if(k>='0'&&k<='9'||k==='.'){
      if(fresh){cur=(k==='.')?'0.':k;fresh=false}
      else{ if(k==='.'&&cur.indexOf('.')>=0)return; cur+=k }
    } else if(k==='C'){cur='0';prev=null;op=null;fresh=true}
    else if(k==='±'){cur=(cur.charAt(0)==='-')?cur.slice(1):'-'+cur}
    else if(k==='%'){cur=String(parseFloat(cur)/100)}
    else if(k==='='){
      if(op!==null&&prev!==null){cur=String(calc(prev,cur,op));op=null;prev=null;fresh=true}
    } else {
      if(op!==null&&prev!==null&&!fresh){cur=String(calc(prev,cur,op))}
      prev=cur;op=k;fresh=true
    }
    if(cur.length>12&&cur.indexOf('.')<0)cur=cur.slice(0,12);
    show()
  })
})
show()
</script></body></html>
"""

    // MARK: - 待办清单

    private static let todoHTML = """
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>待办清单</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;padding:20px;background:#f2f2f7;font-family:-apple-system,sans-serif;min-height:100vh}
@media(prefers-color-scheme:dark){body{background:#000;color:#fff}.item,.bar{background:#1c1c1e;color:#fff}
  .item{border-color:#2c2c2e}}
h1{font-size:26px;margin:0 0 4px}p.sub{margin:0 0 20px;font-size:13px;color:#8e8e93}
.bar{display:flex;gap:10px;background:#fff;border-radius:14px;padding:10px;margin-bottom:18px}
input{flex:1;border:none;outline:none;font-size:16px;background:transparent;color:inherit}
.bar button{border:none;border-radius:10px;padding:10px 16px;background:#0a84ff;color:#fff;font-size:15px}
.item{display:flex;align-items:center;gap:12px;background:#fff;border-radius:12px;
  padding:14px 16px;margin-bottom:8px;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.item.done span{text-decoration:line-through;color:#8e8e93}
.dot{width:22px;height:22px;border-radius:50%;border:2px solid #c7c7cc;flex:none}
.item.done .dot{background:#30d158;border-color:#30d158}
span{flex:1;font-size:16px}
.del{border:none;background:transparent;color:#ff453a;font-size:14px}
.empty{text-align:center;color:#8e8e93;margin-top:40px;font-size:14px}
</style></head><body>
<h1>待办清单</h1><p class="sub">数据保存在本机，示例演示纯前端能力</p>
<div class="bar"><input id="i" placeholder="要做点什么？"><button id="add">添加</button></div>
<div id="list"></div>
<script>
var KEY='kinter.demo.todo';
var items=JSON.parse(localStorage.getItem(KEY)||'[]');
function save(){localStorage.setItem(KEY,JSON.stringify(items));render()}
function render(){
  var box=document.getElementById('list');
  if(!items.length){box.innerHTML='<div class="empty">还没有待办，加一条试试</div>';return}
  box.innerHTML='';
  items.forEach(function(it,i){
    var row=document.createElement('div');
    row.className='item'+(it.done?' done':'');
    row.innerHTML='<div class="dot"></div><span></span><button class="del">删除</button>';
    row.querySelector('span').textContent=it.text;
    row.querySelector('.dot').onclick=function(){items[i].done=!items[i].done;save()};
    row.querySelector('.del').onclick=function(){items.splice(i,1);save()};
    box.appendChild(row)
  })
}
document.getElementById('add').onclick=function(){
  var input=document.getElementById('i');
  var t=input.value.trim(); if(!t)return;
  items.unshift({text:t,done:false}); input.value=''; save()
}
document.getElementById('i').addEventListener('keydown',function(e){
  if(e.key==='Enter')document.getElementById('add').click()
})
render()
</script></body></html>
"""

    // MARK: - 秒表

    private static let stopwatchHTML = """
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>秒表</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none}
body{margin:0;background:#000;color:#fff;font-family:-apple-system,sans-serif;
  min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:36px}
.time{font-size:52px;font-weight:200;font-variant-numeric:tabular-nums;letter-spacing:1px}
.ms{font-size:26px;color:#8e8e93}
.btns{display:flex;gap:24px}
button{width:84px;height:84px;border-radius:50%;border:2px solid #2c2c2e;background:#1c1c1e;
  color:#fff;font-size:16px}
button.go{background:#0a84ff;border-color:#0a84ff}
button.stop{background:#ff453a;border-color:#ff453a}
.laps{width:100%;max-width:320px;max-height:40vh;overflow:auto;padding:0 24px}
.lap{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #2c2c2e;
  font-size:14px;color:#8e8e93;font-variant-numeric:tabular-nums}
</style></head><body>
<div><div class="time" id="t">00:00</div><div class="ms" id="m">.00</div></div>
<div class="btns"><button id="reset">复位</button><button class="go" id="go">开始</button>
<button id="lap">分段</button></div>
<div class="laps" id="laps"></div>
<script>
var running=false,start=0,elapsed=0,timer=null,laps=[];
function fmt(ms){var m=Math.floor(ms/60000),s=Math.floor(ms%60000/1000);
  return (m<10?'0':'')+m+':'+(s<10?'0':'')+s}
function fmtMs(ms){return '.'+('0'+Math.floor(ms%1000/10)).slice(-2)}
function tick(){var ms=elapsed+(running?Date.now()-start:0);
  document.getElementById('t').textContent=fmt(ms);
  document.getElementById('m').textContent=fmtMs(ms)}
function paint(){
  var b=document.getElementById('go');
  b.textContent=running?'暂停':'开始';
  b.className=running?'stop':'go';
  var l=document.getElementById('laps');
  l.innerHTML=laps.map(function(v,i){
    return '<div class="lap"><span>分段 '+(i+1)+'</span><span>'+fmt(v)+fmtMs(v)+'</span></div>'
  }).join('')
}
document.getElementById('go').onclick=function(){
  if(running){elapsed+=Date.now()-start;running=false;clearInterval(timer)}
  else{start=Date.now();running=true;timer=setInterval(tick,30)}
  paint();tick()
}
document.getElementById('lap').onclick=function(){
  if(!running)return;
  laps.unshift(elapsed+Date.now()-start);paint()
}
document.getElementById('reset').onclick=function(){
  running=false;clearInterval(timer);elapsed=0;laps=[];paint();tick()
}
paint();tick()
</script></body></html>
"""

    // MARK: - 单位换算

    private static let converterHTML = """
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>单位换算</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;padding:20px;background:#f2f2f7;font-family:-apple-system,sans-serif;min-height:100vh}
@media(prefers-color-scheme:dark){body{background:#000;color:#fff}.card{background:#1c1c1e;color:#fff}
  select,input{color:#fff}}
h1{font-size:26px;margin:0 0 20px}
.card{background:#fff;border-radius:16px;padding:16px;margin-bottom:14px}
label{font-size:12px;color:#8e8e93;text-transform:uppercase;letter-spacing:.5px}
input,select{width:100%;border:none;outline:none;background:transparent;color:inherit;
  font-size:20px;margin-top:6px;-webkit-appearance:none}
select{font-size:15px}
.res{font-size:32px;font-weight:600;margin-top:6px}
.note{font-size:12px;color:#8e8e93;margin-top:10px;line-height:1.5}
</style></head><body>
<h1>单位换算</h1>
<div class="card"><label>类别</label><select id="kind">
<option value="len">长度</option><option value="weight">重量</option><option value="temp">温度</option>
</select></div>
<div class="card"><label>数值</label><input id="v" type="number" value="1">
<select id="from"></select></div>
<div class="card"><label>结果</label><div class="res" id="out">—</div><select id="to"></select></div>
<div class="note">纯前端示例，不联网、不申请任何权限。</div>
<script>
var UNITS={
  len:{m:1,km:1000,cm:0.01,mm:0.001,inch:0.0254,foot:0.3048,mile:1609.344},
  weight:{g:1,kg:1000,ton:1000000,lb:453.592,oz:28.3495}
};
var LABEL={m:'米',km:'千米',cm:'厘米',mm:'毫米',inch:'英寸',foot:'英尺',mile:'英里',
  g:'克',kg:'千克',ton:'吨',lb:'磅',oz:'盎司',C:'摄氏度',F:'华氏度'};
function toC(v,k){return k==='C'?v:(v-32)*5/9}
function fromC(v,k){return k==='C'?v:v*9/5+32}
function fill(){
  var kind=document.getElementById('kind').value;
  var a=document.getElementById('from'),b=document.getElementById('to');
  var keys=kind==='temp'?['C','F']:Object.keys(UNITS[kind]);
  a.innerHTML=b.innerHTML=keys.map(function(k){
    return '<option value="'+k+'">'+LABEL[k]+'</option>'}).join('');
  b.selectedIndex=Math.min(1,keys.length-1);
  convert()
}
function convert(){
  var kind=document.getElementById('kind').value;
  var v=parseFloat(document.getElementById('v').value);
  var a=document.getElementById('from').value,b=document.getElementById('to').value;
  var out=document.getElementById('out');
  if(isNaN(v)){out.textContent='—';return}
  var r;
  if(kind==='temp'){r=fromC(toC(v,a),b)}
  else{r=v*UNITS[kind][a]/UNITS[kind][b]}
  out.textContent=(Math.abs(r)>=1000?r.toFixed(1):r.toFixed(4)).replace(/0+$/,'').replace(/\\.$/,'')+' '+LABEL[b]
}
['kind','v','from','to'].forEach(function(id){
  document.getElementById(id).addEventListener('input',function(){
    if(id==='kind')fill();else convert()
  })
  document.getElementById(id).addEventListener('change',function(){
    if(id==='kind')fill();else convert()
  })
})
fill()
</script></body></html>
"""

    // MARK: - 能力导览

    private static let guideHTML = """
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>能力手册</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
:root{--bg:#fff;--fg:#1c1c1e;--2nd:#6e6e73;--3rd:#a1a1a6;--line:#e8e8ed;
  --card:#f5f5f7;--blue:#0071e3;--amber:#ff9f0a;--green:#30d158;--red:#ff453a}
@media(prefers-color-scheme:dark){:root{--bg:#000;--fg:#f5f5f7;--2nd:#a1a1a6;--line:#2c2c2e;
  --card:#1c1c1e;--blue:#0a84ff;--3rd:#8e8e93}}
html,body{margin:0;background:var(--bg);color:var(--fg);
  font-family:-apple-system,"SF Pro Text","PingFang SC",sans-serif;-webkit-font-smoothing:antialiased}
.wrap{max-width:780px;margin:0 auto;padding:0 22px}
a{color:var(--blue);text-decoration:none}
h1{font-size:38px;line-height:1.12;letter-spacing:-.5px;margin:16px 0 16px;font-weight:700}
h2{font-size:25px;letter-spacing:-.4px;margin:0 0 10px;font-weight:650}
h3{font-size:15px;margin:0 0 5px;font-weight:600}
p{font-size:16px;line-height:1.6;color:var(--2nd);margin:0 0 14px}
.kicker{font-size:11px;letter-spacing:1.6px;color:var(--2nd);margin-top:34px;font-weight:600}
.lede{font-size:17px;line-height:1.55;color:var(--2nd);margin-bottom:22px}
.pill{display:inline-flex;align-items:center;gap:7px;background:var(--blue);color:#fff;
  padding:9px 18px;border-radius:22px;font-size:14px;font-weight:500}

.stack{margin:24px 0 2px}
.stack svg{width:100%;height:auto;display:block}
.fig{margin:20px 0 24px}
.shot{border-radius:16px;overflow:hidden;border:1px solid var(--line);background:var(--card);
  box-shadow:0 8px 26px rgba(0,0,0,.08)}
.shot img{width:100%;display:block}
.cap{font-size:12.5px;line-height:1.55;color:var(--2nd);margin-top:9px}
section{padding:36px 0;border-top:1px solid var(--line)}
section.first{border-top:none}
.howto{background:var(--card);border-radius:16px;padding:18px 18px 6px;margin-top:6px}
.howto p{margin-bottom:12px}
.howto b{color:var(--fg);font-weight:600}
.flow{display:grid;gap:9px;margin:18px 0 4px}
.node{background:var(--card);border-radius:12px;padding:13px 15px}
.node strong{font-size:15px;font-weight:600;display:block}
.node small{color:var(--2nd);font-size:13px;line-height:1.45;display:block;margin-top:3px}
.node.hl{background:linear-gradient(120deg,#0071e30f,#0071e324);border:1px solid #0071e33a}
.arrow{text-align:center;color:var(--3rd);font-size:13px}
.tier{display:flex;gap:12px;align-items:flex-start;padding:15px 0;border-bottom:1px solid var(--line)}
.tier:last-child{border-bottom:none}
.badge{width:42px;height:42px;border-radius:11px;display:flex;align-items:center;justify-content:center;
  font-size:13px;font-weight:700;flex:none;color:#fff}
.b0{background:#8e8e93}.b1{background:var(--amber)}.b2{background:var(--red)}
.tier div{flex:1;min-width:0}
.tier h3{margin-bottom:3px}
.tier p{margin:0;font-size:14px;line-height:1.55}
.grid{display:grid;gap:12px;margin-top:18px}
@media(min-width:640px){.grid.two{grid-template-columns:1fr 1fr}}
.card{background:var(--card);border-radius:16px;padding:18px}
.card h3{font-size:15.5px}
.card p{font-size:14px;line-height:1.55;margin:0}
.chip{display:inline-block;font-size:11px;font-weight:600;padding:2px 7px;border-radius:6px;
  margin-left:6px;vertical-align:1px}
.c-crit{background:#ff453a1f;color:var(--red)}
.c-std{background:#ff9f0a1f;color:var(--amber)}
.c-net{background:#30d1581f;color:var(--green)}
.grp{margin:28px 0 8px;display:flex;align-items:baseline;gap:9px}
.grp h2{font-size:19px;margin:0}
.grp span{font-size:12px;color:var(--2nd)}
details{border-bottom:1px solid var(--line)}
details summary{list-style:none;display:flex;align-items:flex-start;gap:11px;padding:14px 0;cursor:pointer}
details summary::-webkit-details-marker{display:none}
details summary .txt{flex:1;min-width:0}
details summary .nm{font-size:15px;font-weight:600;display:block}
details summary .one{font-size:13px;color:var(--2nd);line-height:1.45;display:block;margin-top:2px}
details summary .lv{font-size:10.5px;font-weight:600;padding:2px 6px;border-radius:5px;flex:none;
  background:var(--card);color:var(--2nd);margin-top:2px}
.lv1{background:#ff9f0a26!important;color:var(--amber)!important}
.lv2{background:#ff453a26!important;color:var(--red)!important}
.body{padding:0 0 16px 0}
.body .line{display:flex;gap:9px;font-size:13.5px;line-height:1.55;margin-bottom:7px}
.body .k{color:var(--3rd);width:44px;flex:none;font-size:12px;padding-top:1px}
.body .v{color:var(--2nd);flex:1}
.body .v b{color:var(--fg);font-weight:600}
.body code{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:var(--blue)}
pre{background:var(--card);border-radius:12px;padding:16px;overflow:auto;
  font-family:ui-monospace,SFMono-Regular,monospace;font-size:12.5px;line-height:1.65;margin:14px 0}
pre b{color:var(--blue);font-weight:500}
.step{display:flex;gap:14px;align-items:flex-start;padding:16px 0;border-bottom:1px solid var(--line)}
.step:last-child{border-bottom:none}
.num{width:26px;height:26px;border-radius:50%;background:var(--card);color:var(--2nd);
  font-size:13px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none}
.step p{margin:0;font-size:14px}
ul{margin:8px 0 4px;padding-left:18px}
li{font-size:14.5px;line-height:1.65;color:var(--2nd);margin-bottom:9px}
.foot{padding:30px 0 70px;color:var(--3rd);font-size:12px;line-height:1.7}
@media(min-width:700px){h1{font-size:44px}}
</style></head><body>
<div class="wrap">

<div class="kicker">KINTER 能力手册 · v1.1</div>
<h1>50 项能力，<br>每一项都讲明白</h1>
<p class="lede">相机、定位、蓝牙、健康数据、锁屏实时活动……都在这里。每一条都写清楚四件事：能干什么、会弹什么提示、被拒绝了怎么办、在什么情况下它会不好使。</p>
<a class="pill" href="#toc">☰ 直接看目录</a>

<div class="stack">
<svg viewBox="0 0 760 216" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="设备插图">
<defs>
<linearGradient id="wall" x1="0" y1="0" x2="0.6" y2="1">
<stop offset="0" stop-color="#f7ecd9"/><stop offset="45%" stop-color="#d8c3a5"/>
<stop offset="75%" stop-color="#8f7a63"/><stop offset="100%" stop-color="#54463a"/>
</linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="180%">
<feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.22"/>
</filter>
</defs>
<g filter="url(#sh)" transform="rotate(-8 168 116)">
<rect x="120" y="26" width="96" height="182" rx="17" fill="#12100f"/>
<rect x="127" y="33" width="82" height="168" rx="12" fill="url(#wall)"/>
<rect x="127" y="33" width="82" height="168" rx="12" fill="#000" opacity="0.18"/>
</g>
<g filter="url(#sh)">
<rect x="206" y="8" width="106" height="196" rx="18" fill="#12100f"/>
<rect x="213" y="15" width="92" height="182" rx="13" fill="url(#wall)"/>
<rect x="246" y="23" width="26" height="6" rx="3" fill="#12100f" opacity="0.55"/>
<text x="224" y="70" font-family="-apple-system,Helvetica,Arial,sans-serif" font-size="27" font-weight="600" fill="#fff" opacity="0.92">9:41</text>
<rect x="224" y="150" width="70" height="10" rx="5" fill="#fff" opacity="0.28"/>
<rect x="224" y="166" width="46" height="10" rx="5" fill="#fff" opacity="0.18"/>
</g>
<g filter="url(#sh)" transform="rotate(4 372 118)">
<rect x="320" y="28" width="98" height="186" rx="17" fill="#12100f"/>
<rect x="327" y="35" width="84" height="172" rx="12" fill="url(#wall)"/>
<rect x="327" y="35" width="84" height="172" rx="12" fill="#000" opacity="0.10"/>
</g>
<g filter="url(#sh)">
<rect x="436" y="52" width="176" height="146" rx="14" fill="#12100f"/>
<rect x="443" y="59" width="162" height="132" rx="9" fill="url(#wall)"/>
<rect x="443" y="59" width="162" height="132" rx="9" fill="#000" opacity="0.08"/>
<text x="456" y="96" font-family="-apple-system,Helvetica,Arial,sans-serif" font-size="20" font-weight="600" fill="#fff" opacity="0.9">9:41</text>
<rect x="456" y="150" width="120" height="9" rx="4.5" fill="#fff" opacity="0.24"/>
</g>
</svg>
</div>
</div>

<section class="first">
  <h2>这份手册怎么读</h2>
  <div class="howto">
    <p>小程序不是网页里那种"看起来很厉害但什么也做不了"的东西。<b>它真能碰你的相机、相册、位置、健康数据</b>，所以每个能力都对应一个开关，开关在你手上。</p>
    <p>下面每一项都按同一个格式讲：<b>一句话说明它是干嘛的</b> → 展开后告诉你<b>什么时候会弹系统授权框</b>、<b>拒绝之后会怎样</b>、<b>什么设备上用不了</b>。</p>
    <p>看目录时留意右侧小标签：<b>无需授权</b>的直接能用；<b>需要授权</b>的第一次会弹框；<b>需要开发者资质</b>的普通设备上会返回"不支持"。</p>
  </div>
</section>

<section>
  <h2>小程序动你的手机前，要先过五道关</h2>
  <p>你可以把它想成寄快递要过安检：不是拦你，是每一关都留了记录，出事能查、平时能拦。</p>
  <div class="flow">
    <div class="node"><strong>① 它先声明自己要什么</strong><small>小程序的 manifest 里必须写明"我要相机、我要定位"。没写的，调了也会被拦。</small></div>
    <div class="arrow">↓</div>
    <div class="node"><strong>② 按危险程度分级</strong><small>通讯录、剪贴板这类归"高危"，相机、定位归"常规"，联网归"只记录"。高危的永远只能"允许这一次"。</small></div>
    <div class="node"><strong>③ 看你在设置里有没有关掉它</strong><small>每个小程序的能力开关都在「应用管理」里，关掉的能力当场失效。</small></div>
    <div class="node hl"><strong>④ 安全模式：现场向你请示</strong><small>你没点过的敏感调用会被拦下来，屏幕顶部出橙色横幅，问你「允许本次」还是「以后都允许」。</small></div>
    <div class="node"><strong>⑤ 系统权限 + 全程留痕</strong><small>最后一步才轮到 iOS 自己的授权框。每次调用都写进隐私记录，随时可查。</small></div>
    <div class="arrow">↓</div>
    <div class="node"><strong>结果回到小程序</strong><small>成功就拿到数据，被拒就拿到明确的错误原因——不是静默失败，也不会假装成功给你假数据。</small></div>
  </div>
</section>

<section>
  <h2>三种授权等级，区别到底在哪</h2>
  <p>等级决定"会不会打扰你"；安全模式的档位决定"要不要你点头"。</p>
  <div class="tier"><span class="badge b0">L0</span><div>
    <h3>不用授权，随叫随到</h3>
    <p>设备信息、电量、屏幕亮度、震动、本地存储、剪贴板、二维码生成、文字转语音、生成 PDF、打印、分享。这些不碰隐私硬件，调用时不会弹任何框。</p></div></div>
  <div class="tier"><span class="badge b1">L1</span><div>
    <h3>第一次会弹系统框</h3>
    <p>相机、相册、定位、通讯录、日历、提醒事项、通知、蓝牙、FaceID、语音识别。弹框里写着 App 名字和用途，<b>选"不允许"之后它就拿不到数据</b>，你还能在「设置 → Kinter」里随时改回来。</p></div></div>
  <div class="tier"><span class="badge b2">L2</span><div>
    <h3>要开发者资质，普通设备用不了</h3>
    <p>健康步数、锁屏实时活动。这类能力需要额外的开发者权限（entitlement），自己签名的包通常没有。没有时它会老实返回"不支持"，<b>不会崩、不会卡住</b>。</p></div></div>
  <div class="grid two">
    <div class="card"><h3>高危 <span class="chip c-crit">被拦时出橙色横幅</span></h3>
      <p>通讯录、健康数据、麦克风、语音识别、录像、剪贴板文字与图片、陀螺仪、日历、提醒事项。默认拒绝，<b>只能"允许本次"</b>，系统不提供"以后都允许"这个选项，因为一旦泄露收不回来。</p></div>
    <div class="card"><h3>常规 <span class="chip c-std">可记住你的选择</span></h3>
      <p>相机、相册、保存到相册、定位、蓝牙、蓝牙扫描。默认拒绝，但你可以选"以后都允许"，适合相机这种天天要用的。</p></div>
    <div class="card"><h3>联网 <span class="chip c-net">放行只记录</span></h3>
      <p>HTTP、文件上传、WebSocket。正常联网不打扰你，只写进隐私记录。但<b>如果刚刚读过你的剪贴板或通讯录，5 秒内又往外发数据</b>，就会被判定为可疑并直接拦下。</p></div>
    <div class="card"><h3>被拦了会看到什么</h3>
      <p>屏幕顶部一条橙色横幅，写明是哪个小程序、想用哪个能力。点"允许本次"只放行这一次；再点一次会再问一次，不会变成永久授权。</p></div>
  </div>
</section>

<section>
  <h2>拦截之后，你会看到什么</h2>
  <p>被拦下来不会静默失败。屏幕顶部会滑下一张橙色卡片，写着「某某小程序想使用相机」，下面并排放着按钮——<b>点哪个才算数，卡片不会自己消失</b>。</p>
  <div class="grid two">
    <div class="card"><h3>「允许本次」</h3><p>只放行这一次，用完立即失效。同一个能力再调用会再问你一遍。高危能力只提供这个选项，没有永久授权。</p></div>
    <div class="card"><h3>「以后都允许」</h3><p>记住你的选择，以后不再打扰。只对相机、定位、蓝牙这类常规档开放。</p></div>
  </div>
  <div class="fig"><div class="shot"><img src="data:image/jpeg;base64,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nvvvvvvvvvvvvvvvvvvvvvutvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvsssssssssssssssssssssssssssssssssssssssssssssssssvvunJAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEHBAvrgggggggggggggggggggggggggggggggggggggggggggggggggrvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvgqvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvtvukAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGJMIvqhHPHLDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDKKNCvqhAKJFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAvukAMIMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIDvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvrhvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvtPMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMEvrkIAJAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAvrvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvnvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv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mImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImImIiCvH/sei1htaEQDlgCRebsDX9/Jbsj629r+oIRAX4eNZ0/f6PMugXQ0PE7zZ+T8P/9k=" alt="设置页"></div>
    <div class="cap">开关就在「设置 → 安全模式」。它下面那行「App 隐私记录」，是拦截日志的入口。</div></div>
  <div class="fig"><div class="shot"><img src="data:image/jpeg;base64,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/wAF2jVMH55Mf0d79jIJWOOYjPB4BQ4dnv8AG9XXZRL5xNpeSdsr1IosrtmPDfhJkn4kjJkvm3E9smu4YqTURMMlHEEMsY2XCnh4LYcLacTWizCK7Ow1r/5fG9XXZRjcjTA0xcvT6eoXqNfVauuyjJmbmScLF3H0+nqF6jX1WrrspEcLBrc505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050tDhSi1quHf1OrrsojQRtzJbnIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQHIDkByA5AcgOQGP+yVQQjjzd9Tq67KMs8I09RCaZqvT1DRaySM/T+RBWq9Tq67KMasTDFr7+od+oyBlOiRF2Xp2s9h6uvFu+p1dc3yNuDyf0asooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooro8n9Gooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooag8n8n15PrspN2pNAp6sorhu8EsNc39jGQtexf7TNSuQDWGP50G4WpWlmdsX+ENtnDwqS2ZCVGrdmLS/xRoYifc2zuKfIY0JNbKzVxTeDW1tCqamb9fGtXXZRTlXE7oZCXZzM0a2/yMqOnW0nfzkOs0axLE2nrsd5yBKY14z9iWqExMyJfwWTntOt4TWmNX5HpE1/kp/CZaEkl9kJOCs1ai3T7vjWrrsp4sRjhJA0YbJ9ydS7iSJmmGJKvcNSo55E6k/jmrrsohjZMSp4ZEz6ANCeQyYsccBo28WLug5Na8HiJRT45q67L0aNPEszVsbPkOrrsvSeNbilINu/IdXXZfkmrrso1iitmZiIga+AJS8Tac+wI5wuQYqURtdjV12URkJ7/AYTNJV6+wNIqTnTV12X5Jq67L0TOPWY/wCjuMHiJvNTkhho32GdXNnvh6zucjscJLrqf9hpczweMdMRo85mSdXnv/2frMR9oYSNuY/tsLiD11PKM/4O3v37/wDZGF1+t1fJ9eT+ndptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNptNo6Hk/k+eT65L8jao8n12UW9JJLi4i4ZNy9k3/Zj/sRiEuT0HlGixLtdfsPXjFXO5qN6HVarGrh8e1ddlMiHVqOCFyJRSJX9D9O2F6Ul98hyUJbpY5YzEVX2od4leLRCGmVXCzWXx7V12X29tJVs762xHpt6Q3n9xGQb9w1ddl9tbSVuJCVg3yGtb9TMX4mIcU7nt2rrsvtj0+Ixphp/hJtOpxow2zff23V12X2tDmRIoNGT+TGPD+/bNXXZfa6v7n0JhrEZ/YRlf3kNuYsnqMZ+6voajOQjLT9r1ddl9qSxySo5+Y3eqFnslM2r7/VlvyXb6Mdu69r1ddl9q3wn0UXzybfWiYnimeFcuu+E9r1ddl9qfHef0QjRT+CPcqdcsROpP2rV12X2r9Lrkb/AMP7r+j9D2rV12X2rC3F9HldfweEXVILuxZe1auuy+1flz6It6mP1mPKQ/NTd6/n72vV12X2pqqPIcx06rB1CVTp/b6adiO2VyX0VXzybe16uuy+14Adzb6cBviGi22I+z+I16HkVwb+hyly1fgRITJe16uuy+2YcY8/H8aymtiI5tm/bNXXZfbGqox9Lv6P4Y5d32MGYtn7a1ddl9uxdqdg7S+BjGLdfRmlu8BCxp4RJKS8e3avc9aTWKo8x+M4YyJbL3F5P5Nv/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP3Q8n8nzyfyfYJpvAT1Y7SQsu1x+Sr4rWK5RuWdgt+WYLsj/rdvk36n+2f/2gAMAwEAAgADAAAAEAMMLMDPAOAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAFNIAAAAAAAAAAAAAAAAAAAADjjjjjjjjjkjDLAAAAAAAAAAAAAAAAAAABBGwAAAAAAAAAAAAAAEsqnghkkggomlT9KAAAAAAAAAAAAAAAAAAABDDCAAAAAAAAAAAAAAAAggggggggqCBBKAAAAAAAAAAAAAAAAAAGMMMMMMMMMMMMMMMMMMMMMMJIFJCMMAAMMMMMMMMMMMMMMMMNNLALOMLDDDDDDDDDDDDDDDDDDDLDDPHDDDDDDDDDDDDDDDDDDDDCAFPCgAAAAAAACAAAAAAAAAAAAAAACgAAAAAAAAAAAAAAACgAAAAAAEjqgAAAAAAALAAAAAAAAAAAAAABBDAAAAAAAAAAAAAAGYwAAAAAAAsvgAAAAAAAAAAAAAAAAAAAAAAEEIAAAAAAAAAAAAAAIIAAAAAAAEvvpjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjgvrhCCCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJvqtIMAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFvqh/vvvvvvvvvvvvvvvvvvvvvvrvvvvvvvvvvvriAAAAAAAAAABFvqgAggggggggggiggggggggggggigggggggggggiAAAAAAAAAAAFvvgAAAAAAAAAAAMAAAAAAAAAAAAIAAAAAAAAAAEAAAAAAAAAAAAEvvpjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjnivrgBCCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJvqsBFEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFvqsOIIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFvqkIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFvqugAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJgAAAAAAAAAAAAAAB1frhDDAAAAAAAAAAAAAAACAAAAAAAAAAAAABDBAAAAAAAAAAAAAAFvuhDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDIvuqggggggggggggggggggggggggggggggggggggggggggggggggqvumBOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFvqgAAAAAAAAAAAAAAAAAAAAAA0cQQwAAAAAAAAAAAAAAAAAAAAAFvqgA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" alt="App 隐私记录"></div>
    <div class="cap">记录页顶部三个数并排：总调用、敏感能力、已拦截。往下是能力分布、时间轴（<b>红点就是被拦的那几次</b>）和占比环图。</div></div>
  <p>点完「允许本次」之后，刚才那次调用已经失败了，<b>得回小程序里再操作一次才会真正放行</b>。这是故意的：一次授权只换一次调用，不会被偷偷复用。</p>
</section>

<section id="toc">
  <h2>能力目录</h2>
  <p>点开任意一项，会看到它<b>什么时候弹框、拒绝后怎样、什么情况用不了</b>。星号标记的是很多人第一次用会踩坑的地方。</p>
  <div class="fig"><div class="shot"><img src="data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHCAkIBgoJCAkMCwoMDxoRDw4ODx8WGBMaJSEnJiQhJCMpLjsyKSw4LCMkM0Y0OD0/QkNCKDFITUhATTtBQj//2wBDAQsMDA8NDx4RER4/KiQqPz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz8/Pz//wgARCAI5AzQDASIAAhEBAxEB/8QAGwABAQEBAQEBAQAAAAAAAAAAAAIDAQQFBgf/xAAYAQEBAQEBAAAAAAAAAAAAAAAAAQIDBP/aAAwDAQACEAMQAAAB/WO/LPpV8fQ+n34uh9Svz33DXP50H1Z+ZR9HvxOH3+/N+kJ+JR9t+Z9J90AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHO/B+kevv5z0n2fF5fwx/TdPi/ZM2oAAAAAAd4AAAAAAAAAAAACFWgWgWzGnIuDvAdOdmDVn2rQLQi0KtAtNQAAAAAAATwtAtAtAtAtAtAtAtAvuY05zoAAAAAAAAAAAAAAAAAAAi4rnwvu/Kj1VlqfP0y9h5PsfL+obc7yzyzV9uea5Poef0ebh1z+B9/5B6ZjU+iDzeL3+A8v1PF7j16Z6AAAAAAAHmnTE083pxrl8o5NDvOdI3x1jjPpVRoaAA7pnoAAAAAAAAAAAAAAAAAAAAQsQtULEc0Gd95AAHJvpn21QsQtELVCxzpAAAAAAAEqEqEqEqEqEqEqEqEqEqHOgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPOeh5djRlZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABROXqHk03HnrYZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk0zAFxodnuebTPubtDz7zt5/l/Pr9Nz8/5T9u50AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOZ5amOmzy+k658vOfqvJ67WWuVvANM9Bnrli5adY1VzzpmuZTqb8y9IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB5MPoPL074/bz08/D7uVWfxfvYY5/M+1F2stctb4BcdNeSKSK7AtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAvLsgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADDfMVzpNzR0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACps6qUAO8Uzs65kbMtDqhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhKhOe2RwDTPQ7npjc8rKtY2+f9Bjp+K+79DVfheT9VB+f+vvZscOgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA5MjXLTyl7+P2D5/t+Lz5fW9HxftXTLXLe+AaZ2VnrxM1rOcvsvn56S4Nx5Y9o80+sZ6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABPLCaGWnQ8nrSZagy1yt4B3gtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAtAuAAAEFsrKZ2dAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKJz9A8l+gea9hm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0GbQZtBm0Ga4AFxodisbbZVW1ZefM9b8N9Y/SPzPiP2Vfh/0J9cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAkozNGOp08UntY7DLXK3gGmegx2x1fFvpzettM+88Z5axEX3c8+3nk97HI9bPQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAyVwvz+nI8/sx2I+L97wc+Xk+1hvdMtct74BpnodjSSFqVKKSK5wdcFc4O9kUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkUkVlcHANM9Cuc89npeZZ6mXmzfc/NSv6d8/6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOHQHOggtzoy1yOAaZ6HMN8N58uvL6Y3mtOPT50+/kufrw1KeXh62I2Z6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGfKk08nsxPL7/N6SPi/d+Rz4vseD33TLXLfTgGmeh3LblmLUc6S85Qm+CVDnKCpFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFJFZXBwDTPQpyI0ZJdUxZq8Hlr7L5eZ9hzoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAy1yOAaZ6DPTPGs7muerw3vrj4vi/S81Pznn/V2OgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABnkx8fX3Y7eX18u+nwe+ufH+v8Tnx9v0fk/WumWuW+nANM7Kz1Ri2ZsLamPN1YbgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABx0AAOdHOgy0zOAd4OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDrg64OuDvAAAHlPU8m5ox0KAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALIj0Dz3qMK1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNRk1GTUZNczgFxodzvCZ0ebXOd868ut8r4Ptt+v4vF80/Rev8x90+gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAmTRzI2eX0nXPkZx9h4fday1yuuAaZ6DD0YzOOlM5vTNrdcz5brWGxDPhugaVlqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAZNA8nsHz/f0Z/F+9njn8v7HO2stctb4BcdNeQLQNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjRmNGY0ZjTJwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAef0QROvDs2Fc6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADynqZDWvJ7CnRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRx0cdHHRh8H9Lkcflh/8QALxAAAgIBAgYBAgUFAQEAAAAAABEBAgMEEhATICExYBQiMgUzNEBwFSNBUIAkMP/aAAgBAQABBQKIUT2iZiKjiOG6FwtkpQ31mtslKHNx7a5KXImJ4xaJ9NfBwhwo1mmm2+s8LY8d5Nbitkrj01uXpMU0LY+XE4v/AC2x5JrifKvgics0vJSs20OWvLyTW9tPp4nHFMc48prcOXJqNua2fZqjHXUWt6VqdHNs047Y9LyckY64LbMsZL/hmmpeNVES4/g99bO5tk2ybZNsm2RSMf8A8WP9gxjGMYxjGMYxjGMYxkT/AKieGTUZa5cV5yabT5edhrny3m+bJt02fLe5Txkttxxku8uS8X5t9uPLktJbzP2/LznMyXNLmyZOOe/LxfItztRqs2PNpr2yYf2Fpk71teVScsl8kxbfOyLWLWtui1tuO02JyWKz9G+DfBzIK2c9Eef9PPDLpGfH/t8uYyzpcnLnBvnBpeVcpPbJWbV5V91sEWIwyq6fbkLeZ71+Eotprzj0+CcWThmpOTD8bJzsumyXz6bHbFh/YTDiaSXjdSccza1JtbZMRFJiZxxJy/7cU+qcTFOzlo2Tu5ZWqnojz/qEIQhCEI7jsbpN0m6TdI5EIQhCEIQhC/YIQhCEIQhCEIQhCEIX/Udsim2SYmtnjckS6+xTSszOOJIqq7SO0ewR7GuiODGPhe0UpzKbrarBS8anFOONVhm3rkE+Bxwg1b+Ly4yZ9XE211Zv/SMa+R6fS26Cbqeb34W1XfDm5nVBPgXcjh2fZqq219Py1KQ7R2jJMbt3C8OmK8UjTQ8/THTBZqKzE1iYtjrMT6fMRIoniofC2KlprWKx0x7QxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxj/lS2RTuIn6dxEuPYpq5mpEfTtIhR7BAhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhC6I4MY+EzERzKE2ipa1aVrmxXtOXHUrato9agnhugiWQfiP6KkPJnxUy6y0TOiw8z5GpiKazRKNN6bEvhOSsTza8b6qInFljJ1QSW+3dBEu0FqxaJ02CTl0VKVpWMWOt+RiMdKY6+mTHeeF5lvhf8ALwzSI035/THTBZpTFlMGMyflKN9KTFrfmZIc0+30mYYuCg2VfC2ClppStI6Y4r2VjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjH/Kk2U2vtmJddxEv2OYs7Um1q1VNrIhexIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQuiOG43G4iXwcDji49cgnwRLkqay010mK61GSs31GWJ+Bim9ddq9sa38MXwvTYl8JvWDmU431FKzjyVyR0wT4Figx7ZrXz5IxUi19NivaNLhrT4+Lb8fE6Urjr6ZPmeF9777jI+Xh5a035/TBPjhERWKlpUd91Z+rHM7u6oKXb7snmn2+kzDNvCcdJnlV4301ZnHirjjpjhtNptIhexR7PHs8E+ONTWXti0tNZlmNbrMmPLpMs5cXq02iOuC3g+4oV858cZcVdN3vpZtqNPinDT09y/t4XmIt9PC87aUpOY01prl6YLeDbapWNsV8zKIs7VtMzS0zL7VvaTmTuvMwXmYKTuj0mx3ZNbTO27J7xbBkqYMOzqjhtNsm2SIRMOFBshxWIkiptgmsTM1iSIXrEcWMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjH0R7PHBjGQZLbKTqaRky6+MeWNW9NTXbsnrkE+Dd2INTTmabkPLqNNmy6yNPm/plMF+d6dN6wUv28lrWg/usmVE5cuQ0+abT0wT4P8kcN0botEzFomfT8vitVctX6tsMtG6tbWwTpq2nJ0x0wWhxtRFJia0U+ux/09a9ote9oIn6HLrLr7Ftg2xwUL2GPZ44MYyJMuSuLHbVUrlyanDjyTkiKRrsU5susw4r4slcuP1qCfEyopk3REsqayLTpM2nWWf1OLHemjphtGo1eHNz9FS2PB6Y4InhNrRO+7PEW1F5MGbf1QT4nxUhleDhxaJmLRMm+sm+rm0QTaIImJ9KnsN8LxE2+nheN1Md5wmmibZemCeipaHEVRFZiaVmJ/xWswbC8TJeJkpCj1Ca1seOqPaGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGMYxjGP+Vb5NtpuWvO2suN0qsuPYdsTO0mlZKxtNsEQo9c1OXkabFab4SPY8u6MXI1Oruaf9NHsv4l+p/8QAIREAAQQABwEBAAAAAAAAAAAAAQACEVADEBIgITFwImD/2gAIAQMBAT8B/fnpfUL69sCiuLg3tAzsGRqg+BGbmk8hNbpHkM2ZUoVr3EcJhkbYriAfUCQO13tmue0nkJjdIuJU2ZQQrcQLDBA52xaRZjI1QAjPEWHMc7Z9PKmUK1zg1AzsOQrXNnkJrdI9T//EACARAAICAgIDAQEAAAAAAAAAAAERAAIgUBJwAxAhMWD/2gAIAQIBAT8B/vx+/Y6OOndhM5QarkGvZIEBeFooNVbwcr8vdg/olQhiuzxFrrGVLGL1yfUIi1xKxEJcOtsJUIYvZgTjs6wkQ624lPgwcezc5bO0EGqvfyDyL3eUawIc49nmPXGygLwOvtVyoQ7T/8QAPRAAAQMCAwYDBAYKAwEAAAAAAQACESExAxASIjJBUWBhEzBxQoGRoSAzUnCA4QRAYnKSscHR8PEUI1CQ/9oACAEBAAY/AoFlJstRMDnlU5TIj1z23tbPMqdQg8ZQ1PaJ5latbdJ4yth4d6FUM5mCDHR8yMpmigY7J9VvDKXMaT3GWoaSGsdQozoAOkxUhEwzedZkG6xYwNU4mzSeF1oDXxpb635JssOgaojDE9qJmoQ6KgLH2KPwx7zVYAFCzDrWOSADdTiTEiYrdYTWamtawijNXJMDQS7U82hYgcH7LYpe6ZOravDjvZA4Ylow6j7VbKniMwy4WpTSg+H+KcCPesMOdihmozwMR0XqaNWs1luqPjwXh4J2uElBvhaQMRxptfJYVC1+iD2WK3RDtMBoCw9l29yVvuaurq6v03iNkAA0otWqHRUxRNdY8Qmw7DF6QVg6fb+yyVh67OaTuRmSFvM4cE7TYR7KPPVFQu37uZUiIkDc/NYQw9Evbqkgoa4t9gjORQ+krebp16dHH/JRa2ImlFqf+ogDihWQeaJGUBTCu26pziyNJM+i4Ec1SFJ+S4/BcZ5LtCd2/wDPdo4ixJom4YMYft91rYQJ3gtIOHuxNf8AOKw/FDSGDdCYdjZbFOOcDmgdiicTEkrgNqaLVPyGZQgikbMUTBqGy0N/uidgN0xDZzcwGJ4rxNTDWdMfP1TnyyvdBjopy/UaqQ46hzRCmile+ULUVYmZRFEDs05BXv2UH5Kh4jggQa8SrokmZ/8AgdZWWooDmED1JWZUIdvvPLnWCaJ36hOa7Eq26Lw/ZFE0B9XWp1HiEOLSGzIK/R3a8Ua2uO9HJPDGuNOSt7U7Xc91+j6HSe+kdJbrvgt0/wBc9gU7qLHyaCn0O6PzUUgcFujo+VGW/wC5fWOjnk4DknahPZSBTzKXQNzFVb81bh8ekK/QmK5yWqGiPxSWQgXUoCLhT1LCFahR950mgC3haUJMTQKXEAcyoZisceQcjL2iL1WyQfTqHE9380aGdqTpmLVrZYbQXzvOh5osdo1uHiUrMQsIhprtA3p/Eo2QHEbzZv8A6CaIh3tDkekIP8lxzholUv5BQqjlDhIVcJh42ThpG1vd0GsAAHALWGgOiJTv+tu1vUuow2ho7dHUy3x6TC+sb66cnReE7xFS3mUQJ5VT4mtkYEBFH0TbW5IUKoK9HWVs5t6KGj8UlirKUL9ScKKSeC0lCTb70L/Qvbp8xwzxC12l0UMwhD4DXCNqw48VjeJbU1myY2SnQcQjxIbtcJQnUcTVWWVNf7LFqE2IuZjpCrh8Vf35xdbPkmrT71s5ucG1ddFzm1PdaA3ZmYkrTp9rV7086BL7oNYIA6NvRUyoBCth6snReE7xFs28qBlKBdyVT6rj3RTJPzU/tc031VJV56LplJaFanLOQYVPwgvey4CY64g39qyhmIIkeypcZM8ul6kDymaga1oi01jJzCmeI4FrN1oCL9ey4Q4Gv+kW6tQmh4+/pO7vjCmX/wANcieScZqtHDyYaRHcfQFKELsVXjbJtqr3xuqipCnooIcct75LfzIZUFanX8yDnTIdsq/guLr9pTGGBqBubJ7PDNLVujjDDN4iVht8M7fUBzxG6dRLTAX6OX4Ld066SnlrAGxclaSIdOqlTVYMYJZBrs/n0fdbRy9mO5XD+mUolthyWl1/J/kq5xxUKnSHdDUMpDD6gr6nIjmnCKrxD5ojgFe1le1vx+FBSmjmED1HZW+9EvdYIMIfJ/YKDHYjQT3sg8bTT9mq8KH6vRFjnVA/wIPYaHp2VbPE0GHBqa0ADURphnDinYmJ9Xhk10+4BMa8apc0tH2Vhu0UdiR7pWoMO1iDitL2wZPHo6uW781uZksoAtLr+TSvyVRnHFRKochW6/JVKqqHo2zvhKjb+NciOacIqtfDzKXQjgFwoq8KZMHJTW/NUtxVFHSNQD+KUDIEBVTaX6kuUJsFReijp1+L9kJjyILhMdSuOGzU7gJTf+XpZhNM+G3jlh/ujqYfur//xAAtEAADAAICAgEDAwMFAQEAAAAAAREhUTFxEEFhYIGRIKGxwdHxMFBw4fBAgP/aAAgBAQABPyFCkJJhJDJjIirehvQSrXEKtjQbQkua+BtJVuLZ+6Th4q3wKE0HCCokiv4oRnxyUFRoV7EUYxw1C5yQStqhzD9+KryhmjTkk+Po1opWleK/DVRC3Sqy50NDsiRVu4FJ4ziSCeiY+/HrCVp4aEUCvOOJ0TCyScC8q9FzTg+Ye7wZbSNcCxTZe/ZzmRVeWlSx64pRjKU+O1/aiKpSF9BOHKP8x/8AQnZ5m2jhKumJOozcg3v8ZEPqC/MHJD1ty19uSoauLTeiq2M205tJR7+P7eGRWC1Zefqjhr8PH/eLC8oN4Sv38z9x4m1cEInc8/RamhyCvu/wIZKEUbj+7/YozJyMU1j5di7F7R8Upzv/AD6NOcRjHr8oqKontsfVJudFJZdf1LXv/aW4UVleysr2VleytibOI+X9MkjX8lbK2V7K9leyvZXsrK9lZQtv/gepZZZZZZZZZZZZZZZZZZZT/aOXitO0jXj7iQyfAR+38oxTTGhj/Vt07PXt9KlvNtumMqw2K6+UemcO58Jy2OUk2uKNtkTaLL2J7kJiufuJF8oiYefim5s/x/PhZ3HaYuUvZRyf4hnN0fwK5UW+E9fcQ5i5NVffjy1jsiSbdF3PRh5GaCWM55o9V4R39/5F6FbcaUTXhcf63oUsjeXRgW+L8BnNEinE+FzeDFhZ9/5FlMqllYyMPkThYehNlUn2jjsBln+Q2WYMxMmBGT5zuDmkGN6R1KcsnGpRtYZMl+T55kJaSlys8f7acvCleXjSZNu/0H0OMt/G+kV0hcqw2uGvkwxOL5e8/uKZ1VBy/wCES1Imu0dd+OBooxLBu9iUlFX3nn+7HNJVpzhKYEmVW8KfELiY4k/teHuPoWDaaFQbaM2yNKfh9Cxteescd4dELsQxrfnzdDXkrMiQjsKzNG5M/wDATtChJV6+w693xd58Lj/W9C5C9PuD1MIrK9n7Qc5+/oWbXO2KAmiZXHsNKjNbrRLbVttrSGKJeh6JHEXtAnO6NqfAtk1WmIkpHkJuH9CZzs5+baMpD4T/AG058KKKKKKKIjwdR8KPhR8KPhQ2lFFFFFFFFFFC/wDgM9zudzudzudzudzudzudzudzudzudxKf/qJkUnIvKE2rGYg9XBnkrS/J80K/Ub02ueUvY3rNsKlyvkiZOpExEhLhfUKUi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaGn6OPn1OonRsUVW4cTto45qX+RYRKqR9lKjEzSfOi2SHJ7v9n9NPnzxOTxibqi5E6qcxKVJInUh8TEKZY4L0Rm6tpPj5+/8AQQqsrwpTBw+USoWSa9hvjaw/zz9IWn8+KCt8oej7X9njhDri09hFso+vL588Tk8Q2WA6/lidWU12c/DUKlHAuJKEyKb8ASnV+D6PUlLjIrNoRQXBQsz2sX4EkXxsFP4FwO5w2Qvc7AZiiJ/by+fPEfH6a/DZS2Qbkpt8CY/W1/JiDYjJvt9INFFg3E2srjz6h8p5nk3shgnx5fPnj4iItEWvqB8+U59R/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A7b/lSurcKb9B7cK3UxSryafBJT2r9RrU23h2ViH9uE8ojfOIcPQRMgpwlPqFKQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQNP0cf0hOjm9IVt+jIlncM+tmKVMntjgu+WRC44fQbOIYbrglyVS3itfph8+eJw8dnxjkRwOR2tK9CtcOQn3jl8jEpHjCSRe8V/wAMjlnrKjJ+2tFWPH2InKy9lJwRS21b54T/ACCw5S/dJ9HSeGJjq+Rm0ss/pz54OfuwTvgnKfl8+eJwP2A/uwiLSORDzQyDjG8l5fJ616v3HA1ZEQ5vyiL0e3/7imVSWJPo35jT9UhtbYtEoocStdhCe3Jx6PyLgVtHsQj6ppRQS2rUPy+fPEfH6TpebWZsVDN3/AcFK5PmCTMrhMVzcbnQkcFWbg4Gkyf5i1qomsz12UUzT5ZEy/f6KRF9DWp8TXhvdafg50+b8mz5oxob8vnzx8REEX1A+fKcOp1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1Op1H/wAqICteIJQm1aolHFNUnkks9cUg+8+o3FactVhmEHhhEFlxBuknD1/BI7y239QpUggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggen6OPj4I6HTyLTDPGeRo5aUVG0lW4iptpPKIWptnj6ZfPnic/hCGXt45mQQdx6ybRnYsaf3/uZoNnrxin5Y5aXuMIVb4WP4GuyuBsHGX8ZkyoPNtvF/fH7GcyP8hj9p9HSXwyib0x9r+H588pOuYUDccp+Xz54nP4XFL0nwHtWK5Wn4mkkaqF8MH4DfTam4646LxqHBVcez4LyV35Xmje67ksURQmPo1HyatCRrKsWFl0T9kOf3Ev2TT0dgII3rRTZ8rF868vnzxOfw0mtEyYOY6b1z0Jo0eXbXpcD+Zcy/WcDGTZzn6dHyPtBMWVhNVJHhlouqb9GvsNndL0nyzh/J9FYGZCKuE8MTBv3D0/Jp5r1fo9yt8t+Xz54+Hozsdv1iLX0y+fPHxnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnRnQ+fPHxVsq2ira+oHz54jRn+h+UNOl1if8AIiyg54rFM5Me4hmWRZ/LkdE0w5E+kU7x+r9zxiaaqyvL588TlG4m9FaK4ubfTGdcy4b0cxFjKxfT9DXgnw6u3s9Jdt2rlLOAwOQbF+57fz9IPAi+KzOjQq1lQccL+x+4lXYtfuFwfCaj52POfY6O8ri+/L588Tl8JD4aqQ9pW3W37OYUqb3B6XKNP2JNSyT7CVCiURTXreBS/Dng4Xrc0R2iffs+WtjalLxPf0VTwXsniMUlayP75/14RMT4Y2Y7UHvg9Ul68vnzxHlDbyH3ghyKnyN0xwoJLNLL+R+aZfhK5vUSJzh0UnVXEcHuboRc419Kvnzx8VbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2RsjZGyNkbI2Pnzx+pHz54+KK2UNSaKksQV/I+ykcU5mH+R2WzlH/n+TFhXGP3PXoRJ8PfGX/b6afPnicniaR4c45FZnk5mN1AL3MCz38JEuJWJ3BVwHqYEFtVheRnGI1S+iVU7l1u8sL8/R7Bp5IXXJRNJVwOeV9MBfR/4/PhD24SoypXoHM/0fl8+eJyeI3ev/GKzh9jn4TIvhRpTnrkfl/Dn6QVRjN4IDE/GbT0FRYH4e/zwLg+NUMMD+2NVZt+35fPniPKJ5UvpOP09MXN8iyWESuG2OzUkmH0u0nyv0Pn6r17K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9leyvZXsr2V7K9lf/ACpJGovjhbOTJcVQfny42coU5PdKZ7X1G3uuqXSTRzYkkolgxFOFEJRRfUKfUbV/Rx8WWWUGA9HL+F8iZ9dwyca79DVxRpr6XOi9Liyv5Em4i/OHJaDmc/1FAH0wPnzxOYo6KlBt01rJoNdqHIsa4aaVf2N7Gx/gESsto6StJDcXPyx/F3HU3fNnCWf4HQa1Mejfcaw95Y6m/grop2Udrvrv6NaOWjfyc8GIWtwf2b/vjw2mN8IZodKj3gvmvfl8+eJzFJ2lXBnHCToM3o+9OXj3awsGRKaGZIbRwLEV6HErtnIdqCpzaYohqH19FSyfFeRoyXAlFEOOV/YE6w1l/sFwfCaDR2fEfoeYiXhY8vnzxMl+hPY7SZXY13h0WfbwLvpUzzWJWESJ7JGjeRRB+zdE9TbXnjBLSJ/JKMlCa/qMu53v6KaTaq4Gk+V+r98xCSSJReXz54+YtEWvqD3+iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiv/lRkRZfu/wBiDS4q5afIlZ1WMdiR0VmI/wCBlXzw/qJ2HkdfAohKiVEglJwEhJemqFIT6dxkm6JP2yaKW0q8JSLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFoi0RaItEWiLRFodYlr0qNy5oFv5ZhaR/62jj9SPk/af5Z//aAAwDAQACAAMAAAAQ+iC2OWKWa6+++++++++++++++++++++++++++++++++++++yOi2O++++++u+++++++++++64ww8W26u4wyww++++++++yyyyyyyyyiW+++++++++++++++++++8SCaq+amGu2Ci6C++++++uGsYEMm2+CC++++++++++++++++++++u+8ccGCCKsc+88e+++++++uOOOOOOOOO++++++++++++++++++++++++++OO++++++++++++++++++++++++++++y++++++++++++++++++++++++++++++++++++++++++++++++++yiyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy++6p9ZYkIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPEMOAC+qhR2cQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwWgRhC+6AAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAO++++++++++++++++++++++++++++++++++++++++++++++++++++++qqG++++++++++++++++++++++++++++++++++++++++++++++++uzz08w4wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwS+qGuCkokEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4EU3CC+uS+7AAwQgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAwQDC+++++++++++++++++++++++++++++++++++++++++++++++++++e++6+6++++++++++++++++++++++++++++++++++++++++++++++++6iSSyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy++6izjYMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEEDC+qAeF008IIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8Q0XCC+qm9sMcccsMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMK+qOOHEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAIEAC+qsWC0AIMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAkAMxjC+qhe+s8ccMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMK+qJMCIIIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC+qoy+0kgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOOwhDC+uBzjggAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAgK+u+++++++++++++++++++++++++++++++++++++++++++++++++e+++++++++++++++++++++++++++++++++++++++++++++++++++++6+uu++++++++++++++++++++++++++++++++++++++++++++++y+69HTQM4AAAAAAAAAAAAA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spqpYXas/qLoVZn5zd98bxnlaMEsYu8OY6GurKeqrUdbOsuhYdQZsuwOu9QgFW3F7M6frT8Kdsa6B1iyFkPRfwqTXVQzuPrVYvvWkMGPh5mVgC8RHSOU5Xl+dTn51OfhZyTYm1ArT8f1Ofllielz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uelz0uKmCv8Ayo2ZykClq++0aZwBWOkzF1X0KuViMKvI0C2EzSIkPRGvyMVJAKLhM53goFKCzP76RMLm0Omn+IeiparonVdLjWQra0y/+q/Ib+05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzTmnNOac05pzQayz/w1OYtFsTeocy/2ntcAWfs+DCr2h4d4qmcFoUd5Tl3FogQDqA6cxIwGqjovPbH4zqc/Opz8i3KykGL7X3mms1eIGGqQ0ZVEgN7zrdoMqQtFZL/AIaR2eNoihVrhXpl7Eookg3TazY2x1tLgGMwRQQaAYAvSJUXGgzSK5sBg6GipYaWLDvs11/lX4cLASms/C8j1AJMloL0IRvbogiCNj1+ExGKRKP2xay9ApPnU5+dTn5mOsW1Cupd6X4lIWIDfcGanErCTolkP7dJLGlFHTHaMggbdFGo6EJi9e1m8HRea02nTv7K+/sXemNMQKF0K1Kqi9NXSstwajADsUX3aNfw0uotVQSUxgKw4xCiIjVesSrmVJG/S8CtdJi9FkO7rOKhdLq+tRBL0wO9S9oGzerOkdVTViKXov8AdfOpz86nPyFAAkqwLN4QpDyvVXqzV4jU7GIq3ureofUCfcpjvmAzOFCiqY9MeSVG0UWrRB2xenQIsIDnJ06a9Yy6blLtgKWFEuYoFjQX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" alt="应用库"></div>
    <div class="cap">能力开关不在设置里，在<b>每个小程序自己的「管理」页</b>：应用库每行右侧那个滑杆图标，点进去是分类、评分、使用统计、桌面开关、权限清单和卸载。</div></div>

  <div class="grp"><h2>拍照、录音与识别</h2><span>13 项</span></div>
  <details><summary><span class="txt"><span class="nm">相机拍照</span><span class="one">让小程序拍一张照片，比如拍习题、拍发票、拍实物</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">点按钮 → 全屏相机 → 拍完照片交给小程序，它拿到的是一个文件路径。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">第一次用会问"允许 Kinter 使用相机吗"。拒绝后小程序立刻收到失败原因，不会假装拍到了。</span></div>
      <div class="line"><span class="k">注意</span><span class="v"><b>模拟器没有相机</b>，会返回"不支持"。真机第一次用建议先单独试一次，确认系统框弹出来。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">从相册选图</span><span class="one">打开系统相册挑一张图给小程序，照片不会被整体读走</span></span><span class="lv">无需弹框</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">点按钮 → 系统相册选择器 → 选一张 → 小程序拿到这张图的路径。</span></div>
      <div class="line"><span class="k">隐私</span><span class="v">这里用的是系统自带的选择器，<b>它只把"你选中的那张"交给小程序</b>，小程序看不到你其他照片，所以不弹相册授权。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">一次只返回一张（示例的实现），需要多张时得改造。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">保存图片到相册</span><span class="one">把小程序生成的图存进你的相册</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">小程序把图片数据交出去，你会在相簿里看到它。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">第一次会问"允许添加照片"，注意这里要的是<b>写入</b>权限，不是读你相册。</span></div>
      <div class="line"><span class="k">失败</span><span class="v">没给权限时返回失败，图不会出现在相簿里。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">录像</span><span class="one">录一段视频，交给小程序处理或上传</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">点按钮 → 系统录像界面 → 录完返回视频文件路径。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">相机和麦克风两项，都会弹。任一项被拒就录不了。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">属于高危档，安全模式开启时会有橙色横幅要你确认。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">语音识别</span><span class="one">说一句话，小程序直接拿到文字</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">点按钮开口说话，停下来后返回识别文本。适合做语音输入、语音记账。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">两项：语音识别授权 + 麦克风授权。少一项都不行。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">* <b>模拟器没有输入设备</b>，采样率为 0，会提前返回"不支持"而不是卡死。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">扫二维码</span><span class="one">打开相机对准码，把里面的内容给小程序</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">全屏扫码界面，识别成功立刻回调内容，不用你按快门。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">相机授权，拒绝就扫不了。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">条形码也支持，不止二维码。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">生成二维码</span><span class="one">把一段文字变成二维码图片</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">传文字进去，返回一张二维码图，可指定尺寸。做收款码、名片、分享链接都用它。</span></div>
      <div class="line"><span class="k">隐私</span><span class="v">纯本地计算，不联网。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">图片文字识别</span><span class="one">给一张图，识别出里面的文字（支持中文）</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">拍发票、拍书页、拍菜单，返回文字和置信度。适合做记账、摘录。</span></div>
      <div class="line"><span class="k">隐私</span><span class="v">识别在设备本地完成，<b>图片不会上传到任何服务器</b>。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">字太小、反光、倾斜会识别不准，这是识别模型本身的问题，不是权限问题。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">压缩图片</span><span class="one">把大图压小，省流量、上传更快</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">指定缩放比例和画质，返回压缩后的文件路径。原图不动。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">文字转语音</span><span class="one">让小程序把字念出来</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">传一段文字就朗读，支持中文音色，随时可以停。做提示音、朗读器都能用。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">静音键打开时听不到声音，这不是失败。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">播放音频</span><span class="one">放一段本地音频，比如提示音、旁白</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">播放、暂停、停止、跳到某秒都支持。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">播放音乐</span><span class="one">放本地或网络音乐，可以退到后台继续</span></span><span class="lv">无需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">支持循环、音量、查询播放状态的完整控制。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">宿主声明了后台音频，<b>锁屏或切到别的 App 后音乐不会停</b>。想省电记得主动停。</span></div>
    </div></details>
  <details><summary><span class="txt"><span class="nm">录音</span><span class="one">录一段音频存下来</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body">
      <div class="line"><span class="k">怎么用</span><span class="v">开始录音 → 停止 → 拿到文件路径和时长。</span></div>
      <div class="line"><span class="k">会弹框</span><span class="v">麦克风授权。</span></div>
      <div class="line"><span class="k">注意</span><span class="v">高危档，会走橙色横幅确认。</span></div>
    </div></details>

  <div class="grp"><h2>设备与位置</h2><span>14 项</span></div>
  <details><summary><span class="txt"><span class="nm">设备信息</span><span class="one">机型、系统版本、屏幕大小，用来适配界面</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">小程序靠它决定卡片排几列、字多大。纯本地读取。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">不含序列号等能定位到个人的硬件标识。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">电量与充电</span><span class="one">现在多少电、是不是在充电</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">电量低时提示"先充电再用"，或者做省电模式。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">网络状态</span><span class="one">现在是不是 WiFi、走没走流量</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">上传大文件前先问一句"你在用流量，确定传吗"。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">只告诉你类型，不会读你的流量账单。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">网络变化监听</span><span class="one">断网、恢复、切到流量时通知小程序</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">网络断了自动重连，恢复时刷新数据，不用你手动点重试。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">震动</span><span class="one">点按钮时给一点手感反馈</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">短震是触感引擎的"轻点"，长震是系统振动。计时、计数、确认操作都能用。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">iPad 多数没有触感引擎，只有部分机型有。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">陀螺仪</span><span class="one">知道手机现在倾斜了多少度</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">做水平仪、摇一摇、体感小游戏。返回三个角度值。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">运动与健身数据授权。高危档，会有橙色横幅。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">只取一瞬间的角度，不会持续记录你的姿态。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">蓝牙开关状态</span><span class="one">蓝牙现在开着还是关着</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">只探测状态，不列设备。用于提示"请先打开蓝牙"。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">第一次会问蓝牙授权。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">蓝牙关了或没授权，返回的是"未授权"而不是"关着"，看返回值要分清。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">扫描附近蓝牙设备</span><span class="one">找附近的手环、打印机、灯泡</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">返回附近设备的名称、标识和信号强弱，可用于配对前先看有哪些。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">蓝牙授权。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">只扫描不连接，连接协议要开发者自己做。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">面容 / 指纹验证</span><span class="one">用你的脸或指纹确认"是你本人在操作"</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">付款前、看私密内容前，先过一次身份确认。返回成功或失败。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">系统生物识别界面。这里可能出现<b>输密码的界面</b>——那是系统的兜底方式，输的是设备解锁密码，不是 Apple ID 密码。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">没有录入面容的设备、或者模拟器，会直接返回"不支持"。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">当前位置（一次）</span><span class="one">拿一次你在哪，用来算距离、找附近</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">返回经纬度和精度。做"附近的门店""离我多远"都用它。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">第一次问"允许使用你的位置吗"，选"仅本次"也可以。拒绝后可以到「设置 → Kinter → 位置」改回来。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">室内定位精度会差一些；模拟器返回的是固定的默认坐标。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">持续定位</span><span class="one">边走边更新位置，比如跑步记轨迹</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">启动后位置会不断推给小程序，你自己决定什么时候停。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">定位授权。</span></div>
    <div class="line"><span class="k">注意</span><span class="v"><b>比"当前位置"明显费电</b>，用完记得停。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">屏幕亮度</span><span class="one">调亮或调暗屏幕</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">0 到 1 之间取值。看菜谱、看图纸时可以临时调亮。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">改了就保持，<b>退出小程序不会自动恢复原来的亮度</b>。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">屏幕常亮</span><span class="one">让它别自动息屏</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">做计时器、看谱子、看图纸时打开，看完记得关。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">一直开着会明显费电。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">剪贴板</span><span class="one">读写你复制过的那段文字</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">把一段话复制走，或者直接读你刚复制的内容，省得来回切 App。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">高危档，安全模式下出橙色横幅，只能"允许本次"。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">* <b>剪贴板里常有验证码、密码、链接</b>，这是它被归为高危的原因。读完立刻联网外发的行为会被直接拦下。</span></div></div></details>

  <div class="grp"><h2>数据与联网</h2><span>10 项</span></div>
  <details><summary><span class="txt"><span class="nm">本地存储</span><span class="one">小程序自己的小记事本，关掉再开还在</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">存设置、存草稿。每个小程序各存各的，互相看不见。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">卸载小程序时一起清掉。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">自己的文件夹</span><span class="one">在小程序专属目录里存文件</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">列文件、读文件、写文件。适合存导出的表格、缓存图片。</span></div>
    <div class="line"><span class="k">安全</span><span class="v">* <b>文件名里带 ".." 想跳到别的 App 目录，会被直接拒绝</b>。它只能看见自己那一格。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">联网请求</span><span class="one">从服务器取数据、提交数据</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">GET、POST 都行，可以带自定义请求头，返回状态码和内容。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">走系统网络，<b>不会读你的浏览记录，也不代表它能随便访问内网地址</b>；返回内容是否可信要自己判断。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">WebSocket 长连接</span><span class="one">聊天、实时数据推送用这个</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">连上之后双方随时互发消息，连接状态变化会通知小程序。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">小程序退到后台连接可能被系统回收，要自己做重连。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">上传文件</span><span class="one">把本地文件发到服务器</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">选好文件、填好地址就行，返回状态码和服务器回应。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">只上传你指定的那个文件，不会顺手把别的带走。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">生成 PDF</span><span class="one">把页面变成一份 PDF，能存能发</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">出账单、出报告、出小票，返回文件路径。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">打印</span><span class="one">用 AirPrint 直接打出来</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">调起系统打印面板，选打印机、选份数，全部由系统处理。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">需要和打印机在同一个网络下。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">系统分享</span><span class="one">把内容发到微信、邮件、备忘录</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">弹出系统分享面板，你自己选发给谁。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">iPad 上这个面板必须指定弹出位置，否则会崩——这一版已经修好了。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">打开链接</span><span class="one">跳到浏览器或别的 App</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">点"去官网看看"就跳到 Safari。链接会先被校验，可疑协议不放行。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">拨号 / 短信 / 邮件</span><span class="one">一键唤起电话、信息、邮件</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">做客服电话、投诉邮件入口。唤起的是系统界面，<b>发不发由你按</b>。</span></div></div></details>

  <div class="grp"><h2>系统集成</h2><span>8 项</span></div>
  <details><summary><span class="txt"><span class="nm">通讯录</span><span class="one">读取你的联系人（最高危的一类）</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">拿姓名、电话、邮箱。做名片整理、群发前预览。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">高危档：橙色横幅 + 系统授权框，<b>只能"允许本次"，不提供永久授权</b>。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">读完立刻往外发会被组合规则拦下。不需要时就别装需要通讯录权限的小程序。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">日历日程</span><span class="one">看最近 30 天的日程</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">返回最近 30 天的事件标题和时间。做"今天有什么安排"。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">日历授权（iOS 17 会问是"完整访问"还是"仅添加"）。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">选"仅添加"之后，读日程会失败，这是系统行为。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">添加提醒事项</span><span class="one">往"提醒事项"里塞一条待办</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">写进去的内容会出现在系统提醒事项里，到点由系统提醒你。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">提醒事项授权。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">通知</span><span class="one">让小程序能给你发通知</span></span><span class="lv lv1">需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">先申请权限，通过后才能弹。示例里有一条"2 秒后弹"的演示，用来确认通道通不通。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">"允许通知吗"——横幅、角标、声音三项一起。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">拒绝后系统不会让你再问第二次，必须去「设置 → 通知」手动开。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">账号信息</span><span class="one">读当前登录的昵称和 ID</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">用于显示"你好，某某"，或者判断有没有登录。</span></div>
    <div class="line"><span class="k">隐私</span><span class="v">* <b>只给公开信息，拿不到密码，也拿不到登录令牌</b>。设置里还能一键禁止所有小程序读取。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">系统搜索索引</span><span class="one">让内容出现在 Spotlight 搜索结果里</span></span><span class="lv">无需授权</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">小程序把自己的条目交给系统搜索，搜到了点一下会跳回小程序继续看。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">每个小程序只能操作自己那批索引，不会混在一起。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">锁屏实时活动</span><span class="one">在锁屏和灵动岛显示进度</span></span><span class="lv lv2">需资质</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">做倒计时、外卖进度、比赛比分，不用一直开着 App 也能看。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">要求 iOS 16.1 以上，且系统限制同时进行的活动数量。<b>模拟器完全不支持</b>。</span></div></div></details>
  <details><summary><span class="txt"><span class="nm">步数</span><span class="one">读今天的走路步数</span></span><span class="lv lv2">需资质</span></summary>
    <div class="body"><div class="line"><span class="k">怎么用</span><span class="v">做健康打卡、步数换积分。</span></div>
    <div class="line"><span class="k">会弹框</span><span class="v">健康 App 的授权界面，逐项勾选。</span></div>
    <div class="line"><span class="k">注意</span><span class="v">* 自己签名的包通常没有健康资质，会返回"不支持"。<b>它不会因此崩掉</b>，是提前被隔离了。</span></div></div></details>
</section>

<section>
  <h2>想自己做一个</h2>
  <p>不用会 Swift。三样东西：一份说明、一个网页、一个 ZIP。</p>
  <div class="step"><span class="num">1</span><div><h3>写一份 manifest，说明自己是谁</h3>
    <p>里面写清楚名字、版本、有哪几页、<b>要用哪些能力</b>。没写的能力，调了也会被拦——这是防盗用的设计。</p></div></div>
  <pre>{
  "<b>appId</b>": "com.your.app",     ← 全局唯一，装了就不该改
  "<b>name</b>": "我的小程序",
  "<b>version</b>": "1.0.0",
  "<b>pages</b>": ["index"],
  "<b>iconSymbol</b>": "sparkles",     ← 图标用系统图标，不用准备图片
  "<b>iconColor</b>": "#FF9F0A",       ← 底色
  "<b>capabilities</b>": ["camera", "vibrate", "storage"]
}</pre>
  <div class="step"><span class="num">2</span><div><h3>写界面，直接调能力</h3>
    <p>调能力的脚本由宿主自动注入，不用自己引。<b>每个调用都会告诉你成功还是失败</b>，别假设一定成功。</p></div></div>
  <pre>wx.camera.chooseImage({ count: 1 }, function (r) {
  if (r.ok) show(r.path);          // 拿到了照片路径
  else show("没拿到：" + r.reason); // 被拒、被拦、不支持，都有原因
});</pre>
  <div class="step"><span class="num">3</span><div><h3>打包成 ZIP，导入安装</h3>
    <p>ZIP 根目录放 manifest 和 index.html，其他文件随意。去「导入」页选这个 ZIP，<b>会先给你看它要哪些权限</b>，你确认后才装。</p></div></div>
  <div class="grid two">
    <div class="card"><h3>装完之后</h3><p>它会出现在应用库，首次启动自动装好的 5 个示例也在那儿。可以收藏、打分、看打开次数和用了多久。</p></div>
    <div class="card"><h3>装错了怎么改</h3><p>应用管理页可以改分类、关掉某个能力、卸载。数据目录和代码目录是分开的，<b>卸载不会顺手删你的数据</b>。</p></div>
  </div>
</section>

<section>
  <h2>出问题的时候看哪里</h2>
  <p>运行页导航栏那个仪表盘图标，是给调试用的 DevHUD。</p>
  <div class="grid two">
    <div class="card"><h3>FPS</h3><p>界面卡不卡。掉到 30 以下通常是页面自己的动画太重，不是权限问题。</p></div>
    <div class="card"><h3>桥接调用</h3><p>调了几次能力、失败几次。<b>失败数一直涨，说明是权限或参数的问题</b>，去隐私记录里看具体哪一条被拦。</p></div>
    <div class="card"><h3>JS 错误</h3><p>小程序自己代码报错的位置。这里的问题跟宿主无关。</p></div>
    <div class="card"><h3>一键请求权限</h3><p>把系统权限一次性走一遍，面板上显示"请求中 3/13"。<b>中间可能让你输设备密码</b>，那是面容识别的兜底，不是 Apple ID。</p></div>
  </div>
</section>

<section>
  <h2>这些限制，先告诉你</h2>
  <p>不是 bug，是这一版确实还没做到的。</p>
  <ul>
    <li><b>有 6 个模块不走安全检查：</b>页面跳转、应用商店、登录、应用管理、弹窗、权限设置。它们直接连到系统，安全模式的横幅管不到。这是已知缺口。</li>
    <li><b>组合规则只看 5 秒：</b>读完剪贴板等 6 秒再联网，就不会被判定为可疑。想彻底可靠，得改成按行为链追踪。</li>
    <li><b>网页没有导航限制：</b>如果小程序加载了远程网页，那个网页也能向桥发消息。别用来源不明的远程页面。</li>
    <li><b>模拟器上很多能力用不了：</b>相机、面容、语音识别、实时活动都会返回"不支持"，这是预期行为，不是装坏了。</li>
  </ul>
</section>

<div class="foot">Kinter · 能力手册 v1.1<br>本页完全离线，不含任何网络请求。</div>
</div></body></html>
"""

    // MARK: - 安装

    private static let installedKey = "kinter.demoApps.installed.v1"

    /// 首次启动安装内置示例；已装过的按版本差异升级（保留收藏、评分、使用统计）
    @discardableResult
    static func installIfNeeded(force: Bool = false) -> Int {
        var changed = 0
        for demo in all {
            if let existing = AppLibrary.shared.app(id: demo.appId) {
                guard force || existing.version != demo.version else { continue }
                guard let upgraded = materialize(demo, base: existing) else { continue }
                AppLibrary.shared.update(upgraded)
                changed += 1
                continue
            }
            guard let app = materialize(demo) else { continue }
            AppLibrary.shared.add(app)
            changed += 1
        }
        UserDefaults.standard.set(true, forKey: installedKey)
        if changed > 0 {
            NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        }
        return changed
    }

    /// 把示例内容写到 Documents/Apps/<appId>/ 并返回应用记录
    private static func materialize(_ demo: Demo, base: InstalledApp? = nil) -> InstalledApp? {
        // 升级时保留用户在旧版本里积累的收藏、评分、使用统计与能力禁用
        let app: InstalledApp
        if let base = base {
            app = InstalledApp(appId: demo.appId,
                               name: demo.name,
                               version: demo.version,
                               installedAt: base.installedAt,
                               category: demo.category,
                               disabledCapabilities: base.disabledCapabilities,
                               iconFileName: base.iconFileName,
                               isAIGenerated: base.isAIGenerated,
                               generationPrompt: base.generationPrompt,
                               price: base.price,
                               paid: base.paid,
                               isFavorite: base.isFavorite,
                               rating: base.rating,
                               launchCount: base.launchCount,
                               lastOpenedAt: base.lastOpenedAt,
                               totalUsageSeconds: base.totalUsageSeconds,
                               iconSymbol: demo.iconSymbol,
                               iconColor: demo.iconColor)
        } else {
            app = InstalledApp(appId: demo.appId,
                               name: demo.name,
                               version: demo.version,
                               installedAt: Date(),
                               category: demo.category,
                               disabledCapabilities: [],
                               iconSymbol: demo.iconSymbol,
                               iconColor: demo.iconColor)
        }
        let dir = app.directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "appId": demo.appId,
                "version": demo.version,
                "name": demo.name,
                "minHostVersion": "1.0.0",
                "pages": ["index"],
                "iconSymbol": demo.iconSymbol,
                "iconColor": demo.iconColor
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent("manifest.json"))
            try demo.html.write(to: dir.appendingPathComponent("index.html"),
                                atomically: true, encoding: .utf8)
            app.ensureDataDirectory()
            return app
        } catch {
            return nil
        }
    }
}
