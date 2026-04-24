var appLaunched = false;
var appShown = false;
var appHidden = false;

App({
    onLaunch: function(options) {
        appLaunched = true;
        console.log("Hello MiniApp launched");
    },
    onShow: function() {
        appShown = true;
    },
    onHide: function() {
        appHidden = true;
    },
    onError: function(msg) {
        console.error("App error: " + msg);
    }
});
