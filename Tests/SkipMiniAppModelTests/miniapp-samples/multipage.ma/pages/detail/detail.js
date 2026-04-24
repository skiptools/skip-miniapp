Page({
    data: { itemId: null },
    onLoad: function(options) {
        this.data.itemId = options ? options.id : null;
        console.log("Detail loaded with id: " + this.data.itemId);
    }
});
