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
    import flash.utils.getTimer;

    public final class CurrentMapReader extends Sprite {
        private var context:ExtensionContext;
        private var game:Function;
        private var label:TextField = new TextField();
        private var done:Function;
        private var rotation:SkuaRotation;
        private var bag:SkillBag = new SkillBag();
        private var poll:Timer = new Timer(1250);
        private var lastBag:String;
        private var travelPoll:Timer = new Timer(125);
        private var navigator:MapDestinations = new MapDestinations();
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
                travelPoll.addEventListener(TimerEvent.TIMER, checkTravel);
                NativeApplication.nativeApplication.addEventListener(Event.DEACTIVATE, onBackground);
                NativeApplication.nativeApplication.addEventListener(Event.ACTIVATE, onForeground);
            }
            var shown:Boolean = context.call("showTools", verify) === true;
            if (shown) refreshBag();
            return shown;
        }

        private function onBackground(event:Event):void {
            foreground = false;
            stopTravel();
            poll.stop();
            if (rotation && rotation.running) rotation.stop("Stopped · app in background");
        }

        private function onForeground(event:Event):void {
            foreground = true; poll.start(); refreshBag();
        }
        private function refreshBag(event:TimerEvent = null):void {
            if (!foreground || !context) return;
            var info:Object;
            var source:Object;
            try { source = game(); info = bag.snapshot(source); }
            catch (error:Error) { info = bag.snapshot(null); }
            if (!navigator.active) navigator.observe(source,getTimer());
            var payload:String = JSON.stringify(info);
            if (payload !== lastBag) {
                context.call("updateTools","bag",payload,false);
                lastBag = payload;
            }
        }

        private function travelState(problem:String = null):void {
            var active:Boolean = navigator.active;
            if (active == travelPoll.running && !problem) return;
            if (active) travelPoll.start(); else travelPoll.stop();
            if (context) context.call("updateTools","travel",problem || "",active);
        }
        private function checkTravel(event:TimerEvent):void {
            try { travelState(navigator.observe(game(),getTimer())); }
            catch (error:Error) { navigator.cancel(); travelState("The game could not complete this jump."); }
        }
        private function stopTravel():void { navigator.cancel(); travelState(); }
        private function mapCommand(request:Object):void {
            var source:Object = game();
            var loc:Object = MapDestinations.location(source);
            var token:uint = bag.session(source);
            if (!foreground || token != uint(request.session) || !loc) {
                if (request.action == "mobs" || request.action == "marks") {
                    context.call("updateTools","destinations",JSON.stringify({mode:request.action,session:request.session,
                        rows:[],problem:"Enter a map and refresh this list."}),false);
                } else context.call("updateTools","notice","Enter a map and try again.",false);
                return;
            }
            if (request.action == "travel") {
                if (rotation.running) rotation.stop();
                travelState(navigator.begin(source,request.dest,request.mob,getTimer()));
                return;
            }
            var panel:Object = {mode:request.action, session:token, location:loc};
            if (request.action == "mobs") panel.rows = MapDestinations.mobs(source.world);
            if (request.action == "saveMark") {
                panel.location = navigator.bookmark(source);
                if (!panel.location) { context.call("updateTools","notice","Waiting for the entrance pad",false); return; }
            }
            context.call("updateTools","destinations",JSON.stringify(panel),false);
        }

        private function botCommand(message:String):void {
            if (!rotation) return;
            try {
                var request:Object = JSON.parse(message);
                if (request.action == "start" && !foreground) rotation.stop("Stopped · app in background");
                else if (request.action == "start") {
                    stopTravel();
                    rotation.start(request.steps as Array,request["auto"] === true,request.classId,uint(request.session),
                                   request.resetOnTarget === true,int(request.timeoutMs));
                }
                else if (request.action == "bag") { lastBag = null; refreshBag(); }
                else if (request.action == "stop") rotation.stop();
                else if (request.action == "cancelTravel") stopTravel();
                else if (["mobs","marks","saveMark","travel"].indexOf(request.action) >= 0) {
                    try { mapCommand(request); }
                    catch (navigationError:Error) {
                        navigator.cancel(); travelState("Map controls unavailable");
                    }
                }
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
            travelPoll.stop(); travelPoll.removeEventListener(TimerEvent.TIMER,checkTravel);
            navigator.cancel();
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
