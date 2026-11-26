package {
    import flash.display.DisplayObject;
    import flash.utils.getQualifiedClassName;
    public final class MapDestinations {
        private var destination:Object, origin:Object;
        private var monsterID:String;
        private var requestWorld:Object, requestConnection:Object, requestUser:String;
        private var deadline:int;
        private var checkEntryPad:Boolean;

        // Only cells actually seen in this account's current map instance are cached.
        private var seenWorld:Object, seenConnection:Object, seenUser:String, seenArea:String;
        private var seenPads:Object = {};

        public function get active():Boolean { return destination != null; }
        public function cancel():void {
            destination = origin = null; monsterID = null; checkEntryPad = false;
            requestWorld = requestConnection = null; requestUser = null;
        }

        public static function location(game:Object):Object {
            var w:Object = SkillBag.field(game,"world");
            if (!w || !SkillBag.accountReady(game,SkillBag.field(w,"myAvatar")) ||
                SkillBag.field(w,"mapLoadInProgress")) return null;
            var instance:* = SkillBag.field(w,"strAreaName"), cell:* = SkillBag.field(w,"strFrame");
            var pad:* = SkillBag.field(w,"strPad");
            if (!instance || !cell || !SkillBag.field(w,"strMapName")) return null;
            return {area:String(instance),cell:String(cell),pad:pad ? String(pad) : ""};
        }
        public function bookmark(game:Object):Object {
            var here:Object = location(game);
            return here && here.pad ? here : null;
        }
        public static function mobs(w:Object):Array {
            var rows:Array = [], byID:Object = {};
            var definitions:Object = SkillBag.field(w,"mondefMap");
            for each (var spawn:Object in SkillBag.field(w,"monmap")) {
                var desc:Object = SkillBag.field(definitions,String(SkillBag.field(spawn,"MonID")));
                addMonster(byID,spawn,SkillBag.field(spawn,"strFrame"),SkillBag.field(spawn,"strPad"),
                    SkillBag.field(desc,"strMonName") || SkillBag.field(spawn,"strMonName"));
            }
            for each (var unit:Object in SkillBag.field(w,"monsters")) {
                var data:Object = SkillBag.field(unit,"objData"), leaf:Object = SkillBag.field(unit,"dataLeaf");
                addMonster(byID,data,SkillBag.field(leaf,"strFrame") || SkillBag.field(data,"strFrame"),
                    SkillBag.field(leaf,"strPad") || SkillBag.field(data,"strPad"),SkillBag.field(data,"strMonName"));
            }
            for each (var row:Object in byID) rows.push(row);
            rows.sortOn(["cell","name","id"],[Array.CASEINSENSITIVE,Array.CASEINSENSITIVE,Array.NUMERIC]);
            return rows;
        }
        private static function addMonster(byID:Object, data:Object, cell:*, pad:*, name:*):void {
            var id:* = SkillBag.field(data,"MonMapID");
            if (id == null || !cell) return;
            var previous:Object = byID["#"+id];
            if (!name && previous) name = previous.name;
            if (!name) return;
            if (!pad && previous && previous.cell == cell) pad = previous.pad;
            byID["#"+id] = {id:String(id),name:String(name),cell:String(cell),pad:pad ? String(pad) : ""};
        }
        private function remember(game:Object, here:Object):void {
            var w:Object = SkillBag.field(game,"world"), sfc:Object = SkillBag.field(game,"sfc");
            var user:String = SkillBag.nameOf(game);
            if (w !== seenWorld || sfc !== seenConnection || user != seenUser || (here && here.area != seenArea)) {
                seenPads = {}; seenWorld = w; seenConnection = sfc; seenUser = user;
                seenArea = here ? here.area : null;
            }
            if (here && here.pad) seenPads["#"+here.cell] = here.pad;
        }
        public function begin(game:Object, dest:Object, mob:String, token:uint, now:int):String {
            cancel();
            var here:Object = location(game);
            remember(game,here);
            if (!here || !dest || !dest.area || !dest.cell) return "Enter a map and try again";
            var w:Object = game.world;
            if (mob) {
                if (dest.area != here.area) return "Map changed · scan again";
                var current:Object;
                for each (var spawn:Object in mobs(w)) {
                    if (spawn.id == mob) { current = spawn; break; }
                }
                if (!current) return "Monster is no longer on this map · refresh Mobs";
                dest = {area:here.area,cell:current.cell,pad:current.pad || seenPads["#"+current.cell] || "Left"};
            } else if (!dest.pad) return "Bookmark has no entry pad";
            destination = dest; origin = here; monsterID = mob;
            requestWorld = w; requestConnection = game.sfc; requestUser = SkillBag.nameOf(game);
            deadline = now + 12000;

            var status:String = arrival(w,here);
            if (status) return status;
            if (here.area == dest.area && seenPads["#"+dest.cell] && SkillBag.field(w,"moveToCell") is Function) {
                w.moveToCell(dest.cell,dest.pad,false);
            } else if (SkillBag.field(w,"gotoTown") is Function) {
                // Ask for the exact entry, including on first visit, and honour the returned location.
                checkEntryPad = !mob;
                w.gotoTown(dest.area,dest.cell,dest.pad);
            } else return finish("Map controls unavailable");
            return "Warping to " + dest.area + " · " + dest.cell;
        }
        public function observe(game:Object, token:uint, now:int):String {
            var here:Object = location(game);
            remember(game,here);
            if (!active) return null;
            if (SkillBag.field(game,"world") !== requestWorld || SkillBag.field(game,"sfc") !== requestConnection ||
                SkillBag.nameOf(game) != requestUser) return finish("Travel stopped · account changed");
            if (now >= deadline) return finish("Warp not confirmed · " + destination.area + " / " + destination.cell);
            if (!here) return null;
            if (here.area != destination.area) {
                if (here.area == origin.area) return null;
                return finish("Arrived in " + here.area + " · " + here.cell + " instead");
            }
            var status:String = arrival(game.world,here);
            if (status) return status;
            if (checkEntryPad && here.cell == destination.cell) {
                var pad:String = savedPadOnFrame(SkillBag.field(game.world,"map"),here.cell,destination.pad);
                if (pad && SkillBag.field(game.world,"moveToCell") is Function) {
                    checkEntryPad = false;
                    game.world.moveToCell(here.cell,pad,false);
                    return "Moving to entry pad " + pad;
                }
            }
            if (here.cell != destination.cell && (here.area != origin.area || here.cell != origin.cell))
                return finish("Arrived in " + here.area + " · " + here.cell + " instead");
            return null;
        }
        private static function savedPadOnFrame(map:Object, cell:String, wanted:String):String {
            if (!map || SkillBag.field(map,"currentLabel") !== cell || SkillBag.field(map,"isPlaying") ||
                !(SkillBag.field(map,"getChildAt") is Function)) return null;
            for (var i:int=0; i<int(map.numChildren); i++) {
                var child:DisplayObject = map.getChildAt(i) as DisplayObject;
                if (child && child.name && child.name.toLowerCase() == wanted.toLowerCase() &&
                    SkillBag.field(map,child.name) === child && /(^|::)Pad_\d+$/.test(getQualifiedClassName(child)))
                    return child.name;
            }
            return null;
        }
        private function finish(message:String):String { cancel(); return message; }

        private function arrival(w:Object, here:Object):String {
            if (here.area != destination.area || here.cell != destination.cell) return null;
            if (!monsterID) {
                if (String(here.pad).toLowerCase() != String(destination.pad).toLowerCase()) return null;
                return finish("At " + here.area + " · " + here.cell + ", " + here.pad);
            }
            for each (var unit:Object in w.getMonstersByCell(here.cell)) {
                if (String(SkillBag.field(SkillBag.field(unit,"objData"),"MonMapID")) != monsterID) continue;
                if (!SkillBag.field(unit,"pMC") || !SkillBag.field(unit,"dataLeaf")) break;
                if (Number(unit.dataLeaf.intHP) <= 0) return finish("Monster unavailable");
                w.setTarget(unit);
                return finish("Selected " + unit.objData.strMonName);
            }
            return "Waiting for the selected monster";
        }
    }
}
