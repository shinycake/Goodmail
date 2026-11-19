import Foundation

/// The message script's dark pass, for bodies whose sender painted their own colors (`MessagePalette.painted` and
/// `.sendersOwn`). It reads the page as it shows in dark and turns it over the way Gmail does, so a newsletter made
/// for a white page reads like the rest of the app:
/// - A light background, white or a pale gray or pastel, becomes a dark one of the same hue: white becomes the sheet,
///   a paler color a shade above it. Mid and dark colors, such as a brand's navy banner, stay as the sender set them.
/// - A light border turns over the same way, so dividers don't glare.
/// - Text that is then too faint for WCAG AA (4.5:1) on what it sits on lightens, keeping its hue: navy body text
///   turns pale, a link stays blue, and white text on a kept navy banner stays white.
/// - Images, and anything drawn over a background image, stay as they are, since the pass can't see what they show.
///
/// Each change is a mark with its replacement color, which the palette's rules apply in dark appearance only. The
/// sun button turns the card light and the sender's own colors show again, without a reload.
nonisolated enum MessageDarkPass {
    /// The dark of a white page: the gray white turns into, a shade above the dark card so the email still reads as a
    /// sheet. The script turns a lightness of 1 into this same gray.
    static let sheet = "rgb(43, 43, 43)"

    /// Runs inside the message script, which defines `PALETTE`, `channels`, `luminance` and `contrast`. Every color is
    /// read before any mark lands, since a mark changes what the elements around it show.
    static let source = """
        if (PALETTE === 'painted' || PALETTE === 'sendersOwn') {
          const dark = matchMedia('(prefers-color-scheme: dark)');
          const CARD = [28, 28, 30];
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
          const SHEET = oklab([43, 43, 43])[0];
          // A light color's dark counterpart, or null for a color dark enough to keep. Lightness turns over from
          // white at the sheet, the hue stays, and the chroma softens so a pastel becomes a deep tint, not a glow.
          const turned = (color) => {
            const [L, a, b] = oklab(color);
            return L < 0.8 ? null : srgb([SHEET + (1 - L) * 0.75, a * 0.7, b * 0.7]);
          };
          const over = (color, below) => color.length < 4 || color[3] >= 1 ? color.slice(0, 3)
            : color.slice(0, 3).map((v, i) => Math.round(v * color[3] + below[i] * (1 - color[3])));
          const opaque = (color) => color.length >= 3 && (color[3] ?? 1) > 0;
          const css = (color) => `rgb(${color.join(', ')})`;
          // Grays become white; other colors mix toward white until they pass, so red stays red.
          const lightened = (ink, backdrop) => {
            if (Math.max(...ink) - Math.min(...ink) < 40) return 'rgb(255, 255, 255)';
            for (let mix = 0.05; ; mix += 0.05) {
              const candidate = ink.map((v) => Math.round(v + (255 - v) * Math.min(mix, 1)));
              if (mix >= 1 || contrast(candidate, backdrop) >= 4.5) return css(candidate);
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
            // What each element's content shows on in dark once the marks land; null over a background image.
            const backdrops = new Map();
            const marks = [];
            for (const el of [document.body, ...document.body.querySelectorAll('*')]) {
              const style = getComputedStyle(el);
              const below = backdrops.has(el.parentElement) ? backdrops.get(el.parentElement) : page;
              let backdrop = below;
              const paper = channels(style.backgroundColor);
              if (style.backgroundImage !== 'none') {
                backdrop = null;
              } else if (opaque(paper) && (below || (paper[3] ?? 1) >= 1)) {
                const shown = over(paper, below ?? paper);
                const replacement = turned(shown);
                if (replacement) marks.push([el, 'paper', css(replacement)]);
                backdrop = replacement ?? shown;
              }
              backdrops.set(el, backdrop);
              if (backdrop && hasText(el)) {
                const ink = channels(style.color);
                if (opaque(ink)) {
                  const shown = over(ink, backdrop);
                  if (contrast(shown, backdrop) < 4.5) marks.push([el, 'ink', lightened(shown, backdrop)]);
                }
              }
              if (below) {
                const sides = SIDES.map((side) => {
                  const color = style.getPropertyValue(`border-${side}-color`);
                  const value = channels(color);
                  const shows = parseFloat(style.getPropertyValue(`border-${side}-width`)) > 0 && opaque(value);
                  const replacement = shows ? turned(over(value, below)) : null;
                  return [side, replacement ? css(replacement) : color, replacement !== null];
                });
                if (sides.some(([, , changed]) => changed)) marks.push([el, 'border', sides]);
              }
            }
            for (const [el, kind, value] of marks) {
              el.setAttribute(`data-goodmail-dark-${kind}`, '');
              if (kind === 'border') {
                for (const [side, color] of value) el.style.setProperty(`--goodmail-dark-border-${side}`, color);
              } else {
                el.style.setProperty(`--goodmail-dark-${kind}`, value);
              }
            }
          };
          pass();
          // A message opened in light passes the first time the reader sees it in dark.
          dark.addEventListener('change', pass);
        }
        """
}
