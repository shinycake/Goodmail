// Contrast, for the adaptive palette (MessagePalette): text whose color fails WCAG AA (4.5:1) on the card in an
// appearance gets a mark for it and a replacement, which the palette's rules apply in that appearance only. Grays
// become the appearance's own text color; other colors keep their hue, mixed toward white for dark or black for light
// until they pass, so red stays red and a link stays blue. White backgrounds are marked too. Every color is read
// before any mark lands, since a mark changes what its descendants inherit.
if (PALETTE === 'adaptive') {
  const APPEARANCES = [
    { name: 'dark', card: CARD, toward: 255 },
    { name: 'light', card: CARD_LIGHT, toward: 0 },
  ];
  const readable = (ink, { card, toward }) => {
    const opaque = ink.length < 4 ? ink.slice(0, 3) : ink.slice(0, 3).map((v, i) => v * ink[3] + card[i] * (1 - ink[3]));
    if (contrast(opaque, card) >= 4.5) return null;
    // Black, white and grays become the appearance's own text color, as unstyled text would be.
    if (Math.max(...opaque) - Math.min(...opaque) < 40) return 'CanvasText';
    for (let mix = 0.05; ; mix += 0.05) {
      const candidate = opaque.map((v) => Math.round(v + (toward - v) * Math.min(mix, 1)));
      if (mix >= 1 || contrast(candidate, card) >= 4.5) return `rgb(${candidate.join(', ')})`;
    }
  };
  // Our quote and fold colors already pass in both appearances, so they are left as they are.
  const OURS = 'blockquote.goodmail-quote, details.goodmail-fold > summary';
  const marks = [document.body, ...document.body.querySelectorAll('*')].flatMap((el) => {
    if (el.closest(OURS)) return [];
    const style = getComputedStyle(el);
    const ink = channels(style.color);
    const paper = channels(style.backgroundColor);
    const found = [];
    for (const appearance of ink.length >= 3 && ink[3] !== 0 ? APPEARANCES : []) {
      const replacement = readable(ink, appearance);
      if (replacement) found.push([el, appearance.name, replacement]);
    }
    if (paper.length >= 3 && (paper[3] ?? 1) > 0 && luminance(paper) > 0.9) found.push([el, 'white', null]);
    return found;
  });
  for (const [el, name, replacement] of marks) {
    if (replacement) {
      el.setAttribute(`data-goodmail-faint-on-${name}`, '');
      el.style.setProperty(`--goodmail-on-${name}`, replacement);
    } else {
      el.setAttribute('data-goodmail-white', '');
    }
  }
}
