var pageData = { message: "Welcome to Hello MiniApp" };

Page({
    onLoad: function(options) {
        console.log("Index page loaded");
    },
    onShow: function() {
        console.log("Index page shown");
    },
    onReady: function() {
        console.log("Index page ready");
    },
    onHide: function() {
        console.log("Index page hidden");
    },
    onUnload: function() {
        console.log("Index page unloaded");
    }
});
