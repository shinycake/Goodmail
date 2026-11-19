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
  const height = Math.ceil(content.getBoundingClientRect().bottom + window.scrollY
    + parseFloat(style.paddingBottom || '0') + parseFloat(style.marginBottom || '0'));
  if (height === lastHeight) return;
  lastHeight = height;
  window.webkit.messageHandlers[HANDLER].postMessage({ height, hasRemote });
};
fit();
if (READER) {
  // A body held to the view's height doesn't resize when its content does, so its children are watched too,
  // and images report as they load.
  const resizes = new ResizeObserver(report);
  for (const el of [document.body, ...document.body.children]) resizes.observe(el);
  document.addEventListener('toggle', report, true);
  document.addEventListener('load', report, true);
  report();
}
