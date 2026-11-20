// Dark, for bodies whose sender painted their own colors (MessagePalette's painted and sendersOwn). It reads the page
// as it shows in dark and turns it over the way Gmail does, so a newsletter made for a white page reads like the rest
// of the app:
// - A light background, white or a pale gray or pastel, becomes a dark one of the same hue: white becomes the sheet,
//   a paler color a shade above it. Mid and dark colors, such as a brand's navy banner, stay as the sender set them.
// - A light border turns over the same way, so dividers don't glare.
// - Text that is then too faint on what it sits on moves toward white or black, keeping its hue: navy body text turns
//   pale, a link stays blue, and white text on a kept navy banner stays white.
// - An <img> stays as it is, and once it has loaded, keeps the light color the sender drew it on behind it, so a
//   transparent logo's dark ink doesn't vanish on a turned panel. On an opaque image that color never shows. Images
//   still blocked or broken, spacers and tracking pixels, and a <picture> with its own dark source get none. Inline
//   SVG, and anything drawn over a background image, stay as they are, since the pass can't see what they show.
// Each change is a mark with its replacement color, which the palette's rules apply in dark appearance only, so the
// sun button shows the sender's own colors again without a reload. Every color is read before any mark lands, since
// a mark changes what the elements around it show.
if (PALETTE === 'painted' || PALETTE === 'sendersOwn') {
  const dark = matchMedia('(prefers-color-scheme: dark)');
  // OKLab, where lightness is as eyes see it: a pale yellow and a pale blue of the same lightness turn equally
  // dark, which HSL can't promise.
  const linear = (v) => (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  const encoded = (v) => Math.round(255 * Math.min(1,
    v <= 0.0031308 ? Math.max(0, v) * 12.92 : 1.055 * v ** (1 / 2.4) - 0.055));
  const oklab = (color) => {
    const [r, g, b] = color.map(linear);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
  };
  const srgb = ([L, a, b]) => {
    const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
    const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
    const s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3;
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s].map(encoded);
  };
  const SHEET_LIGHTNESS = oklab(SHEET)[0];
  // A light color's dark counterpart, or null for a color dark enough to keep. Lightness turns over from
  // white at the sheet, the hue stays, and the chroma softens so a pastel becomes a deep tint, not a glow.
  const turned = (color) => {
    const [L, a, b] = oklab(color);
    return L < 0.8 ? null : srgb([SHEET_LIGHTNESS + (1 - L) * 0.75, a * 0.7, b * 0.7]);
  };
  const over = (color, below) => color.length < 4 || color[3] >= 1 ? color.slice(0, 3)
    : color.slice(0, 3).map((v, i) => Math.round(v * color[3] + below[i] * (1 - color[3])));
  const opaque = (color) => color.length >= 3 && (color[3] ?? 1) > 0;
  const css = (color) => `rgb(${color.join(', ')})`;
  // Text that fails on its backdrop moves toward whichever of white or black reads better there: white on the
  // turned dark panels, black on a light color the pass kept, such as an orange button. Grays go all the way;
  // a color keeps its hue and chroma in OKLab while only its lightness moves, so a link stays blue rather than
  // washing out to lavender. It moves until it reads comfortably (7:1), not just past the 4.5:1 that flagged
  // it, so body text reads like the rest of the app rather than barely legible.
  const readable = (ink, backdrop) => {
    const up = contrast([255, 255, 255], backdrop) >= contrast([0, 0, 0], backdrop);
    if (Math.max(...ink) - Math.min(...ink) < 40) return up ? 'rgb(255, 255, 255)' : 'rgb(0, 0, 0)';
    const [L, a, b] = oklab(ink);
    for (let step = 1; ; step += 1) {
      const lightness = up ? Math.min(1, L + step * 0.02) : Math.max(0, L - step * 0.02);
      const candidate = srgb([lightness, a, b]);
      if (lightness === 0 || lightness === 1 || contrast(candidate, backdrop) >= 7) return css(candidate);
    }
  };
  const hasText = (el) => [...el.childNodes].some(
    (node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
  const SIDES = ['top', 'right', 'bottom', 'left'];
  let passed = false;
  const pass = () => {
    if (passed || !dark.matches) return;
    passed = true;
    const root = channels(getComputedStyle(document.documentElement).backgroundColor);
    const page = opaque(root) ? over(root, CARD) : CARD;
    // What each element's content shows on in dark once the marks land, the element whose paper that is (null for
    // the page), and the light color the sender painted there if the pass turned it; a null color over a background
    // image, which the pass can't read. A painted page shows our sheet in dark where it was white in light, unless
    // the sender painted the page themselves.
    const pageSenderColor = PALETTE === 'painted' && page.join() === SHEET.join() ? [255, 255, 255] : null;
    const backdrops = new Map();
    const marks = [];
    const plates = [];
    for (const el of [document.body, ...document.body.querySelectorAll('*')]) {
      const style = getComputedStyle(el);
      const below = backdrops.get(el.parentElement)
        ?? { color: page, owner: null, senderColor: pageSenderColor };
      let backdrop = below;
      const paper = channels(style.backgroundColor);
      if (style.backgroundImage !== 'none') {
        backdrop = { color: null, owner: el, senderColor: null };
      } else if (opaque(paper) && (below.color || (paper[3] ?? 1) >= 1)) {
        const shown = over(paper, below.color ?? paper);
        const replacement = turned(shown);
        // An image's own light paper stays: its plate below is that same color.
        if (replacement && el.tagName !== 'IMG') {
          marks.push({ el, kind: 'paper', value: css(replacement), color: replacement });
        }
        backdrop = { color: replacement ?? shown, owner: el, senderColor: replacement ? shown : null };
      }
      backdrops.set(el, backdrop);
      if (el.tagName === 'IMG' && backdrop.senderColor) {
        plates.push({ el, kind: 'plate', value: css(backdrop.senderColor), owner: backdrop.owner });
      }
      let ink = null;
      if (backdrop.color && hasText(el)) {
        const color = channels(style.color);
        const shown = opaque(color) ? over(color, backdrop.color) : null;
        if (shown && contrast(shown, backdrop.color) < 4.5) {
          ink = readable(shown, backdrop.color);
          marks.push({ el, kind: 'ink', value: ink, owner: backdrop.owner });
        }
      }
      // A border is drawn over the element's own paper, and one in the text's color follows the text.
      const under = backdrop.color ?? below.color;
      if (under) {
        const sides = SIDES.map((side) => {
          const color = style.getPropertyValue(`border-${side}-color`);
          if (!(parseFloat(style.getPropertyValue(`border-${side}-width`)) > 0)) return [side, color, false];
          if (ink && color === style.color) return [side, ink, true];
          const value = channels(color);
          const replacement = opaque(value) ? turned(over(value, under)) : null;
          return [side, replacement ? css(replacement) : color, replacement !== null];
        });
        if (sides.some(([, , changed]) => changed)) marks.push({ el, kind: 'border', value: sides });
      }
    }
    const apply = (mark) => {
      mark.el.setAttribute(`data-goodmail-dark-${mark.kind}`, '');
      if (mark.kind === 'border') {
        for (const [side, color] of mark.value) {
          mark.el.style.setProperty(`--goodmail-dark-border-${side}`, color);
        }
      } else {
        mark.el.style.setProperty(`--goodmail-dark-${mark.kind}`, mark.value);
      }
    };
    const remove = (mark) => {
      mark.el.removeAttribute(`data-goodmail-dark-${mark.kind}`);
      const names = mark.kind === 'border' ? SIDES.map((side) => `border-${side}`) : [mark.kind];
      for (const name of names) mark.el.style.removeProperty(`--goodmail-dark-${name}`);
    };
    marks.forEach(apply);
    // A sender's inline `!important` beats even our layered rules. Where a panel kept its light color, or
    // text on it kept its dark one, the panel and every text replacement that counted on it go back to the
    // sender's own pair, which reads.
    const held = new Set();
    for (const mark of marks) {
      const style = getComputedStyle(mark.el);
      if (mark.kind === 'paper' && channels(style.backgroundColor).slice(0, 3).join() !== mark.color.join()) {
        held.add(mark.el);
      } else if (mark.kind === 'ink' && mark.owner
        && channels(style.color).slice(0, 3).join() !== channels(mark.value).join()) {
        held.add(mark.owner);
      }
    }
    for (const mark of marks) {
      if (held.has(mark.el) && mark.kind === 'paper') remove(mark);
      if (mark.kind === 'ink' && held.has(mark.owner)) remove(mark);
    }
    // A plate goes on an image once it shows, big enough to carry ink: a blocked or broken image would otherwise
    // become a light slab, and a transparent spacer or tracking pixel a light bar or dot. A <picture> showing one of
    // its sources rather than its <img>'s own picks that source for dark itself.
    const platable = (img) => img.naturalWidth > 2 && img.naturalHeight > 2
      && img.offsetWidth >= 16 && img.offsetHeight >= 16
      && !(img.closest('picture') && img.currentSrc !== img.src);
    for (const plate of plates) {
      if (held.has(plate.owner)) continue;
      const place = () => { if (platable(plate.el)) apply(plate); };
      if (plate.el.complete) place(); else plate.el.addEventListener('load', place, { once: true });
    }
  };
  pass();
  // A message opened in light passes the first time the reader sees it in dark.
  dark.addEventListener('change', pass);
}
