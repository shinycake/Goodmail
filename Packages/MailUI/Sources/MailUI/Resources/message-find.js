// What the find bar asks of a message after the web view has found a match: where the match is, so the conversation
// can scroll to it, and the way to forget it. The names live in this world only, apart from the page.
window.goodmailFind = {
  // The selected match's box as [x, y, width, height] in the page's own units, or null with no selection.
  matchBox() {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
    const box = selection.getRangeAt(0).getBoundingClientRect();
    return [box.x, box.y, box.width, box.height];
  },
  clear() {
    window.getSelection()?.removeAllRanges();
  },
};
