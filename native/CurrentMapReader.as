package {
    import flash.accessibility.AccessibilityProperties;
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public final class CurrentMapReader extends Sprite {
        private var context:ExtensionContext;
        private var game:Function;
        private var label:TextField = new TextField();
        private var done:Function;

        public function CurrentMapReader(currentGame:Function) {
            game = currentGame;
            context = ExtensionContext.createExtensionContext("com.aqw.classic.margins", "current-map");
            if (context == null) throw new Error("Map extension unavailable.");
            context.addEventListener(StatusEvent.STATUS, onStatus);
            graphics.beginFill(0x10202D, .90);
            graphics.drawRoundRect(0, 0, 150, 38, 12, 12);
            graphics.endFill();
            label.defaultTextFormat = new TextFormat("_sans", 17, 0xFFFFFF, true, null, null, null, null, "center");
            label.width = 150; label.height = 34; label.y = 6; label.selectable = false;
            label.text = "Map";
            addChild(label);
            mouseChildren = false;
            buttonMode = true;
            accessibilityProperties = new AccessibilityProperties();
            accessibilityProperties.name = "Read current map";
            addEventListener(MouseEvent.CLICK, onTap);
        }

        private function onTap(event:MouseEvent):void {
            if (done != null) return;
            label.text = "Reading…";
            read(function(map:String, error:String):void {
                label.text = error != null ? "Tap to retry" : (map ? map : "No map yet");
                accessibilityProperties.name = "Read current map. " + label.text;
                if (error != null) trace("AQW map reader: " + error);
            });
        }

        public function read(callback:Function):void {
            if (done != null || context == null) { callback(null, "Map reader unavailable."); return; }
            done = callback;
            try {
                if (context.call("readMap") !== true) finish(null, "Map reader is busy.");
            } catch (error:Error) { finish(null, error.message); }
        }

        private function onStatus(event:StatusEvent):void {
            if (done == null) return;
            if (event.code == "map.result") { finish(event.level ? event.level : null, null); return; }
            if (event.code == "map.error") { finish(null, event.level); return; }
            if (event.code != "map.request") return;
            var request:Object = JSON.parse(event.level);
            var reply:String;
            try {
                if (request.method !== "currentMap") throw new Error("Unknown map operation.");
                var source:Object = game();
                var bridge:SkuaGameBridge = new SkuaGameBridge(source == null ? {} : source, request.session);
                reply = bridge.execute(event.level);
            } catch (error:Error) {
                reply = JSON.stringify({v:1, session:request.session, id:request.id, ok:false, error:error.message});
            }
            context.call("mapReply", event.level, reply);
        }

        private function finish(map:String, error:String):void {
            var callback:Function = done;
            done = null;
            if (callback != null) callback(map, error);
        }

        public function dispose():void {
            removeEventListener(MouseEvent.CLICK, onTap);
            if (context != null) {
                context.removeEventListener(StatusEvent.STATUS, onStatus);
                context.dispose();
                context = null;
            }
            finish(null, "Map reader closed.");
        }
    }
}
