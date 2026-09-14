// Interpolate actual app renders. Every frame has the same stationary desktop.
// No browser permissions, sensor access, analytics, or external requests.
const angles = [12, 35, 50, 65, 80, 95, 110];
const canvas = document.querySelector('#demo-canvas');
const context = canvas.getContext('2d', { alpha: false });
const slider = document.querySelector('#angle');
const readout = document.querySelector('#angle-display');
const play = document.querySelector('#play');
const status = document.querySelector('#demo-status');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const frames = new Map();
let animation = 0;

function draw(angle) {
  const value = Math.max(12, Math.min(110, angle));
  const upper = angles.find(a => a >= value) ?? 110;
  const lower = [...angles].reverse().find(a => a <= value) ?? 12;
  context.globalAlpha = 1;
  context.drawImage(frames.get(lower), 0, 0, canvas.width, canvas.height);
  if (lower !== upper) {
    context.globalAlpha = (value - lower) / (upper - lower);
    context.drawImage(frames.get(upper), 0, 0, canvas.width, canvas.height);
    context.globalAlpha = 1;
  }
  slider.value = Math.round(value);
  slider.style.setProperty('--range', `${(value - 12) / 98 * 100}%`);
  slider.setAttribute('aria-valuetext', `${Math.round(value)} 度`);
  readout.textContent = `${Math.round(value)}°`;
}

function stop() {
  cancelAnimationFrame(animation);
  animation = 0;
  play.setAttribute('aria-label', '播放合盖演示');
  play.innerHTML = '<svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true"><path d="m7 4 9 6-9 6z"/></svg>';
}

slider.addEventListener('input', () => { stop(); draw(Number(slider.value)); });
play.addEventListener('click', () => {
  if (animation) { stop(); return; }
  if (reducedMotion.matches) { draw(Number(slider.value) > 60 ? 35 : 110); return; }
  const start = performance.now();
  play.setAttribute('aria-label', '暂停合盖演示');
  play.innerHTML = '<svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true"><path d="M5 4h3v12H5zm7 0h3v12h-3z"/></svg>';
  function tick(now) {
    const progress = Math.min(1, (now - start) / 5200);
    const phase = (1 - Math.cos(progress * 2 * Math.PI)) / 2;
    draw(110 - 98 * phase);
    if (progress < 1) animation = requestAnimationFrame(tick);
    else stop();
  }
  animation = requestAnimationFrame(tick);
});
document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
reducedMotion.addEventListener('change', stop);

Promise.all(angles.map(angle => new Promise((resolve, reject) => {
  const frame = new Image();
  frame.onload = () => { frames.set(angle, frame); resolve(); };
  frame.onerror = reject;
  frame.src = `frame-${angle}.png`;
}))).then(() => {
  if (!context) throw new Error('Canvas is unavailable');
  draw(80);
  canvas.classList.add('ready');
  slider.disabled = false;
  play.disabled = false;
  status.textContent = '拖动滑杆，预览开合 · 画面来自 App 示例桌面';
}).catch(() => {
  status.textContent = '当前为静态预览 · 下载 App 体验完整动效';
});
