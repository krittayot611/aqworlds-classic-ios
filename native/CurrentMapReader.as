package {
    import flash.accessibility.AccessibilityProperties;
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.TimerEvent;
    import flash.utils.Timer;

    public final class CurrentMapReader extends Sprite {
        private var context:ExtensionContext;
        private var game:Function;
        private var label:TextField = new TextField();
        private var done:Function;
        private var rotation:SkuaRotation;
        private var bag:SkillBag = new SkillBag();
        private var poll:Timer = new Timer(1250);
        private var lastBag:String;
        private var foreground:Boolean = true;

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

        public function showTools(verify:Boolean):Boolean {
            if (!rotation) {
                rotation = new SkuaRotation(game, function(text:String, active:Boolean):void {
                    context.call("updateTools", "state", text, active);
                },bag);
                poll.addEventListener(TimerEvent.TIMER, refreshBag);
                poll.start();
                NativeApplication.nativeApplication.addEventListener(Event.DEACTIVATE, onBackground);
                NativeApplication.nativeApplication.addEventListener(Event.ACTIVATE, onForeground);
            }
            var shown:Boolean = context.call("showTools", verify) === true;
            if (shown) refreshBag();
            return shown;
        }

        private function onBackground(event:Event):void {
            foreground = false;
            poll.stop();
            if (rotation && rotation.running) rotation.stop("Stopped · app in background");
        }

        private function onForeground(event:Event):void {
            foreground = true; poll.start(); refreshBag();
        }
        private function refreshBag(event:TimerEvent = null):void {
            if (!foreground || !context) return;
            var info:Object;
            try { info = bag.snapshot(game()); }
            catch (error:Error) { info = bag.snapshot(null); }
            var payload:String = JSON.stringify(info);
            if (payload !== lastBag) {
                context.call("updateTools","bag",payload,false);
                lastBag = payload;
            }
        }

        private function botCommand(message:String):void {
            if (!rotation) return;
            try {
                var request:Object = JSON.parse(message);
                if (request.action == "start" && !foreground) rotation.stop("Stopped · app in background");
                else if (request.action == "start") rotation.start(request.steps as Array,request["auto"] === true,request.classId,uint(request.session));
                else if (request.action == "bag") { lastBag = null; refreshBag(); }
                else if (request.action == "stop") rotation.stop();
                else if (request.action == "map" && done == null) {
                    read(function(map:String, error:String):void {
                        if (context) context.call("updateTools", "map", error ? "Tap to retry" : (map || ""), false);
                    });
                }
            } catch (error:Error) { rotation.stop("Controls unavailable"); }
        }

        public function read(callback:Function):void {
            if (done != null || context == null) { callback(null, "Map reader unavailable."); return; }
            done = callback;
            try {
                if (context.call("readMap") !== true) finish(null, "Map reader is busy.");
            } catch (error:Error) { finish(null, error.message); }
        }

        private function onStatus(event:StatusEvent):void {
            if (event.code == "bot.command") { botCommand(event.level); return; }
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
            NativeApplication.nativeApplication.removeEventListener(Event.DEACTIVATE,onBackground);
            NativeApplication.nativeApplication.removeEventListener(Event.ACTIVATE,onForeground);
            poll.stop(); poll.removeEventListener(TimerEvent.TIMER,refreshBag);
            if (rotation) { rotation.dispose(); rotation = null; }
            if (context != null) {
                context.removeEventListener(StatusEvent.STATUS, onStatus);
                context.dispose();
                context = null;
            }
            finish(null, "Map reader closed.");
        }
    }
}
