// Tells the app which link the pointer is over, so a desktop window can show where it goes. A touch window ignores it.
if (READER) {
  let hovered = null;
  const report = (link) => {
    if (link === hovered) return;
    hovered = link;
    window.webkit.messageHandlers[HANDLER].postMessage({ link });
  };
  const address = (anchor) => (typeof anchor.href === 'string' ? anchor.href : anchor.href.baseVal);
  document.addEventListener('mouseover', (event) => {
    const anchor = event.target.closest?.('a[href]');
    report(anchor ? address(anchor) : null);
  });
  document.documentElement.addEventListener('mouseleave', () => report(null));
}
