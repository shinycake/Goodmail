import Foundation

/// Runs in Goodmail's own content world after each message loads. Email JavaScript stays off (ADR-003); this script
/// is ours, and the sender's page can neither see nor call it.
nonisolated enum MessageScript {
    static let handlerName = "goodmail"

    /// `foldLabel` is the accessibility label of the control that shows folded quotes.
    static func source(foldLabel: String) -> String {
        """
        (() => {
          const FOLD_LABEL = \(jsonString(foldLabel));
          const BLOCKS = 'p,div,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,pre,dd,dt,section,article,header,footer,center';

          // 1. Direction per block: where the sender set none, each block follows its own first strong character.
          //    A Hebrew reply above an English quote, or one Hebrew line in English mail, each reads its own way.
          if (!document.body.hasAttribute('dir')) document.body.setAttribute('dir', 'auto');
          for (const el of document.body.querySelectorAll(BLOCKS)) {
            if (!el.hasAttribute('dir')) el.setAttribute('dir', 'auto');
          }

          // 2. Fold quoted history: the first quote, and everything after it at its level.
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
            const strong = range.toString().match(/[\\u0590-\\u08FF\\uFB1D-\\uFDFF\\uFE70-\\uFEFF]|[A-Za-z\\u00C0-\\u024F\\u0370-\\u03FF\\u0400-\\u04FF]/);
            return strong && /[\\u0590-\\u08FF\\uFB1D-\\uFDFF\\uFE70-\\uFEFF]/.test(strong[0]) ? 'rtl' : 'ltr';
          };
          if (fold && hasContentBefore(fold)) {
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

          // 3. Contrast, for the adaptive palette (MessagePalette): text whose color fails WCAG AA (4.5:1) on the card
          //    in an appearance gets a mark for it and a replacement, which the palette's rules apply in that
          //    appearance only. Grays become the appearance's own text color; other colors keep their hue, mixed
          //    toward white for dark or black for light until they pass, so red stays red and a link stays blue.
          //    White backgrounds are marked too. Every color is read before any mark lands, since a mark changes
          //    what its descendants inherit.
          if (document.querySelector('meta[name="goodmail-palette"]')?.content === 'adaptive') {
            const APPEARANCES = [
              { name: 'dark', card: [28, 28, 30], toward: 255 },
              { name: 'light', card: [242, 242, 247], toward: 0 },
            ];
            const channels = (color) => (color.match(/[\\d.]+/g) || []).map(Number);
            const luminance = (rgb) => rgb.slice(0, 3).map((value) => {
              const v = value / 255;
              return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
            }).reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
            const contrast = (rgb, card) => {
              const [high, low] = [luminance(rgb), luminance(card)].sort((a, b) => b - a);
              return (high + 0.05) / (low + 0.05);
            };
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

          // 4. Fit wide layouts, such as 600-pixel newsletters, to the card's width.
          const fit = () => {
            document.body.style.zoom = '';
            const width = document.documentElement.clientWidth;
            const content = document.body.scrollWidth;
            if (content > width + 1) document.body.style.zoom = (width / content).toFixed(4);
          };

          // 5. Report what the native side needs: the height to size the card, and whether remote content is blocked.
          const remote = /^(https?:)?\\/\\//i;
          const hasRemote = [...document.querySelectorAll('img[src], img[srcset], [background], link[href]')]
            .some((el) => remote.test(el.getAttribute('src') || el.getAttribute('srcset')
              || el.getAttribute('background') || el.getAttribute('href') || ''))
            || /url\\(\\s*['"]?(https?:)?\\/\\//i.test(document.documentElement.innerHTML);
          let lastHeight = 0;
          const report = () => {
            // The body, not the document: the document is never shorter than the view, so it can't shrink back.
            const style = getComputedStyle(document.body);
            const height = Math.ceil(document.body.getBoundingClientRect().bottom + window.scrollY
              + parseFloat(style.marginBottom || '0'));
            if (height === lastHeight) return;
            lastHeight = height;
            window.webkit.messageHandlers.\(handlerName).postMessage({ height, hasRemote });
          };
          fit();
          new ResizeObserver(report).observe(document.body);
          document.addEventListener('toggle', report, true);
          report();
        })();
        """
    }

    private static func jsonString(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        return data.map { String(decoding: $0.dropFirst().dropLast(), as: UTF8.self) } ?? "\"\""
    }
}
