(()=>{'use strict';
// JUJU Cinefex Reader: replaces assets/js/local-source.js. Every media URL already points at the app
// (cinefex://reader/__ia/…), which serves it from the library or downloads it, so there is no folder to connect.
const state={connected:true,needsPermission:false,name:'JUJU Cinefex Library'};
const native=m=>{try{webkit.messageHandlers.juju.postMessage(m)}catch{}};
const ours=u=>typeof u==='string'&&u.startsWith('cinefex://reader/');
const openLibrary=async()=>native({action:'library'});
async function resolve(url){if(!ours(url))return null;try{const r=await fetch(url);return r.ok?await r.blob():null}catch{return null}}
function image(im,url){im.dataset.readerSrc=url||'';if(!url){im.removeAttribute('src');return}if(!im.dataset.jujuWatch){im.dataset.jujuWatch='1';im.addEventListener('error',()=>{if(im.dataset.readerSrc?.includes('/__local/')){im.alt='Image unavailable'}})}if(im.getAttribute('src')!==url)im.src=url;}
function releaseImage(){}
window.CinefexSources={ready:Promise.resolve(),choose:openLibrary,connect:openLibrary,connectFiles:openLibrary,reconnect:openLibrary,forget:openLibrary,refresh:openLibrary,resolve,image,releaseImage,status:()=>({...state}),supported:true,persistent:true};
addEventListener('message',e=>{const d=e.data;if(d&&d.cinefexResolveMedia&&e.source)e.source.postMessage({cinefexResolvedMedia:d.cinefexResolveMedia,entries:[]},'*')});
const m=location.pathname.match(/\/issues\/(\d+)\/index\.html$/);if(m)native({action:'issue',issue:Number(m[1])});

// Archive button beside the info (i) button in the page header, drawn like it. Opens the app's library
// panel, which points at this button: its position is passed up through any session frames.
document.addEventListener('DOMContentLoaded',()=>setTimeout(()=>{
 const info=document.getElementById('infoButton');if(!info||document.getElementById('jujuArchive'))return;
 const css=document.createElement('style');
 css.textContent='#jujuArchive{width:34px;height:34px;flex-shrink:0;display:grid;place-items:center;padding:6px;border:0;border-radius:50%;background:transparent;color:var(--ink);cursor:pointer;position:relative}#jujuArchive::before{content:"";position:absolute;inset:-5px}#jujuArchive svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round;pointer-events:none}#jujuArchive:hover{background:var(--line)}#jujuArchive:focus-visible{outline:2px solid var(--red);outline-offset:3px}';
 document.head.append(css);
 const b=document.createElement('button');b.id='jujuArchive';b.type='button';b.title='Archive library';b.setAttribute('aria-label','Archive library');
 paintArchive();
 b.onclick=()=>{const r=b.getBoundingClientRect();let x=r.left,y=r.top,w=window;
  try{while(w!==w.parent&&w.frameElement){const f=w.frameElement.getBoundingClientRect();x+=f.left;y+=f.top;w=w.parent}}catch{}
  native({action:'library',rect:[x,y,r.width,r.height]})};
 info.after(b);paintArchive();
},0));

// Install state from the app (busy, fraction, complete): the app tells the session page, which passes it to
// its frames. Busy draws a ring that fills; an incomplete library shows a download icon; complete, books.
let install=null;try{if(top!==window&&top.__jujuInstall)install=top.__jujuInstall}catch{}
const BOOKS='<rect x="4" y="4" width="4" height="16" rx=".6"/><rect x="10" y="4" width="4" height="16" rx=".6"/><path d="m15.6 5.1 3.3-.9 3.6 14.6-3.3.9z"/>';
const DOWNLOAD='<circle cx="12" cy="12" r="9"/><path d="M12 7.5v8m-3.5-3.5 3.5 3.5 3.5-3.5"/>';
function paintArchive(){const b=document.getElementById('jujuArchive');if(!b)return;const s=install;let body=BOOKS,label='Archive library';
 if(s&&s.busy){const c=56.55,f=Math.max(0,Math.min(1,s.fraction||0));label=`Installing archive, ${Math.floor(f*100)}%`;
  body=`<circle cx="12" cy="12" r="9" opacity=".25"/><circle cx="12" cy="12" r="9" stroke-dasharray="${(f*c).toFixed(2)} ${c}" transform="rotate(-90 12 12)"/>`}
 else if(s&&!s.complete){body=DOWNLOAD;label='Install the archive'}
 const html='<svg viewBox="0 0 24 24" aria-hidden="true">'+body+'</svg>';if(b.dataset.paint!==html){b.dataset.paint=html;b.innerHTML=html}
 b.title=label;b.setAttribute('aria-label',label)}
window.jujuInstall=s=>{install=s;window.__jujuInstall=s;paintArchive();for(let i=0;i<frames.length;i++)try{frames[i].postMessage({jujuInstall:s},'*')}catch{}};
addEventListener('message',e=>{if(e.source===parent&&e.data&&e.data.jujuInstall){install=e.data.jujuInstall;paintArchive()}});

// "Build all PDFs" saves into a folder with showDirectoryPicker. The Mac web view has none, so this is a
// small stand-in backed by the app (a Mac folder panel, then plain file writes), covering what pdf-batch.js uses.
const bridge=window.webkit?.messageHandlers?.jujuFS;
if(typeof showDirectoryPicker!=='function'&&bridge){
 const call=m=>bridge.postMessage(m),fail=(name,msg)=>new DOMException(msg||name,name);
 const join=(a,b)=>a?a+'/'+b:b;
 const base64=blob=>new Promise((ok,no)=>{const r=new FileReader();r.onload=()=>ok(r.result.slice(r.result.indexOf(',')+1));r.onerror=()=>no(r.error);r.readAsDataURL(blob)});
 function file(token,path,name){return{kind:'file',name,
  async getFile(){throw fail('NotSupportedError')},
  async createWritable(){let parts=[];return{
   async write(d){if(d&&d.type==='write')d=d.data;parts.push(d instanceof Blob?d:new Blob([d]))},
   async close(){const blob=new Blob(parts);parts=[];const STEP=8*1024*1024;
    for(let at=0;at===0||at<blob.size;at+=STEP)await call({op:'write',token,path,append:at>0,data:await base64(blob.slice(at,at+STEP))})},
   async abort(){parts=[]},async truncate(){},async seek(){}}}}}
 function directory(token,path,name){return{kind:'directory',name,
  async getDirectoryHandle(n,o={}){const p=join(path,n),r=await call({op:'dir',token,path:p,create:!!o.create});if(r==='missing')throw fail('NotFoundError');if(r!=='dir')throw fail('TypeMismatchError');return directory(token,p,n)},
  async getFileHandle(n,o={}){const p=join(path,n),r=await call({op:'file',token,path:p,create:!!o.create});if(r==='missing')throw fail('NotFoundError');if(r!=='file')throw fail('TypeMismatchError');return file(token,p,n)},
  async removeEntry(n){await call({op:'remove',token,path:join(path,n)})},
  async queryPermission(){return'granted'},async requestPermission(){return'granted'}}}
 window.showDirectoryPicker=async()=>{const r=await call({op:'pick'});if(!r)throw fail('AbortError','The user aborted a request.');return directory(r.token,'',r.name)};
}
})();
