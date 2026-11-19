// Direction per block: where the sender set none, each block follows its own first strong character. A Hebrew
// reply above an English quote, or one Hebrew line in English mail, each reads its own way.
const BLOCKS = 'p,div,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,pre,dd,dt,section,article,header,footer,center';
if (!document.body.hasAttribute('dir')) document.body.setAttribute('dir', 'auto');
for (const el of document.body.querySelectorAll(BLOCKS)) {
  if (!el.hasAttribute('dir')) el.setAttribute('dir', 'auto');
}
