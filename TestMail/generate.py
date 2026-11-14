#!/usr/bin/env python3
"""Writes the test-mail corpus: synthetic messages that imitate what real clients send, with the encodings and
quoting styles that break mail readers. A DEBUG build files them into the test account (`-GoodmailSeedTestMail`),
and Gmail's responses for them are recorded as fixtures (ADR-010).

Each directory is one thread; its files are the messages in order. Run from anywhere: `TestMail/generate.py`.
"""
import base64
import pathlib
import struct
import zlib
from email.charset import Charset, QP, BASE64
from email.header import Header
from email.mime.application import MIMEApplication
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr, format_datetime
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).parent
ME = "tester@example.com"  # The recorder swaps the real test address for this one.
START = datetime(2026, 10, 12, 8, 30, tzinfo=timezone(timedelta(hours=3)))


def addr(name, email, charset="utf-8"):
    if name.isascii():
        return formataddr((name, email))
    return f"{Header(name, charset).encode()} <{email}>"


def headers(msg, sender, to, subject, minutes, msgid, reply_to=None, subject_charset="utf-8"):
    msg["From"] = sender
    msg["To"] = to
    msg["Subject"] = Header(subject, subject_charset)
    msg["Date"] = format_datetime(START + timedelta(minutes=minutes))
    msg["Message-ID"] = f"<{msgid}@goodmail.test>"
    if reply_to:
        msg["In-Reply-To"] = f"<{reply_to[-1]}@goodmail.test>"
        msg["References"] = " ".join(f"<{r}@goodmail.test>" for r in reply_to)
    return msg


def text(body, charset="utf-8", encoding=QP):
    cs = Charset(charset)
    cs.body_encoding = encoding
    part = MIMEText("", "plain")
    part.set_payload(body.encode(charset if charset != "iso-8859-8-i" else "iso-8859-8"))
    part.set_charset(cs) if charset != "iso-8859-8-i" else None
    if charset == "iso-8859-8-i":
        del part["Content-Type"], part["Content-Transfer-Encoding"]
        part["Content-Type"] = 'text/plain; charset="iso-8859-8-i"'
        part["Content-Transfer-Encoding"] = "base64"
        part.set_payload(base64.encodebytes(body.encode("iso-8859-8")).decode())
    elif encoding == QP:
        # set_charset doesn't re-encode an existing bytes payload; do it explicitly.
        import quopri
        del part["Content-Transfer-Encoding"]
        part["Content-Transfer-Encoding"] = "quoted-printable"
        part.set_payload(quopri.encodestring(body.encode(charset)).decode("ascii"))
    return part


def html(body):
    return MIMEText(body, "html", "utf-8")


def alternative(plain, rich):
    msg = MIMEMultipart("alternative")
    msg.attach(MIMEText(plain, "plain", "utf-8"))
    msg.attach(html(rich))
    return msg


