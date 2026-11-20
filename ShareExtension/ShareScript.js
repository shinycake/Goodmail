// Safari runs this in the page being shared and hands its result to the Share extension, so the message can take the
// page's title as its subject (SharedItems.swift).
var ShareScript = function () {};

ShareScript.prototype = {
    run: function (parameters) {
        parameters.completionFunction({ title: document.title, url: document.URL });
    },
    finalize: function () {},
};

var ExtensionPreprocessingJS = new ShareScript();
