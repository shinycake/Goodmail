// Shared by every part of the message script. MessageScript runs this after the header it writes (READER, FOLD_LABEL,
// HANDLER, and the reader's colors CARD, CARD_LIGHT and SHEET), then each other part in a block of its own, so a part
// sees the header and these names but never another part's.
const PALETTE = document.querySelector('meta[name="goodmail-palette"]')?.content;
const channels = (color) => (color.match(/[\d.]+/g) || []).map(Number);
const luminance = (rgb) => rgb.slice(0, 3).map((value) => {
  const v = value / 255;
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
}).reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
const contrast = (rgb, card) => {
  const [high, low] = [luminance(rgb), luminance(card)].sort((a, b) => b - a);
  return (high + 0.05) / (low + 0.05);
};
