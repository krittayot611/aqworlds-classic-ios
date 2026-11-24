package {
    import flash.display.DisplayObject;
    import flash.geom.Rectangle;

    /** Navigation uses the same Join, Go To and walking controls as the game. */
    public final class MapDestinations {
        private var session:uint;
        private var area:String;
        private var trail:Array = [];
        private var doors:Object = {};
        private var destination:Object;
        private var monsterID:String;
        private var fromArea:String, waitingAt:String;
        private var deadline:int, nextCheck:int;

        public function get active():Boolean { return destination != null; }
        public function cancel():void { destination = null; monsterID = null; waitingAt = null; }

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
            record(here);
            here.route = trail.concat();
            return here;
        }
        private function record(here:Object):void {
            if (area != here.area) { area = here.area; trail = []; doors = {}; }
            if (!here.pad) return;
            for (var i:int = trail.length - 1; i >= 0; i--) {
                if (trail[i].cell == here.cell && trail[i].pad == here.pad) {
                    trail.length = i+1;
                    return;
                }
            }
            if (trail.length >= 64) trail.shift();
            trail.push({cell:here.cell,pad:here.pad});
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
            destination = dest; monsterID = mob; session = token;
            fromArea = here.area; deadline = now + 45000; nextCheck = 0;
            if (here.area != dest.area) {
                game.world.gotoTown(dest.area,"Enter","Spawn");
                return "Joining " + dest.area;
            }
            return advance(game,here,now);
        }
        public function observe(game:Object, token:uint, now:int):String {
            if (token != session) {
                session = token; area = null; trail = []; doors = {};
                if (active) return finish("Travel stopped · account changed");
            }
            var here:Object = location(game);
            if (here) {
                record(here);
                var adjacent:Array = [];
                for each (var exit:Object in SkillBag.field(game.world,"arrEvent")) {
                    if (exit is DisplayObject && SkillBag.field(exit,"tCell"))
                        adjacent.push({cell:String(exit.tCell),pad:SkillBag.field(exit,"tPad") || ""});
                }
                if (adjacent.length) doors["#"+here.cell] = adjacent;
            }
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
                if (monsterID) {
                    for each (var unit:Object in w.getMonstersByCell(here.cell)) {
                        if (String(SkillBag.field(unit.objData,"MonMapID")) != monsterID) continue;
                        if (!unit.pMC || !unit.dataLeaf || Number(unit.dataLeaf.intHP) <= 0) break;
                        w.setTarget(unit); w.approachTarget();
                        return finish("Approaching " + unit.objData.strMonName);
                    }
                    return finish("Monster unavailable · scan again");
                }
                if (here.pad == destination.pad)
                    return finish("At " + here.area + " · " + here.cell + ", " + here.pad);
                var marker:DisplayObject = SkillBag.field(SkillBag.field(w,"map"),destination.pad) as DisplayObject;
                if (walk(game,marker)) return finish("Walking to " + here.cell + ", " + destination.pad);
            }
            if (waitingAt == here.cell && nextCheck > now) return null;
            if (waitingAt == here.cell) return finish("Travel stopped · check the exit to " + destination.cell);
            waitingAt = here.cell; nextCheck = now + 10000;

            // A player in the destination cell may offer the game's regular Go To shortcut.
            // Consult the live list on each selection and let the game enforce its own Go To rules.
            if (here.cell != destination.cell && "getUsersByCell" in w && "goto" in w &&
                !SkillBag.field(SkillBag.field(w,"map"),"nogoto")) {
                for each (var other:Object in w.getUsersByCell(destination.cell)) {
                    var leaf:Object = SkillBag.field(other,"dataLeaf");
                    var who:* = SkillBag.field(leaf,"uoName") || SkillBag.field(leaf,"strUsername");
                    if (!who || other === w.myAvatar || (!monsterID && leaf.strPad != destination.pad)) continue;
                    w["goto"](String(who));
                    return "Going to " + destination.cell;
                }
            }

            var next:Object = {cell:destination.cell,pad:monsterID ? "" : destination.pad};
            if (walkExit(game,next)) return "Walking to " + next.cell;
            var route:Array = destination.route as Array;
            if (route) {
                for (var i:int=route.length-2; i>=0; --i) {
                    if (route[i].cell == here.cell && walkExit(game,route[i+1]))
                        return "Walking to " + route[i+1].cell;
                }
            }
            var first:Object = firstDoor(here.cell,next);
            if (first && walkExit(game,first)) return "Walking to " + first.cell;
            return finish("Use the map exits to reach " + destination.cell +
                (destination.pad ? ", " + destination.pad : ""));
        }
        // Only follow exits observed in this instance, verifying the next door on screen.
        private function firstDoor(start:String, dest:Object):Object {
            var seen:Object = {};
            seen["#"+start] = true;
            var queue:Array = [{cell:start,first:null}];
            for (var i:int=0; i<queue.length; ++i) {
                var current:Object = queue[i];
                for each (var edge:Object in doors["#"+current.cell]) {
                    var first:Object = current.first || edge;
                    if (edge.cell == dest.cell && (!dest.pad || edge.pad == dest.pad)) return first;
                    if (seen["#"+edge.cell]) continue;
                    seen["#"+edge.cell] = true;
                    queue.push({cell:edge.cell,first:first});
                }
            }
            return null;
        }
        private static function walkExit(game:Object, next:Object):Boolean {
            for each (var exit:Object in SkillBag.field(game.world,"arrEvent")) {
                if (!(exit is DisplayObject) || SkillBag.field(exit,"tCell") != next.cell) continue;
                if (next.pad && SkillBag.field(exit,"tPad") != next.pad) continue;
                if (walk(game,exit as DisplayObject)) return true;
            }
            return false;
        }
        private static function walk(game:Object, marker:DisplayObject):Boolean {
            var root:DisplayObject = game as DisplayObject;
            if (!root || !marker || !marker.parent || !("walkToPoint" in game.world)) return false;
            var bounds:Rectangle = marker.getBounds(root);
            return !bounds.isEmpty() && game.world.walkToPoint(bounds.x+bounds.width/2,bounds.y+bounds.height/2,false);
        }
    }
}
