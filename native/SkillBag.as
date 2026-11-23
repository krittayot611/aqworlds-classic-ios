package {
    // Only bag classes cross into UIKit. Account identity stays inside the game.
    public final class SkillBag {
        private var world:Object, avatar:Object, user:String;
        private var epoch:uint;
        public static function field(obj:Object, key:String):* {
            return obj != null && key in obj ? obj[key] : null;
        }
        public static function nameOf(game:Object):String {
            var name:* = field(field(game,"sfc"),"myUserName");
            return name ? String(name).toLowerCase() : "";
        }
        public static function accountReady(game:Object, player:Object):Boolean {
            var user:String = nameOf(game);
            if (!user || !player) return false;
            var character:* = field(field(player,"objData"),"strUsername") || field(field(player,"dataLeaf"),"strUsername");
            return !character || String(character).toLowerCase() == user;
        }
        public static function classId(item:Object):String {
            var kind:* = field(item,"sType");
            var isClass:Boolean = kind ? String(kind).toLowerCase() == "class" : field(item,"sES") == "ar";
            var id:Number = Number(field(item,"ItemID"));
            return isClass && id > 0 && id == int(id) ? String(int(id)) : "";
        }
        public static function equipped(item:Object):Boolean {
            var flag:* = field(item,"bEquip");
            return flag === true || String(flag) == "1" || String(flag).toLowerCase() == "true";
        }
        public static function equippedId(player:Object):String {
            var items:Array = field(player,"items") as Array;
            for each (var item:Object in items) {
                var id:String = classId(item);
                if (id && equipped(item)) return id;
            }
            return "";
        }
        public static function owned(player:Object, id:String):Object {
            var items:Array = field(player,"items") as Array;
            for each (var item:Object in items) if (classId(item) == id && id) return item;
            return null;
        }
        public function session(game:Object):uint {
            var w:Object = field(game,"world");
            var a:Object = field(w,"myAvatar");
            var u:String = nameOf(game);
            if (world !== w || avatar !== a || user !== u) {
                ++epoch; world = w; avatar = a; user = u;
            }
            return epoch;
        }
        public function snapshot(game:Object):Object {
            var token:uint = session(game);
            var classes:Array = [], seen:Object = {};
            var items:Array = field(avatar,"items") as Array;
            var worn:String = "";
            if (accountReady(game,avatar) && field(world,"strMapName") && field(world,"strFrame") && items) {
                for each (var item:Object in items) {
                    var id:String = classId(item);
                    if (!id) continue;
                    if (equipped(item)) worn = id;
                    var name:* = field(item,"sName");
                    if (!name || seen[id]) continue;
                    seen[id] = true;
                    classes.push({id:id,name:String(name)});
                }
                classes.sortOn(["name","id"],[Array.CASEINSENSITIVE,Array.NUMERIC]);
            }
            return {session:token, classes:classes, equipped:worn};
        }
    }
}
