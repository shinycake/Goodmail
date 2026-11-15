extension ImageTrustRule {
    /// Domains where anyone can sign up for an address, so a domain rule for one would load every stranger's images.
    /// The reader is never offered these from a message, and Settings warns before saving one. Not exhaustive: it
    /// covers the providers most mail comes from, including the Israeli ones.
    static let publicMailDomains: Set<String> = [
        // Apple, Google, Microsoft
        "icloud.com", "me.com", "mac.com", "gmail.com", "googlemail.com",
        "outlook.com", "hotmail.com", "live.com", "msn.com", "passport.com",
        "outlook.co.il", "hotmail.co.il", "hotmail.co.uk", "hotmail.fr", "hotmail.de", "live.co.uk",
        // Yahoo and AOL
        "yahoo.com", "ymail.com", "rocketmail.com", "yahoo.co.uk", "yahoo.fr", "yahoo.de", "yahoo.co.jp",
        "aol.com", "aim.com",
        // Privacy and independent providers
        "proton.me", "protonmail.com", "pm.me", "tutanota.com", "tuta.io", "fastmail.com", "zoho.com",
        "hey.com", "mail.com", "email.com", "gmx.com", "gmx.net", "gmx.de", "web.de",
        // Regional
        "yandex.com", "yandex.ru", "mail.ru", "qq.com", "163.com", "126.com", "naver.com",
        "walla.co.il", "walla.com", "012.net.il", "013.net", "bezeqint.net", "netvision.net.il", "zahav.net.il",
    ]
}
