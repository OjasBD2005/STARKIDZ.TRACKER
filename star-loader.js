/* ============================================================
   STAR Kidz — BRANDED LOADER  (replaces the old croc loader)
   A clean splash showing the STAR Kidz logo while the portal loads.

   Usage:
     <script src="star-loader.js" data-auto="true"></script>  // auto show on entry
     <script src="star-loader.js"></script>                   // manual control

   API:  window.StarLoader.show(message?)   window.StarLoader.hide()
   (window.CrocLoader is kept as an alias so older calls keep working.)
   ============================================================ */
(function(){
  if(window.StarLoader) return;

  var me   = document.currentScript;
  var AUTO = !!(me && me.dataset && me.dataset.auto === 'true');
  var MIN  = (me && me.dataset && +me.dataset.min) || 1400;   // min visible time (ms)

  var CSS = `
  .sk-overlay{position:fixed;inset:0;z-index:99999;display:none;place-items:center;
    background:radial-gradient(120% 120% at 50% 18%,#16224a 0%,#0b1430 48%,#070d1f 100%);
    font-family:'Manrope',system-ui,-apple-system,sans-serif}
  .sk-overlay.sk-show{display:grid;animation:skFade .3s ease}
  .sk-overlay.sk-hide{animation:skOut .45s ease forwards}
  @keyframes skFade{from{opacity:0}to{opacity:1}}
  @keyframes skOut{to{opacity:0;visibility:hidden}}
  .sk-box{text-align:center;display:flex;flex-direction:column;align-items:center;gap:18px}
  .sk-badge{width:118px;height:118px;border-radius:30px;background:#fff;display:grid;place-items:center;
    box-shadow:0 24px 60px -18px rgba(225,29,43,.55),0 0 0 1px rgba(255,255,255,.06);
    animation:skPop .6s cubic-bezier(.2,.9,.25,1.2) both}
  @keyframes skPop{from{transform:scale(.6);opacity:0}to{transform:scale(1);opacity:1}}
  .sk-badge svg{width:80px;height:80px;animation:skSpin 2.2s ease-in-out infinite}
  @keyframes skSpin{0%,100%{transform:rotate(-7deg) scale(1)}50%{transform:rotate(7deg) scale(1.06)}}
  .sk-word{font-weight:800;font-size:26px;letter-spacing:.3px;color:#fff;line-height:1}
  .sk-word b{color:#fb7185;font-style:italic}
  .sk-msg{color:rgba(255,255,255,.62);font-size:13px;font-weight:600;min-height:18px}
  .sk-dots{display:flex;gap:7px}
  .sk-dots i{width:8px;height:8px;border-radius:50%;background:#fb7185;display:inline-block;animation:skBlink 1s infinite}
  .sk-dots i:nth-child(2){animation-delay:.15s;background:#f43f5e}
  .sk-dots i:nth-child(3){animation-delay:.3s;background:#e11d2b}
  @keyframes skBlink{0%,100%{opacity:.25;transform:translateY(0)}50%{opacity:1;transform:translateY(-5px)}}
  `;

  var LOGO = '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">'
    + '<circle cx="32" cy="32" r="30.5" fill="none" stroke="#e11d2b" stroke-width="3.4"/>'
    + '<path d="M32 10 L37.29 24.72 L52.92 25.2 L40.56 34.78 L44.94 49.8 L32 41 L19.06 49.8 L23.44 34.78 L11.08 25.2 L26.71 24.72 Z" fill="#e11d2b"/>'
    + '<path d="M32 10 L32 41 L19.06 49.8 L23.44 34.78 L11.08 25.2 L26.71 24.72 Z" fill="#b01421"/></svg>';

  function build(){
    var s = document.createElement('style'); s.textContent = CSS; document.head.appendChild(s);
    var o = document.createElement('div'); o.className = 'sk-overlay'; o.id = 'skOverlay';
    o.innerHTML =
      '<div class="sk-box">'
      +  '<div class="sk-badge">' + LOGO + '</div>'
      +  '<div class="sk-word">STAR <b>Kidz</b></div>'
      +  '<div class="sk-dots"><i></i><i></i><i></i></div>'
      +  '<div class="sk-msg" id="skMsg"></div>'
      + '</div>';
    document.body.appendChild(o);
    return o;
  }

  var overlay = null, shownAt = 0;
  function ensure(){ if(!overlay) overlay = document.getElementById('skOverlay') || build(); return overlay; }

  var StarLoader = {
    show: function(msg){
      var o = ensure();
      var m = document.getElementById('skMsg'); if(m) m.textContent = msg || 'Loading the STAR Kidz portal…';
      o.classList.remove('sk-hide'); o.classList.add('sk-show'); shownAt = Date.now();
    },
    hide: function(){
      var o = ensure();
      var wait = Math.max(0, MIN - (Date.now() - shownAt));
      setTimeout(function(){
        o.classList.add('sk-hide');
        setTimeout(function(){ o.classList.remove('sk-show','sk-hide'); }, 460);
      }, wait);
    }
  };

  window.StarLoader = StarLoader;
  window.CrocLoader = StarLoader;   // backward-compatible alias

  if(AUTO){
    if(document.body){ StarLoader.show(); }
    else { document.addEventListener('DOMContentLoaded', function(){ StarLoader.show(); }); }
    window.addEventListener('load', function(){ StarLoader.hide(); });
  }
})();
