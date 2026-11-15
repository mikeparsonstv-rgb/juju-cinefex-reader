(()=>{'use strict';
// JUJU Cinefex Reader: crisper text when zoomed into the printed issues (1–126).
// Their text sits in one full-page layer (img[data-dark-text]) scanned at about 2× page size. Past that,
// zooming only enlarges blur. When the zoom settles, this redraws the layer at the screen's real
// resolution and steepens the edge ramp, so letters stay sharp. Only the scan's own pixels are used,
// so no letter can change. Nothing is stored: zoom out or turn the page and it is gone.
const layer=document.querySelector('img[data-dark-text]');if(!layer)return;
const PAGE_W=layer.offsetWidth||864,PAGE_H=layer.offsetHeight||768,MAX_PIXELS=14e6;
const LO=100,HI=156;                                   // ink levels mapped to paper / full ink
const lut=new Uint8ClampedArray(256);for(let v=0;v<256;v++){const ink=255-v;lut[v]=255-Math.round(Math.min(255,Math.max(0,(ink-LO)*255/(HI-LO))))}
let canvas=null,shownWidth=0,timer=0,busy=false;
function scale(){try{const r=frameElement.getBoundingClientRect();return r.width/PAGE_W}catch{return 1}}
function clear(){if(canvas){canvas.remove();canvas=null;shownWidth=0}layer.style.visibility=''}
async function update(){
 if(busy)return;const natural=layer.naturalWidth;if(!natural||!layer.complete)return;
 let w=Math.round(PAGE_W*scale()*(devicePixelRatio||1));
 if(w<=natural*1.15){clear();return}                   // the scan already has enough detail
 const h0=Math.round(w*PAGE_H/PAGE_W);if(w*h0>MAX_PIXELS)w=Math.floor(Math.sqrt(MAX_PIXELS*PAGE_W/PAGE_H));
 if(canvas&&Math.abs(w-shownWidth)/w<.08)return;       // close enough to what is already drawn
 busy=true;
 try{
  const h=Math.round(w*PAGE_H/PAGE_W),c=document.createElement('canvas');c.width=w;c.height=h;
  const g=c.getContext('2d',{willReadFrequently:true});g.imageSmoothingEnabled=true;g.imageSmoothingQuality='high';
  g.drawImage(layer,0,0,w,h);
  const img=g.getImageData(0,0,w,h),d=img.data;
  for(let i=0;i<d.length;i+=4){d[i]=lut[d[i]];d[i+1]=lut[d[i+1]];d[i+2]=lut[d[i+2]]}
  g.putImageData(img,0,0);
  c.style.cssText=layer.style.cssText;c.style.visibility='';c.style.width=PAGE_W+'px';c.style.height=PAGE_H+'px';
  c.setAttribute('aria-hidden','true');c.dataset.jujuSharp='1';
  layer.after(c);canvas?.remove();canvas=c;shownWidth=w;layer.style.visibility='hidden';
 }catch{clear()}finally{busy=false}
}
function soon(){clearTimeout(timer);timer=setTimeout(update,220)}
// Dark mode sets a filter on the layer; keep the redrawn copy in step.
new MutationObserver(()=>{if(canvas){canvas.style.filter=layer.style.filter}}).observe(layer,{attributes:true,attributeFilter:['style']});
addEventListener('message',e=>{if(e.source===parent&&e.data&&e.data.cinefexPanMode)soon()});
addEventListener('resize',soon);
try{new ResizeObserver(soon).observe(frameElement)}catch{}
if(layer.complete&&layer.naturalWidth)soon();layer.addEventListener('load',soon);
})();
