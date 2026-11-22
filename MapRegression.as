package {
    import flash.display.Bitmap;
    import flash.display.MovieClip;
    import flash.display.StageScaleMode;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.system.ApplicationDomain;
    import flash.utils.Timer;

    // Run only by the release smoke check; never creates a game session.
    public final class MapRegression {
        // Read the attached client first. Exercise two distinct names and logout
        // with a local world so CI never changes an account or joins a server.
        public static function checkReader(live:CurrentMapReader, config:File, note:Function):void {
            var input:FileStream = new FileStream();
            input.open(config, FileMode.READ);
            var names:Array;
            try { names = JSON.parse(input.readUTFBytes(input.bytesAvailable)) as Array; }
            finally { input.close(); }
            if (!names || names.length != 2 || names[0] == names[1]) throw new Error("Invalid map test data.");
            live.read(function(initial:String, failure:String):void {
                if (failure != null) { note("MAP_ERROR " + failure); return; }
                note("MAP_LIVE " + JSON.stringify(initial));
                var fixture:Object = {world:{strMapName:names[0]}};
                var reader:CurrentMapReader = new CurrentMapReader(function():Object { return fixture; });
                var index:int = 0;
                function received(map:String, error:String):void {
                    if (error != null) { note("MAP_ERROR " + error); reader.dispose(); return; }
                    note("MAP_SAMPLE " + JSON.stringify(map));
                    ++index;
                    if (index == 3) { reader.dispose(); return; }
                    fixture.world = index == 1 ? {strMapName:names[1]} : null;
                    reader.read(received);
                }
                reader.read(received);
            });
        }

        public static function run(game:MovieClip):Object {
            if (game.stage.scaleMode != StageScaleMode.SHOW_ALL ||
                game.stage.stageWidth != 960 || game.stage.stageHeight != 550 ||
                game.stage.getChildAt(0) != game || game.x != 0 || game.y != 0 ||
                game.scaleX != 1 || game.scaleY != 1 || game.scrollRect != null) {
                throw new Error("The legacy game coordinate system changed.");
            }
            var worldClass:Class = ApplicationDomain.currentDomain.getDefinition("World") as Class;
            var previous:Object = worldClass["currentInstance"];
            var host:MovieClip = new MovieClip();
            host.visible = false;
            host["ui"] = null;
            host["litePreference"] = {data: {bSmoothBG: false}};
            host["chatF"] = {mute: {timer: new Timer(1000)}, unmuteMe: function(event:Object):void {}};
            game.addChild(host);
            var world:MovieClip;
            try {
                world = new worldClass(host) as MovieClip;
                host["world"] = world;
                host.addChild(world);
                var map:MovieClip = world["map"] as MovieClip;
                var ground:MovieClip = new MovieClip();
                ground.graphics.beginFill(0x39A8D8);
                ground.graphics.drawRect(0, 0, 960, 500);
                ground.graphics.endFill();
                ground.graphics.beginFill(0xE83E8C);
                ground.graphics.drawRect(0, 0, 30, 500);
                ground.graphics.endFill();
                map.addChild(ground);

                // Negative control: the transform used by 0.1.6 must fail.
                host.x = 64;
                host.scaleX = host.scaleY = 0.75;
                world["applySmoothBG"]();
                var broken:Bitmap = map.getChildByName("bmp0") as Bitmap;
                var chars:MovieClip = world["CHARS"] as MovieClip;
                var wrong:Point = chars.globalToLocal(new Point(400, 300));
                if (broken == null || broken.bitmapData.getPixel(10, 100) == 0xE83E8C ||
                    (Math.abs(wrong.x - 400) < 0.01 && Math.abs(wrong.y - 300) < 0.01)) {
                    throw new Error("The regression check did not detect the old transform.");
                }

                host.x = 0;
                host.scaleX = host.scaleY = 1;
                world["applySmoothBG"]();
                var restored:Bitmap = map.getChildByName("bmp0") as Bitmap;
                var target:Point = chars.globalToLocal(new Point(400, 300));
                if (restored == null || restored.bitmapData.getPixel(10, 100) != 0xE83E8C ||
                    Math.abs(target.x - 400) > 0.01 || Math.abs(target.y - 300) > 0.01) {
                    throw new Error("Map rasterisation or movement coordinates are incorrect.");
                }
                return {old_transform_detected: true, map_left_edge_restored: true,
                    movement_coordinates_restored: true};
            } finally {
                if (world != null) {
                    world["cleanupMap"]();
                    world["killTimers"]();
                    world["killListeners"]();
                }
                if (host.parent != null) host.parent.removeChild(host);
                worldClass["currentInstance"] = previous;
            }
            return null;
        }
    }
}
