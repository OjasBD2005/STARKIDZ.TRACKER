/* ============================================================
   STAR Kidz — CROC LOADER
   A branded 3D crocs/clog loading splash shown when a user
   enters the portal. Original SVG artwork (not product photos),
   cycling through STAR Kidz colourways.

   Usage:
     <script src="croc-loader.js" data-auto="true"></script>   // auto show on page entry, auto hide when ready
     <script src="croc-loader.js"></script>                    // manual: CrocLoader.show('msg') / CrocLoader.hide()

   API:  window.CrocLoader.show(message?)   window.CrocLoader.hide()
   ============================================================ */
(function(){
  if(window.CrocLoader) return;

  // honour the script tag's data-auto + optional data-min (ms minimum display)
  var me = document.currentScript;
  var AUTO = !!(me && me.dataset && me.dataset.auto === 'true');
  var MIN  = (me && me.dataset && +me.dataset.min) || 1900;

  // STAR Kidz colourways  [body, sole, strap, holes]  (drawn fallback only)
  var WAYS = [
    {b:'#f2f1ec', s:'#d8c3a0', t:'#d8c3a0', n:'rgba(0,0,0,.14)', lbl:'White · Tan'},
    {b:'#d7dbe0', s:'#1f2a44', t:'#1f2a44', n:'rgba(0,0,0,.18)', lbl:'Light Grey · Navy'},
    {b:'#202938', s:'#ffffff', t:'#ffffff', n:'rgba(255,255,255,.16)', lbl:'Black · White'},
    {b:'#bfe6cb', s:'#ffffff', t:'#16233a', n:'rgba(0,0,0,.13)', lbl:'Mint Sport'}
  ];
  // Drop a real product photo named one of these into the project folder and
  // the loader auto-swaps the drawn croc for the actual product image.
  var PROD_NAMES = ['product-croc.png','product-croc.jpg','product-croc.jpeg','product-croc.webp'];

  var CSS = `
  .cl-overlay{position:fixed;inset:0;z-index:99999;display:none;place-items:center;
    background:radial-gradient(120% 120% at 50% 18%,#16224a 0%,#0b1430 48%,#070d1f 100%);
    overflow:hidden;font-family:'Manrope',system-ui,-apple-system,sans-serif}
  .cl-overlay.cl-show{display:grid;animation:clFade .35s ease}
  .cl-overlay.cl-hide{animation:clOut .45s ease forwards}
  @keyframes clFade{from{opacity:0}to{opacity:1}}
  @keyframes clOut{to{opacity:0;visibility:hidden}}

  /* soft depth orbs + perspective floor for the 3D feel */
  .cl-orb{position:absolute;border-radius:50%;filter:blur(80px);opacity:.55}
  .cl-orb.a{width:460px;height:460px;background:#3358e0;top:-14%;left:-8%}
  .cl-orb.b{width:380px;height:380px;background:#e11d2b;bottom:-16%;right:-8%}
  .cl-orb.c{width:300px;height:300px;background:#22c5a8;top:52%;left:14%;opacity:.35}
  .cl-floor{position:absolute;left:-60%;right:-60%;bottom:-10%;height:60%;
    background-image:linear-gradient(rgba(255,255,255,.07) 1.5px,transparent 1.5px),linear-gradient(90deg,rgba(255,255,255,.07) 1.5px,transparent 1.5px);
    background-size:46px 46px;transform:perspective(560px) rotateX(64deg);transform-origin:top center;
    animation:clFloor 13s linear infinite;
    -webkit-mask-image:linear-gradient(to bottom,transparent,#000 30%,#000 80%,transparent);
            mask-image:linear-gradient(to bottom,transparent,#000 30%,#000 80%,transparent)}
  @keyframes clFloor{to{background-position:0 46px,0 0}}

  /* drifting background footwear silhouettes */
  .cl-bg{position:absolute;inset:0;pointer-events:none;overflow:hidden}
  .cl-ghost{position:absolute;opacity:.10;animation:clDrift 9s ease-in-out infinite alternate}
  .cl-ghost svg{display:block;width:100%;height:auto}
  .cl-ghost.g1{width:150px;top:16%;left:8%;animation-duration:8s}
  .cl-ghost.g2{width:110px;bottom:18%;right:10%;animation-duration:10s;animation-delay:-3s}
  .cl-ghost.g3{width:84px;top:24%;right:22%;animation-duration:11s;animation-delay:-5s}
  .cl-ghost.g4{width:96px;bottom:24%;left:20%;animation-duration:9.5s;animation-delay:-2s}
  @keyframes clDrift{from{transform:translateY(-16px) rotate(-6deg)}to{transform:translateY(18px) rotate(6deg)}}

  .cl-center{position:relative;z-index:2;text-align:center;padding:24px}

  /* 3D stage */
  .cl-stage{width:300px;height:200px;margin:0 auto;position:relative;perspective:760px}
  .cl-tilt{position:absolute;inset:0;transform-style:preserve-3d;animation:clTilt 3.4s ease-in-out infinite}
  @keyframes clTilt{0%,100%{transform:rotateY(-13deg) rotateX(4deg)}50%{transform:rotateY(13deg) rotateX(0deg)}}

  .cl-croc{position:absolute;left:50%;top:42%;width:268px;margin-left:-134px;
    transform-origin:50% 88%;animation:clHop 1.15s cubic-bezier(.5,.05,.4,1) infinite;
    filter:drop-shadow(0 16px 14px rgba(0,0,0,.45))}
  .cl-croc svg{display:block;width:100%;height:auto}
  .cl-croc path,.cl-croc ellipse,.cl-croc circle{transition:fill .55s ease,stroke .55s ease}
  /* real product photo (used when product-croc.* is present) */
  .cl-prod{display:none;width:100%;height:auto;max-height:210px;object-fit:contain;border-radius:14px}
  .cl-photo .cl-tilt{animation:none!important;transform:none!important}
  .cl-photo .cl-croc{animation:clFloat 2.6s ease-in-out infinite!important}
  @keyframes clFloat{0%,100%{transform:translateY(0)}50%{transform:translateY(-16px)}}
  /* photo mode: clean near-black backdrop so a black-bg product shot blends seamlessly */
  .cl-overlay.cl-photo{background:radial-gradient(120% 120% at 50% 26%,#0b0b10 0%,#000 72%)}
  .cl-photo .cl-floor,.cl-photo .cl-orb,.cl-photo .cl-bg{display:none}
  .cl-photo .cl-prod{border-radius:0;max-height:272px}
  @keyframes clHop{0%{transform:translateY(0) rotate(-3deg)}
    45%{transform:translateY(-26px) rotate(2deg)}
    60%{transform:translateY(-26px) rotate(3deg)}
    100%{transform:translateY(0) rotate(-3deg)}}

  .cl-shadow{position:absolute;left:50%;bottom:6%;width:170px;height:26px;margin-left:-85px;border-radius:50%;
    background:radial-gradient(closest-side,rgba(0,0,0,.5),rgba(0,0,0,0));
    animation:clShadow 1.15s cubic-bezier(.5,.05,.4,1) infinite}
  @keyframes clShadow{0%,100%{transform:scale(1);opacity:.5}50%{transform:scale(.7);opacity:.28}}

  .cl-charm{transform-origin:center;animation:clCharm 1.15s ease-in-out infinite}
  @keyframes clCharm{0%,100%{transform:rotate(-8deg)}50%{transform:rotate(8deg)}}

  /* brand + text */
  .cl-brandrow{display:flex;align-items:center;justify-content:center;gap:10px;margin-top:18px}
  .cl-star{width:34px;height:34px;flex:0 0 auto;animation:clStar 6s linear infinite}
  @keyframes clStar{to{transform:rotateY(360deg)}}
  .cl-name{font-family:'Fredoka','Manrope',sans-serif;font-weight:700;font-size:28px;color:#fff;letter-spacing:.4px;line-height:1}
  .cl-name b{color:#5b8cff}
  .cl-sub{margin-top:6px;font-size:11.5px;letter-spacing:.06em;text-transform:uppercase;color:rgba(255,255,255,.5);font-weight:700}
  .cl-msg{margin-top:14px;font-size:13.5px;color:rgba(255,255,255,.82);font-weight:600;min-height:18px}
  .cl-msg .cl-dots::after{content:"";animation:clDots 1.4s steps(4,end) infinite}
  @keyframes clDots{0%{content:""}25%{content:"."}50%{content:".."}75%{content:"..."}100%{content:""}}

  /* progress sweep */
  .cl-bar{width:230px;height:7px;border-radius:9999px;margin:16px auto 0;overflow:hidden;
    background:rgba(255,255,255,.12);position:relative}
  .cl-bar i{position:absolute;top:0;left:-40%;height:100%;width:40%;border-radius:9999px;
    background:linear-gradient(90deg,#5b8cff,#e11d2b,#f5b301);animation:clBar 1.3s ease-in-out infinite}
  @keyframes clBar{0%{left:-42%}100%{left:104%}}
  .cl-way{margin-top:11px;font-size:11px;color:rgba(255,255,255,.4);font-weight:600;letter-spacing:.04em}

  @media (prefers-reduced-motion:reduce){
    .cl-tilt,.cl-croc,.cl-shadow,.cl-charm,.cl-star,.cl-floor,.cl-ghost,.cl-bar i{animation:none!important}
  }
  @media(max-width:480px){.cl-stage{transform:scale(.82)}}
  `;

  // ---- SVG: chunky croc-clog, toe to the right ----
  function crocSVG(){
    return `<svg viewBox="0 0 280 184" xmlns="http://www.w3.org/2000/svg">
      <!-- heel strap (behind body) -->
      <path d="M70 116 C 40 90 46 44 86 40 C 104 38 113 50 108 66" fill="none"
            stroke="var(--t)" stroke-width="13" stroke-linecap="round"/>
      <circle cx="70" cy="116" r="9" fill="var(--t)"/>
      <circle cx="70" cy="116" r="3.4" fill="rgba(0,0,0,.35)"/>
      <!-- chunky platform sole -->
      <path d="M42 120 C 34 113 41 105 52 105 L 224 105 C 244 106 250 118 242 130
               C 235 140 214 142 196 140 L 72 140 C 50 140 42 130 42 120 Z" fill="var(--s)"/>
      <path d="M50 124 L 232 124" stroke="rgba(0,0,0,.10)" stroke-width="3" stroke-linecap="round"/>
      <!-- upper / clog body -->
      <path d="M54 108 C 47 72 74 50 134 49 C 190 48 218 68 219 100 C 219 105 217 108 210 108 Z" fill="var(--b)"/>
      <!-- gloss highlight -->
      <path d="M74 72 C 96 60 128 58 158 61" fill="none" stroke="rgba(255,255,255,.45)" stroke-width="6" stroke-linecap="round"/>
      <!-- toe seam -->
      <path d="M198 70 C 210 78 214 90 209 104" fill="none" stroke="rgba(0,0,0,.10)" stroke-width="4" stroke-linecap="round"/>
      <!-- croc holes -->
      <ellipse cx="126" cy="74" rx="5" ry="6.4" fill="var(--n)"/>
      <ellipse cx="150" cy="70" rx="5" ry="6.4" fill="var(--n)"/>
      <ellipse cx="174" cy="72" rx="5" ry="6.4" fill="var(--n)"/>
      <ellipse cx="138" cy="92" rx="5" ry="6.4" fill="var(--n)"/>
      <ellipse cx="162" cy="90" rx="5" ry="6.4" fill="var(--n)"/>
      <ellipse cx="186" cy="92" rx="5" ry="6.4" fill="var(--n)"/>
      <!-- jibbitz charm: Captain America shield -->
      <g class="cl-charm" transform="translate(98 86)">
        <circle r="15.5" fill="#c8102e"/>
        <circle r="12" fill="#ffffff"/>
        <circle r="8.4" fill="#c8102e"/>
        <circle r="4.8" fill="#1b3a8b"/>
        <path d="M0 -4.6 L1.33 -1.42 L4.75 -1.2 L2.13 1.02 L3.03 4.37 L0 2.44 L-3.03 4.37 L-2.13 1.02 L-4.75 -1.2 L-1.33 -1.42 Z" fill="#ffffff"/>
      </g>
    </svg>`;
  }
  function ghostSVG(){
    return `<svg viewBox="0 0 280 184"><path d="M42 120 C 34 113 41 105 52 105 L 224 105 C 244 106 250 118 242 130 C 235 140 214 142 196 140 L 72 140 C 50 140 42 130 42 120 Z" fill="#fff"/><path d="M54 108 C 47 72 74 50 134 49 C 190 48 218 68 219 100 C 219 105 217 108 210 108 Z" fill="#fff"/></svg>`;
  }
  var STAR = `<svg class="cl-star" viewBox="0 0 64 64"><circle cx="32" cy="32" r="30.5" fill="#fff"/><circle cx="32" cy="32" r="30.5" fill="none" stroke="#e11d2b" stroke-width="3"/><path d="M32 10 L37.29 24.72 L52.92 25.2 L40.56 34.78 L44.94 49.8 L32 41 L19.06 49.8 L23.44 34.78 L11.08 25.2 L26.71 24.72 Z" fill="#e11d2b"/><path d="M32 10 L32 41 L19.06 49.8 L23.44 34.78 L11.08 25.2 L26.71 24.72 Z" fill="#b01421"/></svg>`;

  var HTML =
    '<div class="cl-overlay" id="clOverlay" role="status" aria-live="polite" aria-label="Loading">'+
      '<div class="cl-orb a"></div><div class="cl-orb b"></div><div class="cl-orb c"></div>'+
      '<div class="cl-floor"></div>'+
      '<div class="cl-bg">'+
        '<div class="cl-ghost g1">'+ghostSVG()+'</div>'+
        '<div class="cl-ghost g2">'+ghostSVG()+'</div>'+
        '<div class="cl-ghost g3">'+ghostSVG()+'</div>'+
        '<div class="cl-ghost g4">'+ghostSVG()+'</div>'+
      '</div>'+
      '<div class="cl-center">'+
        '<div class="cl-stage"><div class="cl-tilt">'+
          '<div class="cl-shadow"></div>'+
          '<div class="cl-croc" id="clCroc"><img class="cl-prod" id="clProd" alt="STAR Kidz croc">'+crocSVG()+'</div>'+
        '</div></div>'+
        '<div class="cl-brandrow">'+STAR+'<div class="cl-name">STAR <b>Kidz</b></div></div>'+
        '<div class="cl-sub">Ojas Footwear · Production Portal</div>'+
        '<div class="cl-msg" id="clMsg"><span class="cl-dots">Lacing up your workspace</span></div>'+
        '<div class="cl-bar"><i></i></div>'+
        '<div class="cl-way" id="clWay"></div>'+
      '</div>'+
    '</div>';

  var overlay=null, croc=null, msgEl=null, wayEl=null, shownAt=0, cycle=null, idx=0;

  function applyWay(w){
    if(!croc) return;
    croc.style.setProperty('--b',w.b); croc.style.setProperty('--s',w.s);
    croc.style.setProperty('--t',w.t); croc.style.setProperty('--n',w.n);
    if(wayEl) wayEl.textContent='Colourway · '+w.lbl;
  }
  function startCycle(){
    stopCycle(); idx=0; applyWay(WAYS[0]);
    cycle=setInterval(function(){ idx=(idx+1)%WAYS.length; applyWay(WAYS[idx]); }, 1600);
  }
  function stopCycle(){ if(cycle){clearInterval(cycle);cycle=null;} }

  function inject(){
    if(document.getElementById('clOverlay')) return;
    var st=document.createElement('style'); st.id='clStyle'; st.textContent=CSS; document.head.appendChild(st);
    var holder=document.createElement('div'); holder.innerHTML=HTML;
    overlay=holder.firstChild; document.body.appendChild(overlay);
    croc=document.getElementById('clCroc'); msgEl=document.getElementById('clMsg'); wayEl=document.getElementById('clWay');
    tryProduct();
  }

  // If a real product photo (product-croc.*) exists in the app folder, use it
  // as the actual shoe and drop the drawn fallback.
  function tryProduct(){
    var img=document.getElementById('clProd'); if(!img) return;
    var svg=croc.querySelector('svg'), i=0;
    (function next(){
      if(i>=PROD_NAMES.length) return;            // none found → keep drawn croc
      var name=PROD_NAMES[i++], probe=new Image();
      probe.onload=function(){
        img.src=name; img.style.display='block';
        if(svg) svg.style.display='none';
        if(overlay) overlay.classList.add('cl-photo');
        stopCycle(); if(wayEl) wayEl.textContent='STAR Kidz · Captain America';
      };
      probe.onerror=next; probe.src=name;
    })();
  }

  function show(message){
    if(!document.body){ document.addEventListener('DOMContentLoaded',function(){show(message);}); return; }
    inject();
    if(message) msgEl.innerHTML='<span class="cl-dots">'+message+'</span>';
    overlay.classList.remove('cl-hide'); overlay.classList.add('cl-show');
    shownAt=Date.now(); startCycle();
  }
  function hide(){
    if(!overlay) return;
    var wait=Math.max(0, MIN-(Date.now()-shownAt));
    setTimeout(function(){
      overlay.classList.add('cl-hide');
      setTimeout(function(){ overlay.classList.remove('cl-show','cl-hide'); stopCycle(); }, 460);
    }, wait);
  }

  window.CrocLoader={show:show, hide:hide};

  // auto mode: show on entry, hide once the window has fully loaded
  if(AUTO){
    var go=function(){
      show();
      if(document.readyState==='complete') hide();
      else window.addEventListener('load', hide, {once:true});
    };
    if(document.body) go(); else document.addEventListener('DOMContentLoaded', go);
  }
})();
