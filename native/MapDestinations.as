package {
    import flash.display.DisplayObject;
    import flash.display.InteractiveObject;
    import flash.events.MouseEvent;
    import flash.geom.Rectangle;

    /** Navigation uses the same Join, Go To and walking controls as the game. */
    public final class MapDestinations {
        private var session:uint;
        private var area:String;
        private var trail:Array = [];
        private var doors:Object = {};
        private var destination:Object, tried:Object;
        private var lastCell:String, portalAt:String;
        private var monsterID:String;
        private var fromArea:String, waitingAt:String, shortcutAt:String;
        private var ownerWorld:Object, connection:Object, user:String;
        private var deadline:int, nextCheck:int;

        public function get active():Boolean { return destination != null; }
        public function cancel():void {
            destination = null; monsterID = null; waitingAt = shortcutAt = null;
            ownerWorld = connection = null; user = lastCell = portalAt = null; tried = {};
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
                // A normal instance join can replace the avatar while preserving the connection.
                if (active && (SkillBag.field(game,"world") !== ownerWorld || SkillBag.field(game,"sfc") !== connection ||
                    SkillBag.nameOf(game) !== user)) return finish("Travel stopped · account changed");
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
            if (lastCell != here.cell) {
                lastCell = here.cell; waitingAt = shortcutAt = portalAt = null;
            }
            if (here.cell == destination.cell) {
                if (monsterID) {
                    var found:Boolean = false;
                    for each (var unit:Object in w.getMonstersByCell(here.cell)) {
                        if (String(SkillBag.field(unit.objData,"MonMapID")) != monsterID) continue;
                        found = true;
                        if (!unit.pMC || !unit.dataLeaf || Number(unit.dataLeaf.intHP) <= 0) break;
                        w.setTarget(unit); w.approachTarget();
                        return finish("Approaching " + unit.objData.strMonName);
                    }
                    if (!found && waitingAt != here.cell) {
                        waitingAt = here.cell; nextCheck = now + 4500;
                        return "Waiting for the monster to load";
                    }
                    if (!found && now < nextCheck) return null;
                    return finish("Monster unavailable · scan again");
                }
                if (here.pad == destination.pad)
                    return finish("At " + here.area + " · " + here.cell + ", " + here.pad);
                var marker:DisplayObject = SkillBag.field(SkillBag.field(w,"map"),destination.pad) as DisplayObject;
                if (walk(game,marker)) return finish("Walking to " + here.cell + ", " + destination.pad);
            }
            if (waitingAt == here.cell && nextCheck > now) return null;
            if (waitingAt == here.cell && shortcutAt != here.cell && portalAt != here.cell)
                return finish("Travel stopped · check the exit to " + destination.cell);
            waitingAt = here.cell; nextCheck = now + 10000;
            if (here.cell != destination.cell && portalAt != here.cell && tapPortal(game,destination,monsterID != null)) {
                portalAt = here.cell; nextCheck = now + 3500;
                return "Warping to " + destination.cell;
            }

            // A player in the destination cell may offer the game's regular Go To shortcut.
            // Consult the live list on each selection and let the game enforce its own Go To rules.
            if (here.cell != destination.cell && shortcutAt != here.cell && "getUsersByCell" in w && "goto" in w &&
                !SkillBag.field(SkillBag.field(w,"map"),"nogoto")) {
                for each (var other:Object in w.getUsersByCell(destination.cell)) {
                    var leaf:Object = SkillBag.field(other,"dataLeaf");
                    var who:* = SkillBag.field(leaf,"uoName") || SkillBag.field(leaf,"strUsername") ||
                        SkillBag.field(SkillBag.field(other,"objData"),"strUsername");
                    if (!who || other === w.myAvatar || (!monsterID && SkillBag.field(leaf,"strPad") != destination.pad)) continue;
                    shortcutAt = here.cell; nextCheck = now + 3500;
                    w["goto"](String(who));
                    return "Going to " + destination.cell;
                }
            }

            shortcutAt = portalAt = null;
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
            if (monsterID) {
                var onward:Object = nextUntriedExit(game,here.cell);
                if (onward) return "Following map exits to " + destination.cell + " · " + onward.cell;
            }
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
        // Explore only the exits the current map exposes. Track directed edges so a dead end can be left.
        private function nextUntriedExit(game:Object, cell:String):Object {
            var exits:Object = SkillBag.field(game.world,"arrEvent");
            for each (var entry:Object in exits) {
                var to:* = SkillBag.field(entry,"tCell");
                if (!to || to == cell || !(entry is DisplayObject)) continue;
                var pad:String = SkillBag.field(entry,"tPad") || "";
                var key:String = JSON.stringify([cell,to,pad]);
                if (tried[key]) continue;
                tried[key] = true;
                if (walk(game,entry as DisplayObject)) return {cell:to,pad:pad};
            }
            // Known return paths can lead to an unvisited branch several screens back.
            for (var node:String in doors) {
                if (node == "#"+cell) continue;
                for each (var edge:Object in doors[node]) {
                    if (tried[JSON.stringify([node.substr(1),edge.cell,edge.pad])]) continue;
                    var first:Object = firstDoor(cell,{cell:node.substr(1)});
                    if (first && walkExit(game,first)) return first;
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
