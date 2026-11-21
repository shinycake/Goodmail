// Size: the body's default text is the system's body style, and on the Mac that style sizes its font itself, whatever
// the reader's zoom or a font size says. So before anything reads the page's fonts, the default becomes the system
// font at the size the style gives it now, in pixels (MessageDocument's goodmail-sized rules): the zoom scales that,
// and the reader's text size still sets it.
const style = document.createElement('span');
style.style.font = '-apple-system-body';
document.body.appendChild(style);
document.documentElement.style.setProperty('--goodmail-body-size', getComputedStyle(style).fontSize);
style.remove();
document.documentElement.classList.add('goodmail-sized');
