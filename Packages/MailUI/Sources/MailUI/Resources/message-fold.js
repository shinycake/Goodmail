// Fold quoted history: the first quote, and everything after it at its level.
const isBlank = (node) => node.nodeType === Node.COMMENT_NODE
  || (node.nodeType === Node.TEXT_NODE && !node.textContent.trim())
  || (node.nodeType === Node.ELEMENT_NODE && node.tagName === 'BR');
const start = document.body.querySelector(
  '.gmail_quote, blockquote[type="cite"], #divRplyFwdMsg, .moz-cite-prefix, blockquote.goodmail-quote');
let fold = start;
// Climb while the quote is the first real content of its parent, so its wrapper folds with it.
while (fold && fold.parentElement && fold.parentElement !== document.body) {
  let before = fold.previousSibling;
  while (before && isBlank(before)) before = before.previousSibling;
  if (before) break;
  fold = fold.parentElement;
}
const hasContentBefore = (node) => {
  const range = document.createRange();
  range.setStart(document.body, 0);
  range.setEndBefore(node);
  return range.toString().trim().length > 0 || range.cloneContents().querySelector('img') !== null;
};
// The fold control sits where the reply's text starts, so it follows the reply's direction, not the quote's.
const directionBefore = (node) => {
  const range = document.createRange();
  range.setStart(document.body, 0);
  range.setEndBefore(node);
  const strong = range.toString().match(/[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]|[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]/);
  return strong && /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/.test(strong[0]) ? 'rtl' : 'ltr';
};
if (READER && fold && hasContentBefore(fold)) {
  const details = document.createElement('details');
  details.className = 'goodmail-fold';
  details.setAttribute('dir', directionBefore(fold));
  const summary = document.createElement('summary');
  summary.textContent = '•••';
  summary.setAttribute('aria-label', FOLD_LABEL);
  details.appendChild(summary);
  fold.parentNode.insertBefore(details, fold);
  while (details.nextSibling) details.appendChild(details.nextSibling);
}
