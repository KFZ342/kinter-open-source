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
.stack{height:146px;margin:26px 0 6px;position:relative}
.dev{position:absolute;top:0;border-radius:14px;overflow:hidden;
  box-shadow:0 10px 26px rgba(0,0,0,.16);border:1.5px solid #1c1c1e14}
.dev i{display:block;position:absolute;inset:10px 6px 6px;border-radius:7px;
  background:linear-gradient(160deg,#e9d9c6,#c9b49c 40%,#8d7a68 70%,#5c4f45)}
.dev b{position:absolute;left:16px;top:14px;font-size:25px;font-weight:600;color:#fff;
  text-shadow:0 1px 6px rgba(0,0,0,.35);letter-spacing:-1px}
.d1{left:2%;width:26%;height:82%;transform:rotate(-3deg)}
.d2{left:26%;width:29%;height:96%;z-index:3}
.d3{left:52%;width:27%;height:88%;transform:rotate(2deg)}
.d4{left:74%;width:24%;height:76%;transform:rotate(-2deg)}
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
@media(min-width:700px){h1{font-size:44px}.stack{height:180px}}
</style></head><body>
<div class="wrap">

<div class="kicker">KINTER 能力手册 · v1.1</div>
<h1>50 项能力，<br>每一项都讲明白</h1>
<p class="lede">相机、定位、蓝牙、健康数据、锁屏实时活动……都在这里。每一条都写清楚四件事：能干什么、会弹什么提示、被拒绝了怎么办、在什么情况下它会不好使。</p>
<a class="pill" href="#toc">☰ 直接看目录</a>

<div class="stack">
  <div class="dev d1"><i></i></div>
  <div class="dev d2"><i></i><b>9:41</b></div>
  <div class="dev d3"><i></i></div>
  <div class="dev d4"><i></i></div>
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

<section id="toc">
  <h2>能力目录</h2>
  <p>点开任意一项，会看到它<b>什么时候弹框、拒绝后怎样、什么情况用不了</b>。星号标记的是很多人第一次用会踩坑的地方。</p>

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