def png(width=24, height=24, rgb=(0x16, 0xA7, 0x66)):
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def pdf():
    return (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj "
            b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")


def write(thread, messages):
    folder = ROOT / thread
    folder.mkdir(exist_ok=True)
    for old in folder.glob("*.eml"):
        old.unlink()
    for index, msg in enumerate(messages, 1):
        (folder / f"{index:02}.eml").write_bytes(msg.as_bytes())


DANA = addr("Dana Levi", "dana@example.com")
YAEL = addr("יעל כהן", "yael@example.co.il")
AVI = addr("אבי מזרחי", "avi@example.co.il")
TESTER = addr("Goodmail Tester", ME)

# 1. A legacy Israeli client: windows-1255, quoted-printable, encoded-word subject.
write("hebrew-windows-1255", [headers(
    text("שלום,\r\nמצורף הסיכום מהפגישה ביום שלישי. סעיף 3 (תקציב 2027) עדיין פתוח.\r\n"
         "אפשר לענות עד 15:00, או להתקשר ל-03-5551234.\r\n\r\nתודה,\r\nאבי", "windows-1255"),
    addr("אבי מזרחי", "avi@example.co.il", "windows-1255"), TESTER, "סיכום פגישה – תקציב 2027", 0, "w1255-1",
    subject_charset="windows-1255")])

# 2. Logical Hebrew declared as iso-8859-8-i, base64.
write("hebrew-iso-8859-8-i", [headers(
    text("תזכורת: התור לרופא ביום רביעי בשעה 09:40.\r\nכתובת: רחוב הרצל 12, תל אביב.", "iso-8859-8-i"),
    YAEL, TESTER, "תזכורת: תור לרופא", 30, "iso88598i-1")])

# 3. Gmail web thread: English start, Hebrew reply above the English quote, then a mixed reply.
g1 = alternative(
    "Hi Yael,\n\nCan we move the review to Thursday 14:00? Agenda: Q4 numbers, hiring, the RTL bug (#482).\n\nDana",
    '<div dir="ltr">Hi Yael,<div><br></div><div>Can we move the review to Thursday 14:00? Agenda: Q4 numbers, '
    'hiring, the RTL bug (<a href="https://example.com/issues/482">#482</a>).</div><div><br></div><div>Dana</div></div>')
g2 = alternative(
    "בטח, יום חמישי ב-14:00 מתאים. אני אביא את הנתונים של Q4.\n\nOn Mon, Oct 12, 2026 at 8:30 AM Dana Levi <dana@example.com> wrote:\n> Hi Yael,\n>\n> Can we move the review to Thursday 14:00?\n",
    '<div dir="rtl">בטח, יום חמישי ב-14:00 מתאים. אני אביא את הנתונים של Q4.</div><br><div class="gmail_quote">'
    '<div dir="ltr" class="gmail_attr">On Mon, Oct 12, 2026 at 8:30 AM Dana Levi &lt;<a href="mailto:dana@example.com">'
    'dana@example.com</a>&gt; wrote:<br></div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;'
    'border-left:1px solid rgb(204,204,204);padding-left:1ex"><div dir="ltr">Hi Yael,<div><br></div><div>Can we move '
    'the review to Thursday 14:00? Agenda: Q4 numbers, hiring, the RTL bug (#482).</div><div><br></div><div>Dana</div>'
    '</div></blockquote></div>')
g3 = alternative(
    "Great — see you Thursday. אגב, the deck is at https://example.com/deck (גרסה 3).\n",
    '<div dir="ltr">Great — see you Thursday. אגב, the deck is at <a href="https://example.com/deck">'
    'https://example.com/deck</a> (גרסה 3).</div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">'
    'On Mon, Oct 12, 2026 at 9:10 AM יעל כהן &lt;yael@example.co.il&gt; wrote:<br></div><blockquote class="gmail_quote">'
    '<div dir="rtl">בטח, יום חמישי ב-14:00 מתאים. אני אביא את הנתונים של Q4.</div><br><div class="gmail_quote">'
    '<blockquote class="gmail_quote"><div dir="ltr">Hi Yael,<div><br></div><div>Can we move the review to Thursday '
    '14:00?</div></div></blockquote></div></blockquote></div>')
write("gmail-mixed-thread", [
    headers(g1, DANA, f"{YAEL}, {TESTER}", "Review → Thursday?", 60, "gm-1"),
    headers(g2, YAEL, f"{DANA}, {TESTER}", "Re: Review → Thursday?", 100, "gm-2", ["gm-1"]),
    headers(g3, DANA, f"{YAEL}, {TESTER}", "Re: Review → Thursday?", 130, "gm-3", ["gm-1", "gm-2"]),
])

# 4. Outlook: Hebrew HTML with dir=rtl on the body, a divRplyFwdMsg reply header, and Word's markup.
outlook = alternative(
    "היי,\nהקובץ המעודכן נמצא בתיקייה המשותפת. שימו לב לשינוי בעמוד 4.\n\nFrom: Dana Levi <dana@example.com>\nSent: Monday, October 12, 2026 11:02\nSubject: Quarterly report\n\nPlease send the updated file.",
    '<html dir="rtl"><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><style>p.MsoNormal'
    '{margin:0cm;font-size:11pt;font-family:"Calibri",sans-serif}</style></head><body lang="HE" dir="rtl">'
    '<div class="WordSection1"><p class="MsoNormal" dir="RTL">היי,</p><p class="MsoNormal" dir="RTL">הקובץ המעודכן '
    'נמצא בתיקייה המשותפת. שימו לב לשינוי בעמוד 4 (Revenue YoY +12%).</p><p class="MsoNormal" dir="RTL">&nbsp;</p>'
    '<div style="border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0cm 0cm 0cm"><div id="divRplyFwdMsg" '
    'dir="ltr"><p class="MsoNormal"><b>From:</b> Dana Levi &lt;dana@example.com&gt;<br><b>Sent:</b> Monday, '
    'October 12, 2026 11:02<br><b>Subject:</b> Quarterly report</p></div></div><p class="MsoNormal" dir="LTR">Please '
    'send the updated file.</p></div></body></html>')
write("outlook-hebrew-reply", [headers(outlook, YAEL, f"{DANA}, {TESTER}", "RE: Quarterly report", 200, "ol-1")])

# 5. Apple Mail: blockquote type=cite, Hebrew reply over a Hebrew quote.
apple = alternative(
    "מעולה, תודה!\n\n> ב-12 באוק׳ 2026, בשעה 12:40, אבי מזרחי <avi@example.co.il> כתב/ה:\n>\n> הנה התמונות מהטיול.\n",
    '<html><body dir="auto"><div dir="rtl">מעולה, תודה!</div><div dir="rtl"><br><blockquote type="cite">ב-12 באוק׳ '
    '2026, בשעה 12:40, אבי מזרחי &lt;avi@example.co.il&gt; כתב/ה:<br><br></blockquote></div><blockquote type="cite">'
    '<div dir="rtl">הנה התמונות מהטיול.</div></blockquote></body></html>')
write("apple-mail-reply", [headers(apple, YAEL, f"{AVI}, {TESTER}", "Re: תמונות מהטיול", 260, "am-1")])

# 6. A newsletter: table layout, remote images and a tracking pixel that must stay blocked.
newsletter = alternative(
    "This week at Example Co: the new release, three talks, and a sale.",
    '<html><body style="margin:0;background:#f4f4f4"><table width="100%" cellpadding="0" cellspacing="0"><tr><td '
    'align="center"><table width="600" style="background:#fff"><tr><td><img src="https://images.example.com/banner.png" '
    'width="600" alt="Example Co"></td></tr><tr><td style="padding:24px;font:16px Helvetica">This week: the new '
    'release, three talks, and a sale. <a href="https://example.com/news?utm_source=mail">Read more</a></td></tr>'
    '</table></td></tr></table><img src="https://track.example.com/open.gif?u=123" width="1" height="1"></body></html>')
write("newsletter", [headers(newsletter, addr("Example Co", "news@example.com"), TESTER, "This week at Example Co",
                             300, "nl-1")])

# 7. An inline image (cid:) and a PDF attachment.
related = MIMEMultipart("related")
related.attach(html('<div dir="rtl">מצורף הלוגו החדש: <img src="cid:logo@goodmail.test" width="24" height="24"> '
                    'ובקובץ ה-PDF הפרטים.</div>'))
logo = MIMEImage(png(), "png")
logo.add_header("Content-ID", "<logo@goodmail.test>")
logo.add_header("Content-Disposition", "inline", filename="logo.png")
related.attach(logo)
mixed = MIMEMultipart("mixed")
mixed.attach(related)
attachment = MIMEApplication(pdf(), "pdf")
attachment.add_header("Content-Disposition", "attachment", filename=("utf-8", "", "הצעת מחיר.pdf"))
mixed.attach(attachment)
write("inline-image-and-pdf", [headers(mixed, AVI, TESTER, "לוגו חדש + הצעת מחיר", 330, "img-1")])

# 8. Plain text with "> " quoting and mixed directions on single lines.
write("plain-quoted-mixed", [headers(
    text("I agree with Avi. ההחלטה: deploy ביום ראשון at 09:00.\n\n> On Oct 12, Avi wrote:\n> נעשה deploy ביום ראשון?\n"
         ">> Dana wrote:\n>> Can we ship v2.1 this week?\n", "utf-8"),
    DANA, f"{AVI}, {TESTER}", "Re: v2.1 deploy", 360, "pq-1")])

# 9. A back-and-forth for the chat layout: a signature, a quick follow-up, a reply sent from a phone, a file, and
#    inline answers to an older message after a pause.
def reply_text(new, attribution, quoted):
    return new + "\n\n" + attribution + "\n" + "".join(f"> {line}\n" for line in quoted.split("\n"))


c1 = text("Hey! Are we still on for Saturday? I was thinking the farmers market at 10, then brunch.\n\n-- \n"
          "Dana Levi\nProduct, Example Inc.\n")
c2 = text("Also, can you bring the picnic blanket?\n")
c3 = text(reply_text("Yes to both! 10 works.\n\nSent from my iPhone",
                     "On Mon, Oct 12, 2026 at 9:02 AM Dana Levi <dana@example.com> wrote:",
                     "Also, can you bring the picnic blanket?"))
c4 = MIMEMultipart("mixed")
c4.attach(text("Here's the map they posted.\n"))
map_pdf = MIMEApplication(pdf(), "pdf")
map_pdf.add_header("Content-Disposition", "attachment", filename="Market map.pdf")
c4.attach(map_pdf)
c5 = text("On Mon, Oct 12, 2026 at 9:20 AM Goodmail Tester <tester@example.com> wrote:\n> Yes to both!\nAmazing.\n\n"
          "> 10 works.\nLet's say 10:15, parking is a pain.\n\n> Sent from my iPhone\n")
c6 = text("Deal 👍\n")
write("chat-weekend-plan", [
    headers(c1, DANA, TESTER, "Saturday?", 0, "chat-1"),
    headers(c2, DANA, TESTER, "Re: Saturday?", 2, "chat-2", ["chat-1"]),
    headers(c3, TESTER, DANA, "Re: Saturday?", 20, "chat-3", ["chat-1", "chat-2"]),
    headers(c4, TESTER, DANA, "Re: Saturday?", 21, "chat-4", ["chat-1", "chat-2", "chat-3"]),
    headers(c5, DANA, TESTER, "Re: Saturday?", 150, "chat-5", ["chat-1", "chat-2", "chat-3"]),
    headers(c6, TESTER, DANA, "Re: Saturday?", 155, "chat-6", ["chat-1", "chat-2", "chat-3", "chat-5"]),
])

# 10. A Hebrew group thread for the chat layout, with a Hebrew Gmail attribution and an iPhone signature.
h1 = text("היי לכולם, מי מגיע לארוחת שישי? אני מכינה שקשוקה.\n")
h2 = text(reply_text("אני בפנים! אביא חלה.",
                     "בתאריך יום ב׳, 12 באוק׳ 2026 ב-8:30 מאת יעל כהן <yael@example.co.il>:",
                     "היי לכולם, מי מגיע לארוחת שישי? אני מכינה שקשוקה."))
h3 = text("גם אני מגיע 🙂 אפשר להביא יין?\n\nנשלח מה-iPhone שלי\n")
h4 = text("בטח! תביא אדום.\n")
h5 = text("ואל תשכחו, מתחילים ב-19:30.\n")
group = f"{YAEL}, {AVI}, {TESTER}"
write("chat-hebrew-group", [
    headers(h1, YAEL, f"{AVI}, {TESTER}", "ארוחת שישי", 0, "heb-1"),
    headers(h2, AVI, group, "Re: ארוחת שישי", 5, "heb-2", ["heb-1"]),
    headers(h3, TESTER, f"{YAEL}, {AVI}", "Re: ארוחת שישי", 12, "heb-3", ["heb-1", "heb-2"]),
    headers(h4, YAEL, group, "Re: ארוחת שישי", 14, "heb-4", ["heb-1", "heb-2", "heb-3"]),
    headers(h5, YAEL, group, "Re: ארוחת שישי", 15, "heb-5", ["heb-1", "heb-2", "heb-3", "heb-4"]),
])
