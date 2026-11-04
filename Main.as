package {
    import flash.desktop.NativeApplication;
    import flash.desktop.SystemIdleMode;
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.PNGEncoderOptions;
    import flash.display.Loader;
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.display.StageDisplayState;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.InvokeEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Matrix;
    import flash.geom.Rectangle;
    import flash.net.URLRequest;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.utils.ByteArray;

    [SWF(width="960", height="550", frameRate="30", backgroundColor="#101820")]
    public class Main extends Sprite {
        [Embed(source="Background.jpg")]
        private static const BackgroundImage:Class;
        private var backdrop:Sprite = new Sprite();
        private var backdropTexture:BitmapData;

        private static const GAME_BASE:String = "https://game.aq.com/game/";

        private var gameLoader:Loader = new Loader();
        private var panel:Sprite = new Sprite();
        private var message:TextField;
        private var versionLoader:URLLoader;
        private var binaryLoader:URLLoader;
        private var gameVersion:Object;
        private var loading:Boolean = false;
        private var loadPhase:String = "startup";
        private var smokeAssetFile:String;
        private var assetProbe:Loader;
        private var gameClient:MovieClip;
        private var loadingPreviewSaved:Boolean = false;
        private var nativeWidth:Number;
        private var nativeHeight:Number;
        private var sourceBounds:Rectangle;

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

            createBackdrop();
            addChild(panel);
            var title:TextField = addLabel("AQWorlds Classic", 50, 205, 32);
            title.setTextFormat(new TextFormat("_sans", 32, 0xFFFFFF, false, null, null, null, null, "center"));
            message = addLabel("Loading...", 50, 265, 20);
            message.defaultTextFormat = new TextFormat("_sans", 20, 0xFFFFFF, false, null, null, null, null, "center");
            message.height = 155;
            message.wordWrap = true;

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
            writeStartup("Touch client 0.1.7: loading screen ready");
            try {
                centerStage();
                stage.addEventListener(Event.RESIZE, centerStage);
                Multitouch.inputMode = MultitouchInputMode.NONE;
                NativeApplication.nativeApplication.systemIdleMode = SystemIdleMode.KEEP_AWAKE;
                writeStartup("Input and screen configured");
            } catch (error:Error) {
                // A device capability failure must not prevent automatic startup.
                writeStartup(error.name + " " + error.errorID + ": " + error.message);

            }
            // Start on the first frame, after the UI and launch arguments are ready.
            addEventListener(Event.ENTER_FRAME, startAutomatically);
        }

        private function startAutomatically(event:Event):void {
            removeEventListener(Event.ENTER_FRAME, startAutomatically);
            if (smokeAssetFile != null) captureLoadingPreview();
            writeStartup("Automatic game launch");
            openGame();
        }

        private function onInvoke(event:InvokeEvent):void {
            for each (var argument:String in event.arguments) {
                if (argument.indexOf("--smoke-assets=") == 0) {
                    smokeAssetFile = argument.substr(15);
                    if (!/^[A-Za-z0-9_-]+\.swf$/.test(smokeAssetFile)) smokeAssetFile = null;
                }
            }
            // INVOKE can arrive after the first frame. Capture whichever loading
            // state is currently visible without delaying normal automatic startup.
            if (smokeAssetFile != null && message != null && panel.visible) captureLoadingPreview();
        }

        private function createBackdrop():void {
            backdropTexture = (new BackgroundImage() as Bitmap).bitmapData;
            backdrop.mouseEnabled = false;
            backdrop.mouseChildren = false;
            stage.addChildAt(backdrop, 0);
            writeStartup("Background ready: original texture; pointer input disabled");
        }

        private function captureLoadingPreview():void {
            if (loadingPreviewSaved) return;
            var snapshot:BitmapData = new BitmapData(Math.max(1, stage.stageWidth), Math.max(1, stage.stageHeight), false, 0x101820);
            snapshot.draw(stage);
            var stream:FileStream = new FileStream();
            stream.open(File.documentsDirectory.resolvePath("aqw-loading.png"), FileMode.WRITE);
            stream.writeBytes(snapshot.encode(snapshot.rect, new PNGEncoderOptions()));
            stream.close();
            snapshot.dispose();
            loadingPreviewSaved = true;
            writeStartup("Loading background preview saved");
        }

        private function centerStage(event:Event = null):void {
            // Legacy map rasterisation and walking expect an untransformed game
            // at the Stage origin and the original 960 x 550 coordinate system.
            if (isNaN(nativeWidth) || nativeWidth <= 0) {
                stage.align = StageAlign.TOP_LEFT;
                stage.scaleMode = StageScaleMode.NO_SCALE;
                nativeWidth = stage.stageWidth;
                nativeHeight = stage.stageHeight;
            }
            stage.align = "";
            stage.scaleMode = StageScaleMode.SHOW_ALL;
            scaleX = scaleY = 1;
            x = y = 0;
            if (gameClient != null) {
                gameClient.scaleX = gameClient.scaleY = 1;
                gameClient.x = gameClient.y = 0;
                gameClient.scrollRect = null;
            }
            var fit:Number = Math.min(nativeWidth / 960, nativeHeight / 550);
            var width:Number = nativeWidth / fit;
            var height:Number = nativeHeight / fit;
            sourceBounds = new Rectangle((960 - width) / 2, (550 - height) / 2, width, height);
            try {
                stage.fullScreenSourceRect = sourceBounds;
                if (stage.displayState == StageDisplayState.NORMAL) {
                    stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
                }
            } catch (unsupported:Error) {
                // Keep the game's coordinate system intact on runtimes which
                // cannot show a background outside the original canvas.
                writeStartup("Full-screen background unavailable: " + unsupported.message);
            }
            var cover:Number = Math.max(width / backdropTexture.width, height / backdropTexture.height);
            var fill:Matrix = new Matrix(cover, 0, 0, cover,
                (960 - backdropTexture.width * cover) / 2,
                (550 - backdropTexture.height * cover) / 2);
            backdrop.graphics.clear();
            backdrop.graphics.beginBitmapFill(backdropTexture, fill, false, true);
            if (gameClient == null) {
                backdrop.graphics.drawRect(sourceBounds.x, sourceBounds.y, width, height);
            } else {
                // The game must be Stage child zero. Draw only the surrounding
                // margins in the overlay so neither its image nor input is covered.
                if (sourceBounds.x < 0) {
                    backdrop.graphics.drawRect(sourceBounds.x, 0, -sourceBounds.x, 550);
                    backdrop.graphics.drawRect(960, 0, -sourceBounds.x, 550);
                }
                if (sourceBounds.y < 0) {
                    backdrop.graphics.drawRect(sourceBounds.x, sourceBounds.y, width, -sourceBounds.y);
                    backdrop.graphics.drawRect(sourceBounds.x, 550, width, -sourceBounds.y);
                }
            }
            backdrop.graphics.endFill();
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

        private function openGame():void {
            if (loading) return;
            loading = true;
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
                game.scrollRect = null;
                stage.addChildAt(game, 0);
                writeStartup("Game is Stage child zero; background input disabled");
                gameClient = game;
                centerStage();
                panel.visible = false;
                loadPhase = "game running";
                writeStartup("Game client attached; login and gameplay remain unverified");
                writeStartup("Viewport centred: align=" + stage.align + "; scale=" + stage.scaleMode);
                writeStartup("Game viewport: x=" + game.x + "; y=" + game.y + "; scale=" + game.scaleX +
                    "; native=" + stage.stageWidth + "x" + stage.stageHeight);
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
                var regression:Object = MapRegression.run(gameClient);
                if (regression == null) throw new Error("The map regression check did not complete.");
                writeStartup("Map regression passed: " + JSON.stringify(regression));
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
