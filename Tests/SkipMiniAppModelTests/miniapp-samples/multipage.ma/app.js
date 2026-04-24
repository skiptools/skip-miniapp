App({
    globalData: { userInfo: null },
    onLaunch: function(options) {
        console.log("MultiPage app launched");
    },
    onShow: function() {
        console.log("MultiPage app shown");
    },
    onHide: function() {
        console.log("MultiPage app hidden");
    }
});
