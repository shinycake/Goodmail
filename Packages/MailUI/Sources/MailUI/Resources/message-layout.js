// The reader's zoom, from the head on load and from the app when the reader changes it. On iPhone and iPad CSS zoom
// scales the whole page, so its text reflows at the larger size. On the Mac it scales boxes and leaves text at its
// size, so there the zoom multiplies each text size the page starts with instead, and its line spacing follows as a
// share of the size. Either way the sizes the page reports are in the view's points.
const root = document.documentElement;
const zoomScalesText = (() => {
  const probe = document.createElement('span');
  probe.textContent = 'Zoom';
  probe.style.cssText = 'position: absolute; visibility: hidden; white-space: nowrap; font: 16px system-ui';
  document.body.appendChild(probe);
  const width = probe.getBoundingClientRect().width;
  root.style.zoom = '2';
  const zoomed = probe.getBoundingClientRect().width;
  root.style.zoom = '';
  probe.remove();
  return zoomed > width * 1.5;
})();
// Where a text size or line spacing starts, since the rest inherit it, with the inline values to give back at 1.
const texts = zoomScalesText ? [] : [document.body, ...document.body.querySelectorAll('*')].flatMap((el) => {
  const style = getComputedStyle(el);
  const parent = el === document.body ? null : getComputedStyle(el.parentElement);
  if (parent && style.fontSize === parent.fontSize && style.lineHeight === parent.lineHeight) return [];
  const size = parseFloat(style.fontSize);
  const line = style.lineHeight === 'normal' ? null : parseFloat(style.lineHeight) / size;
  const inline = ['font-size', 'line-height'].map((name) =>
    [el.style.getPropertyValue(name), el.style.getPropertyPriority(name)]);
  return [{ el, size, line, inline }];
});
let zoom = 1;
const zoomTo = (factor) => {
  zoom = factor;
  if (zoomScalesText) {
    root.style.zoom = factor === 1 ? '' : String(factor);
    return;
  }
  for (const { el, size, line, inline } of texts) {
    const [[fontSize, sizePriority], [lineHeight, linePriority]] = inline;
    if (factor === 1) {
      el.style.setProperty('font-size', fontSize, sizePriority);
      el.style.setProperty('line-height', lineHeight, linePriority);
      continue;
    }
    // Important, so a sender's own important size gives way to the reader's zoom.
    el.style.setProperty('font-size', `${size * factor}px`, 'important');
    if (line !== null) el.style.setProperty('line-height', String(line), 'important');
  }
};
zoomTo(parseFloat(document.querySelector('meta[name="goodmail-zoom"]')?.content || '1'));

// Fit wide layouts, such as 600-pixel newsletters, to the card's width.
const fit = () => {
  document.body.style.zoom = '';
  const width = document.documentElement.clientWidth;
  const content = document.body.scrollWidth;
  if (content > width + 1) document.body.style.zoom = (width / content).toFixed(4);
};

// What the reader's card needs from the page: the height to size the card, and whether remote content is blocked. A
// PDF's page sizes itself, so only the reader reports.
const remote = /^(https?:)?\/\//i;
const hasRemote = [...document.querySelectorAll('img[src], img[srcset], [background], link[href]')]
  .some((el) => remote.test(el.getAttribute('src') || el.getAttribute('srcset')
    || el.getAttribute('background') || el.getAttribute('href') || ''))
  || /url\(\s*['"]?(https?:)?\/\//i.test(document.documentElement.innerHTML);
let lastHeight = 0;
// The body's content, not its box or the document's: the document is never shorter than the view, so it
// couldn't shrink back, and a template's `html, body { height: 100% }` holds the body to the view, which
// starts 1 point tall, so the card would never grow past it.
const content = document.createRange();
content.selectNodeContents(document.body);
const report = () => {
  const style = getComputedStyle(document.body);
  // The box is in the view's points already; the body's own padding and margin are in the page's units.
  const scale = parseFloat(root.style.zoom || '1');
  const height = Math.ceil(content.getBoundingClientRect().bottom + window.scrollY
    + (parseFloat(style.paddingBottom || '0') + parseFloat(style.marginBottom || '0')) * scale);
  if (height === lastHeight) return;
  lastHeight = height;
  window.webkit.messageHandlers[HANDLER].postMessage({ height, hasRemote, zoom });
};
fit();
if (READER) {
  // A body held to the view's height doesn't resize when its content does, so its children are watched too,
  // and images report as they load.
  const resizes = new ResizeObserver(report);
  for (const el of [document.body, ...document.body.children]) resizes.observe(el);
  document.addEventListener('toggle', report, true);
  document.addEventListener('load', report, true);
  // The view's width changes with the window and with the reader's zoom, and a wide layout fits the new width.
  window.addEventListener('resize', () => { fit(); report(); });
  // Reports even when the height comes out the same, so the app learns the page took the zoom.
  window.goodmailZoom = (factor) => { zoomTo(factor); fit(); lastHeight = 0; report(); };
  report();
}
