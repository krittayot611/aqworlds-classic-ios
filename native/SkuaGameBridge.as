package {
    /** Runs only on the AIR thread. The host supplies the actual loaded game object. */
    public final class SkuaGameBridge {
        private var game:Object;
        private var session:String;
        public function SkuaGameBridge(game:Object, session:String) {
            if (game == null || !session) throw new ArgumentError("A game and session are required.");
            this.game = game; this.session = session;
        }
        public function detach():void { game = null; }
        public function execute(json:String):String {
            var reply:Object = {v:1,session:session,id:0,ok:false};
            try {
                if (json.length > 65536) throw new ArgumentError("Request too large.");
                var r:Object = JSON.parse(json);
                if (r == null || r.v !== 1 || !(r.session is String) || !(r.args is Array) ||
                    !(r.id is Number) || r.id <= 0 || r.id > 9007199254740991 || r.id % 1 != 0)
                    throw new ArgumentError("Invalid bridge envelope.");
                reply.id = r.id; reply.session = r.session;
                if (r.session !== session) throw new ArgumentError("Stale game session.");
                if (game == null) throw new Error("Game detached.");
                var args:Array = r.args; var value:*;
                switch (r.method) {
                    case "currentMap":
                        count(args, 0);
                        var world:Object = ("world" in game) ? game["world"] : null;
                        var map:* = world != null && ("strMapName" in world) ? world["strMapName"] : null;
                        reply.result = encode(map is String && map.length > 0 ? map : null);
                        break;
                    case "getGameObject":
                        count(args, 1); reply.result = encode(resolve(path(args[0]))); break;
                    case "getGameObjectKey":
                        count(args, 2); value = resolve(path(args[0]));
                        if (value == null) throw new Error("Game object is unavailable.");
                        validKey(String(args[1])); reply.result = encode(value[args[1]]); break;
                    case "isNull":
                        count(args, 1); var parts:Array = path(args[0]);
                        try { reply.result = (resolve(parts) == null).toString(); }
                        catch (missing:ReferenceError) { reply.result = "true"; }
                        break;
                    case "callGameFunction":
                        if (!args.length) throw new ArgumentError("Function path required.");
                        var fnPath:Array = path(args[0]); var key:String = fnPath.pop();
                        var owner:* = resolve(fnPath);
                        if (owner == null || !(owner[key] is Function)) throw new Error("Game function is unavailable.");
                        var fn:Function = owner[key] as Function;
                        reply.result = encode(fn.apply(owner, args.slice(1))); break;
                    default: throw new ArgumentError("Unsupported bridge method: " + r.method);
                }
                reply.ok = true;
            } catch (error:Error) { reply.error = error.message; }
            return JSON.stringify(reply);
        }
        private function count(args:Array, expected:int):void {
            if (args.length != expected) throw new ArgumentError("Unexpected argument count.");
        }
        private function encode(value:*):String { return value === undefined ? "null" : JSON.stringify(value); }
        private function validKey(key:String):void {
            if (key == "constructor" || key == "prototype" || key == "__proto__") throw new ArgumentError("Invalid game path key.");
        }
        private function path(value:*):Array {
            if (!(value is String) || !value.length || value.length > 1024) throw new ArgumentError("Invalid game path.");
            var parts:Array = String(value).split(".");
            if (parts.length > 64) throw new ArgumentError("Game path is too deep.");
            for each (var key:String in parts) {
                if (!/^[$A-Za-z_][$A-Za-z_0-9]*$/.test(key)) throw new ArgumentError("Use dotted paths or getGameObjectKey.");
                validKey(key);
            }
            return parts;
        }
        private function resolve(parts:Array):* {
            var value:* = game;
            for each (var key:String in parts) { if (value == null) return null; value = value[key]; }
            return value;
        }
    }
}
