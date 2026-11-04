package {
    import flash.desktop.NativeApplication;
    import flash.desktop.SystemIdleMode;
    import flash.display.Loader;
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.InvokeEvent;
    import flash.events.MouseEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.URLRequest;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.system.ApplicationDomain;
    import flash.system.Capabilities;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.utils.ByteArray;

    [SWF(width="960", height="550", frameRate="30", backgroundColor="#101820")]
    public class Main extends Sprite {
        private static const GAME_BASE:String = "https://game.aq.com/game/";

        private var gameLoader:Loader = new Loader();
        private var panel:Sprite = new Sprite();
        private var message:TextField;
        private var openButton:Sprite;
        private var versionLoader:URLLoader;
        private var binaryLoader:URLLoader;
        private var gameVersion:Object;
        private var loading:Boolean = false;
        private var loadPhase:String = "startup";
        private var smokeAssetFile:String;
        private var assetProbe:Loader;
        private var gameClient:MovieClip;

        public function Main() {
            writeStartup("Main constructor");
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
            if (stage) {
                initialize();
            } else {
                addEventListener(Event.ADDED_TO_STAGE, initialize);
            }
        }

        private function initialize(event:Event = null):void {
            removeEventListener(Event.ADDED_TO_STAGE, initialize);
            writeStartup("Stage attached");

            addChild(panel);
            panel.graphics.beginFill(0x101820);
            panel.graphics.drawRect(0, 0, 960, 550);
            panel.graphics.endFill();
            addLabel("AQWorlds Classic", 50, 70, 32);
            addLabel("Tap to open the official game launcher.", 50, 125, 22);
            addLabel("Touch client 0.1.4", 50, 165, 18);
            addLabel(Capabilities.os + " / AIR " + Capabilities.version, 50, 200, 16);
            message = addLabel("Ready", 50, 265, 20);
            message.height = 155;
            message.wordWrap = true;

            openButton = new Sprite();
            openButton.graphics.beginFill(0x257C69);
            openButton.graphics.drawRoundRect(0, 0, 240, 60, 12);
            openButton.graphics.endFill();
            openButton.x = 50;
            openButton.y = 445;
            openButton.buttonMode = true;
            var caption:TextField = new TextField();
            caption.defaultTextFormat = new TextFormat("_sans", 22, 0xFFFFFF, true);
            caption.text = "Open game";
            caption.x = 20;
            caption.y = 14;
            caption.width = 210;
            caption.mouseEnabled = false;
            openButton.addChild(caption);
            panel.addChild(openButton);
            openButton.addEventListener(MouseEvent.CLICK, openGame);

            loaderInfo.uncaughtErrorEvents.addEventListener(
                UncaughtErrorEvent.UNCAUGHT_ERROR, onUnhandledError
            );
            gameLoader.uncaughtErrorEvents.addEventListener(
                UncaughtErrorEvent.UNCAUGHT_ERROR, onUnhandledError
            );
            gameLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onLoaded);
            gameLoader.contentLoaderInfo.addEventListener(ProgressEvent.PROGRESS, onProgress);
            gameLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
            gameLoader.contentLoaderInfo.addEventListener(
                SecurityErrorEvent.SECURITY_ERROR, onLoadError
            );
            writeStartup("UI ready");
            try {
                centerStage();
                stage.addEventListener(Event.RESIZE, centerStage);
                Multitouch.inputMode = MultitouchInputMode.NONE;
                NativeApplication.nativeApplication.systemIdleMode = SystemIdleMode.KEEP_AWAKE;
                writeStartup("Input and screen configured");
            } catch (error:Error) {
                // A device capability failure must leave the launch controls visible.
                writeStartup(error.name + " " + error.errorID + ": " + error.message);
                message.text = "Ready. Device setting: " + error.message;
            }
        }

        private function onInvoke(event:InvokeEvent):void {
            for each (var argument:String in event.arguments) {
                if (argument.indexOf("--smoke-assets=") == 0) {
                    smokeAssetFile = argument.substr(15);
                    if (!/^[A-Za-z0-9_-]+\.swf$/.test(smokeAssetFile)) smokeAssetFile = null;
                }
            }
            if (event.arguments.indexOf("--smoke-game") >= 0 && message != null) {
                openGame(null);
            }
        }

        private function centerStage(event:Event = null):void {
            // Centre SHOW_ALL's letterboxing and preserve the game's touch coordinates.
            if (stage.align != "") stage.align = "";
            if (stage.scaleMode != StageScaleMode.SHOW_ALL) stage.scaleMode = StageScaleMode.SHOW_ALL;
        }

        private function writeStartup(text:String):void {
            trace("AQW-CLASSIC " + text);
            try {
                var stream:FileStream = new FileStream();
                stream.open(File.documentsDirectory.resolvePath("aqw-startup.log"), FileMode.APPEND);
                stream.writeUTFBytes(new Date().toUTCString() + " " + text + "\n");
                stream.close();
            } catch (ignored:Error) {
                // Diagnostics must never block the game.
            }
        }

        private function addLabel(text:String, x:Number, y:Number, size:int):TextField {
            var label:TextField = new TextField();
            label.defaultTextFormat = new TextFormat("_sans", size, 0xFFFFFF);
            label.selectable = false;
            label.mouseEnabled = false;
            label.text = text;
            label.x = x;
            label.y = y;
            label.width = 860;
            label.height = 45;
            panel.addChild(label);
            return label;
        }

        private function openGame(event:MouseEvent):void {
            if (loading) return;
            loading = true;
            openButton.visible = false;
            message.text = "Checking the latest game version...";
            loadPhase = "version request";
            versionLoader = new URLLoader();
            versionLoader.addEventListener(Event.COMPLETE, onVersionLoaded);
            versionLoader.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
            versionLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onLoadError);
            try {
                versionLoader.load(new URLRequest(GAME_BASE + "api/data/gameversion?ver=" + new Date().time));
            } catch (error:Error) {
                showFailure(error.name + " " + error.errorID + "\n" + error.message);
            }
        }

        private function onVersionLoaded(event:Event):void {
            try {
                gameVersion = JSON.parse(String(versionLoader.data));
                var file:String = String(gameVersion.sFile);
                // Only the official endpoint chooses a filename on the fixed HTTPS host.
                if (!/^[A-Za-z0-9_-]+\.swf$/.test(file)) {
                    throw new Error("The game version response has an invalid filename.");
                }
                versionLoader = null;
                loadPhase = "game download";
                message.text = "Downloading the game...";
                binaryLoader = new URLLoader();
                binaryLoader.dataFormat = URLLoaderDataFormat.BINARY;
                binaryLoader.addEventListener(Event.COMPLETE, onGameDownloaded);
                binaryLoader.addEventListener(ProgressEvent.PROGRESS, onProgress);
                binaryLoader.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                binaryLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onLoadError);
                writeStartup("Game version " + gameVersion.sVersion + ": " + file);
                binaryLoader.load(new URLRequest(GAME_BASE + "gamefiles/" + file +
                    "?ver=" + encodeURIComponent(String(gameVersion.sVersion))));
            } catch (error:Error) {
                showFailure(error.name + " " + error.errorID + "\n" + error.message);
            }
        }

        private function onGameDownloaded(event:Event):void {
            try {
                var bytes:ByteArray = binaryLoader.data as ByteArray;
                if (bytes == null || bytes.length < 8 ||
                    (bytes[0] != 0x46 && bytes[0] != 0x43 && bytes[0] != 0x5A) ||
                    bytes[1] != 0x57 || bytes[2] != 0x53) {
                    throw new Error("The game download is not a valid SWF file.");
                }
                binaryLoader = null;
                loadPhase = "game initialization";
                message.text = "Starting the game...";
                var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
                context.allowCodeImport = true;
                context.parameters = {isweb: "false", dosignup: "false", sLang: ""};
                writeStartup("Loading official game bytes in the application domain: " + bytes.length);
                // URL Loader.load() puts the remote SWF in another security sandbox.
                // Its Stage access then throws #2070. Interpreter builds can import the
                // trusted official game bytes into the app's own domain instead.
                gameLoader.loadBytes(bytes, context);
            } catch (error:Error) {
                showFailure(error.name + " " + error.errorID + "\n" + error.message);
            }
        }

        private function onLoaded(event:Event):void {
            try {
                var game:MovieClip = gameLoader.content as MovieClip;
                if (game == null) throw new Error("The game did not provide a MovieClip.");
                // Supply the same bootstrap parameters as Artix's Loader4.
                var parameters:Object = game["params"];
                if (parameters == null) {
                    parameters = {};
                    game["params"] = parameters;
                }
                parameters.sURL = GAME_BASE;
                // loadBytes has an app:/ origin. Override the asset base before
                // ADDED_TO_STAGE so the game fetches its external files over HTTPS.
                parameters.sFilePath = GAME_BASE + "gamefiles/";
                parameters.sTitle = gameVersion.sTitle;
                parameters.vars = gameVersion;
                parameters.isWeb = false;
                parameters.doSignup = false;
                parameters.isEU = String(gameVersion.isEU) == "true";
                parameters.test = false;
                parameters.loginURL = GAME_BASE + "api/login/now";
                parameters.sBG = gameVersion.sBG;
                parameters.sLang = "";
                game["titleDomain"] = ApplicationDomain.currentDomain;
                game.x = 0;
                game.y = 0;
                stage.addChildAt(game, 0);
                gameClient = game;
                centerStage();
                panel.visible = false;
                loadPhase = "game running";
                writeStartup("Game client attached; login and gameplay remain unverified");
                writeStartup("Viewport centred: align=" + stage.align + "; scale=" + stage.scaleMode);
                writeStartup("Official asset base: " + game["sFilePath"]);
                if (smokeAssetFile != null) checkExternalAssets();
            } catch (error:Error) {
                showFailure(error.name + " " + error.errorID + "\n" + error.message);
            }
        }

        private function onProgress(event:ProgressEvent):void {
            if (event.bytesTotal > 0) {
                message.text = "Downloading game " +
                    Math.round(100 * event.bytesLoaded / event.bytesTotal) + "%";
            }
        }

        private function checkExternalAssets():void {
            var gameClass:Class = ApplicationDomain.currentDomain.getDefinition("Game") as Class;
            var base:String = String(gameClass["serverFilePath"]);
            if (base != GAME_BASE + "gamefiles/") throw new Error("The game did not accept the official asset base.");
            var assetLoaderClass:Class = ApplicationDomain.currentDomain.getDefinition("types.AirLoader") as Class;
            assetProbe = new assetLoaderClass() as Loader;
            assetProbe.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUnhandledError);
            assetProbe.contentLoaderInfo.addEventListener(Event.COMPLETE, function(event:Event):void {
                writeStartup("External asset check passed: " + smokeAssetFile);
            });
            assetProbe.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
            assetProbe.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onLoadError);
            writeStartup("Checking external assets through the official AirLoader");
            assetProbe.load(new URLRequest(base + "interface/Assets/" + smokeAssetFile),
                gameClient["assetsContext"] as LoaderContext);
        }

        private function onLoadError(event:Event):void {
            showFailure(event.toString());
        }

        private function onUnhandledError(event:UncaughtErrorEvent):void {
            event.preventDefault();
            var error:Error = event.error as Error;
            var text:String = "Unhandled game error";
            if (error) {
                text = error.name + " " + error.errorID + "\n" + error.message;
            }
            showFailure(text);
        }

        private function showFailure(text:String):void {
            writeStartup("Load failed (" + loadPhase + "): " + text);
            panel.visible = true;
            if (panel.parent == this) {
                setChildIndex(panel, numChildren - 1);
            }
            message.text = "Could not start the game (" + loadPhase + ").\n" + text +
                "\nClose and reopen the app before trying again.";
            trace("AQW-PROBE " + text);
        }
    }
}
