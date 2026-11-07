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
        .init(appId: "com.demo.guide", name: "能力导览", version: "1.0.0",
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
<title>能力导览</title><style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;padding:24px;background:#f2f2f7;font-family:-apple-system,sans-serif;min-height:100vh}
@media(prefers-color-scheme:dark){body{background:#000;color:#fff}.card{background:#1c1c1e}
  .row{border-color:#2c2c2e}.row span{color:#fff}}
h1{font-size:28px;margin:0 0 6px}p.sub{font-size:13px;color:#8e8e93;margin:0 0 22px;line-height:1.6}
.card{background:#fff;border-radius:16px;padding:6px 18px;margin-bottom:16px}
.title{font-size:12px;color:#8e8e93;text-transform:uppercase;letter-spacing:.5px;padding:12px 0 4px}
.row{display:flex;justify-content:space-between;padding:11px 0;border-bottom:1px solid #f2f2f7;font-size:15px}
.row:last-child{border-bottom:none}
.row code{font-family:ui-monospace,monospace;font-size:13px;color:#0a84ff}
</style></head><body>
<h1>能力导览</h1>
<p class="sub">这些能力都由宿主提供，小程序在 manifest.json 里声明后即可通过 wx.* 调用。<br>
高危能力会触发安全模式横幅，需要你当场点「允许本次」。</p>
<div class="card"><div class="title">媒体与采集</div>
<div class="row"><span>拍照 / 选图 / 存图</span><code>camera · photo · savePhoto</code></div>
<div class="row"><span>录音 / 语音识别</span><code>microphone · speech</code></div>
<div class="row"><span>扫码 / 生成二维码</span><code>qrScan · qrGenerate</code></div>
<div class="row"><span>文字识别</span><code>ocr</code></div></div>
<div class="card"><div class="title">系统与设备</div>
<div class="row"><span>设备信息 / 电量 / 网络</span><code>deviceInfo · battery · network</code></div>
<div class="row"><span>定位 / 持续定位</span><code>location · locationWatch</code></div>
<div class="row"><span>剪贴板读写</span><code>clipboard · clipboardImage</code></div>
<div class="row"><span>震动 / 屏幕常亮 / 亮度</span><code>vibrate · screenAwake · brightness</code></div></div>
<div class="card"><div class="title">内容与协作</div>
<div class="row"><span>本地存储 / 文件</span><code>storage · files</code></div>
<div class="row"><span>多窗口联动广播</span><code>sharedbus</code></div>
<div class="row"><span>AI 问答</span><code>ai</code></div>
<div class="row"><span>Live Activity / Spotlight</span><code>liveActivity · spotlight</code></div></div>
<div class="card"><div class="title">怎么做一个</div>
<div class="row"><span>写 manifest.json + index.html</span><code>打包成 ZIP</code></div>
<div class="row"><span>在「导入」页安装</span><code>InstallPreview</code></div>
<div class="row"><span>或直接用 AI 生成</span><code>描述一句话</code></div></div>
</body></html>
"""

    // MARK: - 安装

    private static let installedKey = "kinter.demoApps.installed.v1"

    /// 首次启动安装内置示例；已装过则跳过
    @discardableResult
    static func installIfNeeded(force: Bool = false) -> Int {
        if !force && UserDefaults.standard.bool(forKey: installedKey) { return 0 }
        var installed = 0
        for demo in all {
            if AppLibrary.shared.isInstalled(demo.appId) { continue }
            guard let app = materialize(demo) else { continue }
            AppLibrary.shared.add(app)
            installed += 1
        }
        UserDefaults.standard.set(true, forKey: installedKey)
        if installed > 0 {
            NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        }
        return installed
    }

    /// 把示例内容写到 Documents/Apps/<appId>/ 并返回应用记录
    private static func materialize(_ demo: Demo) -> InstalledApp? {
        let app = InstalledApp(appId: demo.appId,
                               name: demo.name,
                               version: demo.version,
                               installedAt: Date(),
                               category: demo.category,
                               disabledCapabilities: [],
                               iconSymbol: demo.iconSymbol,
                               iconColor: demo.iconColor)
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
