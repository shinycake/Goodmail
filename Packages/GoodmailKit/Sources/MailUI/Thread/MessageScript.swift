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

          // 3. Fit wide layouts, such as 600-pixel newsletters, to the card's width.
          const fit = () => {
            document.body.style.zoom = '';
            const width = document.documentElement.clientWidth;
            const content = document.body.scrollWidth;
            if (content > width + 1) document.body.style.zoom = (width / content).toFixed(4);
          };

          // 4. Report what the native side needs: the height to size the card, and whether remote content is blocked.
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
