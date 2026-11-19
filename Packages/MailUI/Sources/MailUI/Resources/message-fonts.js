// Fonts: a sender's font list with no generic family falls back to WebKit's serif default wherever none of its fonts
// is installed, as Outlook's "Aptos" or "Calibri" alone does on iOS. Ending each such list with the system font keeps
// any font that is installed and reads like the app where none is.
const GENERIC = /^(serif|sans-serif|monospace|cursive|fantasy|math|emoji|fangsong|system-ui|-apple-system.*|ui-.+)$/i;
// Only where a list starts, since descendants inherit it; all are read before any is changed.
const family = (el) => getComputedStyle(el).fontFamily;
const lists = [document.body, ...document.body.querySelectorAll('*')]
  .filter((el) => el === document.body || family(el) !== family(el.parentElement))
  .map((el) => [el, family(el)]);
for (const [el, family] of lists) {
  const names = family.split(',').map((name) => name.trim().replace(/^["']|["']$/g, ''));
  if (!names.some((name) => GENERIC.test(name))) el.style.fontFamily = `${family}, system-ui`;
}
