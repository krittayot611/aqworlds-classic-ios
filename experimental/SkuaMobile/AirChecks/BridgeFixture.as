package {
    import flash.display.Sprite;
    import flash.desktop.NativeApplication;
    public final class BridgeFixture extends Sprite {
        private var bridge:SkuaGameBridge;
        private var nextId:int;
        private var checks:int;
        public function BridgeFixture() {
            try {
                var world:Object = {strMapName:"battleon", health:42, names:["one","two"]};
                world.jump = function(map:String):String { this.strMapName = map; return this.strMapName; };
                bridge = new SkuaGameBridge({world:world}, "fixture-session");
                check(command("getGameObject", ["world.strMapName"]).result === '"battleon"', "JSON string result");
                check(command("getGameObject", ["world.health"]).result === "42", "numeric result");
                check(command("getGameObjectKey", ["world.names",1]).result === '"two"', "array key");
                check(command("isNull", ["world.missing"]).result === "true", "missing property");
                check(command("callGameFunction", ["world.jump","yulgar"]).result === '"yulgar"' && world.strMapName === "yulgar", "function owner and arguments");
                check(!command("getGameObject", ["world.constructor"]).ok, "reserved path rejected");
                check(!command("getGameObject", ["world[0]"]).ok, "invalid path rejected");
                check(!command("unsupported", []).ok, "unsupported command reported");
                check(!command("callGameFunction", ["world.missing"]).ok, "missing function reported");
                var stale:Object = JSON.parse(bridge.execute(JSON.stringify({v:1,session:"old-session",id:100,method:"isNull",args:["world"]})));
                check(!stale.ok && stale.session === "old-session" && stale.id === 100, "stale session correlation");
                check(!JSON.parse(bridge.execute("{")).ok, "malformed JSON reported");
                bridge.detach();
                check(!command("getGameObject", ["world.health"]).ok, "detached game rejected");
                trace("PASS AIR bridge: " + checks + " dispatcher checks; fixture only, no live game.");
                NativeApplication.nativeApplication.exit(0);
            } catch(error:Error) {
                trace("FAIL AIR bridge: " + error.getStackTrace());
                NativeApplication.nativeApplication.exit(1);
            }
        }
        private function command(method:String,args:Array):Object {
            var id:int = ++nextId;
            var response:Object = JSON.parse(bridge.execute(JSON.stringify({v:1,session:"fixture-session",id:id,method:method,args:args})));
            if (response.id !== id || response.session !== "fixture-session" || response.v !== 1)
                throw new Error("Response correlation failed");
            return response;
        }
        private function check(value:Boolean,label:String):void {
            if (!value) throw new Error(label);
            ++checks; trace("PASS AIR bridge: " + label);
        }
    }
}
