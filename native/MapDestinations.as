package {
    import flash.display.DisplayObject;
    import flash.display.InteractiveObject;
    import flash.events.MouseEvent;


    /** Navigation uses the same Join, Go To and portal controls as the game. */
    public final class MapDestinations {
        private var session:uint;
        private var destination:Object;
        private var attempted:Boolean;
        private var monsterID:String;
        private var fromArea:String;
        private var ownerWorld:Object, connection:Object, user:String;
        private var deadline:int;

        public function get active():Boolean { return destination != null; }
        public function cancel():void {
            destination = null; monsterID = null; attempted = false;
            ownerWorld = connection = null; user = null;
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
            if (!here || !here.pad) return null;
            return here;
        }
        public static function mobs(w:Object):Array {
            var rows:Array = [], byID:Object = {};
            var definitions:Object = SkillBag.field(w,"mondefMap");
            for each (var spawn:Object in SkillBag.field(w,"monmap")) {
                var desc:Object = SkillBag.field(definitions,String(SkillBag.field(spawn,"MonID")));
                addMonster(byID, spawn, SkillBag.field(spawn,"strFrame"),
                    SkillBag.field(desc,"strMonName") || SkillBag.field(spawn,"strMonName"));
            }
            for each (var unit:Object in SkillBag.field(w,"monsters")) {
                var data:Object = SkillBag.field(unit,"objData"), leaf:Object = SkillBag.field(unit,"dataLeaf");
                addMonster(byID,data,SkillBag.field(leaf,"strFrame") || SkillBag.field(data,"strFrame"),
                    SkillBag.field(data,"strMonName"));
            }
            for each (var row:Object in byID) rows.push(row);
            rows.sortOn(["cell","name","id"],[Array.CASEINSENSITIVE,Array.CASEINSENSITIVE,Array.NUMERIC]);
            return rows;
        }
        private static function addMonster(byID:Object, data:Object, cell:*, name:*):void {
            var id:* = SkillBag.field(data,"MonMapID");
            if (id != null && name && cell) byID["#"+id] = {id:String(id),name:String(name),cell:String(cell)};
        }
        public function begin(game:Object, dest:Object, mob:String, token:uint, now:int):String {
            cancel();
            var here:Object = location(game);
            if (!here || !dest || !dest.area || !dest.cell) return "Enter a map and try again";
            if (mob && dest.area != here.area) return "Map changed · scan again";
            if (mob) {
                var current:Object;
                for each (var spawn:Object in mobs(game.world)) {
                    if (spawn.id == mob) { current = spawn; break; }
                }
                if (!current) return "Monster is no longer on this map · refresh Mobs";
                dest = {area:here.area,cell:current.cell};
            }
            destination = dest; monsterID = mob; session = token;
            ownerWorld = game.world; connection = game.sfc; user = SkillBag.nameOf(game);
            fromArea = here.area; deadline = now + 12000;
            if (here.area != dest.area) {
                game.world.gotoTown(dest.area,dest.cell,dest.pad);
                return "Joining " + dest.area;
            }
            return advance(game,here,now);
        }
        public function observe(game:Object, token:uint, now:int):String {
            if (token != session) {
                session = token;
                // A normal instance join can replace the avatar while preserving the connection.
                if (active && (SkillBag.field(game,"world") !== ownerWorld || SkillBag.field(game,"sfc") !== connection ||
                    SkillBag.nameOf(game) !== user)) return finish("Travel stopped · account changed");
            }
            var here:Object = location(game);
            if (!active) return null;
            if (now >= deadline) return finish("Travel timed out · " + destination.area + " / " + destination.cell);
            if (!here) return null;
            if (here.area != destination.area) {
                if (here.area == fromArea && fromArea != destination.area) return null;
                return finish("Travel stopped · map changed");
            }
            return advance(game,here,now);
        }
        private function finish(message:String):String { cancel(); return message; }

        private function advance(game:Object, here:Object, now:int):String {
            var w:Object = game.world;
            if (here.cell == destination.cell) {
                if (!monsterID && here.pad == destination.pad)
                    return finish("At " + here.area + " · " + here.cell + ", " + here.pad);
                if (monsterID) {
                    for each (var unit:Object in w.getMonstersByCell(here.cell)) {
                        if (String(SkillBag.field(unit.objData,"MonMapID")) != monsterID) continue;
                        if (!unit.pMC || !unit.dataLeaf) break;
                        if (Number(unit.dataLeaf.intHP) <= 0) return finish("Monster unavailable");
                        w.setTarget(unit);
                        return finish("Selected " + unit.objData.strMonName);
                    }
                    return "Waiting for the selected monster";
                }
            }
            if (attempted) return null;
            attempted = true;
            if (tapPortal(game,destination,monsterID != null)) return "Warping to " + destination.cell;
            if ("getUsersByCell" in w && "goto" in w && !SkillBag.field(SkillBag.field(w,"map"),"nogoto")) {
                for each (var other:Object in w.getUsersByCell(destination.cell)) {
                    var leaf:Object = SkillBag.field(other,"dataLeaf");
                    var who:* = SkillBag.field(leaf,"uoName") || SkillBag.field(leaf,"strUsername") ||
                        SkillBag.field(SkillBag.field(other,"objData"),"strUsername");
                    if (!who || other === w.myAvatar || (!monsterID && SkillBag.field(leaf,"strPad") != destination.pad)) continue;
                    w["goto"](String(who));
                    return "Warping to " + destination.cell;
                }
            }
            return finish("Direct warp unavailable · " + destination.cell);
        }
        private static function tapPortal(game:Object, dest:Object, anyPad:Boolean):Boolean {
            for each (var entry:Object in SkillBag.field(game.world,"arrEvent")) {
                var control:InteractiveObject = entry as InteractiveObject;
                if (!control || !control.mouseEnabled || !control.hasEventListener(MouseEvent.CLICK) ||
                    SkillBag.field(entry,"tCell") != dest.cell || (!anyPad && SkillBag.field(entry,"tPad") != dest.pad) ||
                    SkillBag.field(entry,"enabled") === false) continue;
                var parent:DisplayObject = control;
                while (parent && parent != game && parent.visible && parent.alpha > 0) parent = parent.parent;
                if (parent != game) continue;
                control.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true,false));
                return true;
            }
            return false;
        }
    }
}
