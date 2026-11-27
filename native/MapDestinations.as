package {
    import flash.display.DisplayObject;
    import flash.display.InteractiveObject;
    import flash.events.MouseEvent;
    import flash.utils.getQualifiedClassName;
    public final class MapDestinations {
        private var destination:Object, origin:Object;
        private var monsterID:String;
        private var requestWorld:Object, requestConnection:Object, requestUser:String;
        private var deadline:int;
        private var adjustedPad:Boolean;
        private var padCandidate:DisplayObject;

        // Only cells actually seen in this account's current map instance are cached.
        private var seenWorld:Object, seenConnection:Object, seenUser:String, seenArea:String;
        private var seenPads:Object = {};

        public function get active():Boolean { return destination != null; }
        public function cancel():void {
            destination = origin = null; monsterID = null; adjustedPad = false; padCandidate = null;
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
            if (w !== seenWorld || sfc !== seenConnection || user != seenUser || (here && !same(here.area,seenArea))) {
                seenPads = {}; seenWorld = w; seenConnection = sfc; seenUser = user;
                seenArea = here ? here.area : null;
            }
            if (here && here.pad) seenPads["#"+here.cell] = here.pad;
        }
        private static function same(a:*, b:*):Boolean {
            return a != null && b != null && String(a).toLowerCase() == String(b).toLowerCase();
        }

        // Use the map's own enabled travel control for a first visit. Its normal click handler
        // retains character, quest and door checks that are specific to the current map.
        private static function useMapExit(game:Object, cell:String, pad:String):Boolean {
            for each (var exit:Object in SkillBag.field(game.world,"arrEvent")) {
                var control:InteractiveObject = exit as InteractiveObject;
                if (!control || !control.mouseEnabled || SkillBag.field(exit,"enabled") === false ||
                    !control.hasEventListener(MouseEvent.CLICK) || !same(SkillBag.field(exit,"tCell"),cell)) continue;
                var area:* = SkillBag.field(exit,"tMap");
                if (area && !same(area,game.world.strMapName) && !same(area,game.world.strAreaName)) continue;
                var entry:* = SkillBag.field(exit,"tPad");
                if (pad && entry && !same(entry,pad)) continue;
                var parent:DisplayObject = control;
                while (parent && parent != game && parent.visible && parent.alpha > 0) parent = parent.parent;
                if (parent !== game) continue;
                control.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true,false));
                return true;
            }
            return false;
        }

        // Return a message only when the choice needs the player's attention.
        public function begin(game:Object, dest:Object, mob:String, now:int):String {
            cancel();
            var here:Object = location(game);
            remember(game,here);
            if (!here || !dest || !dest.area || !dest.cell) return "Enter a map and try again.";
            var w:Object = game.world;
            var inInstance:Boolean = same(here.area,dest.area);
            if (mob) {
                if (!inInstance) return "Map changed. Refresh Mobs.";
                var current:Object;
                for each (var spawn:Object in mobs(w)) {
                    if (spawn.id == mob) { current = spawn; break; }
                }
                if (!current) return "This monster is no longer listed. Refresh Mobs.";
                dest = {area:here.area,cell:current.cell,pad:current.pad || seenPads["#"+current.cell] || ""};
            } else if (!dest.pad) return "This bookmark has no entry pad.";
            destination = dest; origin = here; monsterID = mob;
            requestWorld = w; requestConnection = game.sfc; requestUser = SkillBag.nameOf(game);
            deadline = now + (inInstance ? 4000 : 12000);

            if (!inInstance) {
                if (!(SkillBag.field(w,"gotoTown") is Function)) return finish("Map travel is unavailable.");
                w.gotoTown(dest.area,dest.cell,dest.pad);
                return null;
            }
            if (same(here.cell,dest.cell)) return observe(game,now);
            if (useMapExit(game,dest.cell,mob ? "" : dest.pad)) return null;
            if (!seenPads["#"+dest.cell] || !(SkillBag.field(w,"moveToCell") is Function))
                return finish("No direct jump is available to this cell from here.");
            w.moveToCell(dest.cell,dest.pad || seenPads["#"+dest.cell],false);
            return null;
        }

        public function observe(game:Object, now:int):String {
            var here:Object = location(game);
            remember(game,here);
            if (!active) return null;
            if (SkillBag.field(game,"sfc") !== requestConnection || SkillBag.nameOf(game) != requestUser ||
                (same(origin.area,destination.area) && SkillBag.field(game,"world") !== requestWorld))
                return finish();
            if (now >= deadline) return finish("The game did not confirm the destination.");
            if (!here) return null;
            if (!same(here.area,destination.area)) {
                return same(here.area,origin.area) ? null : finish("The game sent you to another map.");
            }
            if (!same(here.cell,destination.cell)) {
                return same(here.area,origin.area) && same(here.cell,origin.cell) ? null :
                    finish("The game sent you to another cell.");
            }
            var w:Object = game.world;
            if (monsterID) {
                for each (var unit:Object in w.getMonstersByCell(here.cell)) {
                    if (String(SkillBag.field(SkillBag.field(unit,"objData"),"MonMapID")) != monsterID ||
                        !SkillBag.field(unit,"pMC") || !SkillBag.field(unit,"dataLeaf")) continue;
                    if (Number(unit.dataLeaf.intHP) <= 0) return finish("This monster is down.");
                    w.setTarget(unit);
                    return finish();
                }
                return null;
            }
            if (same(here.pad,destination.pad)) return finish();
            if (adjustedPad) return null;
            var pad:DisplayObject = savedPadOnFrame(SkillBag.field(w,"map"),here.cell,destination.pad);
            // Some maps keep playing ambient animation. Require the same real pad on two
            // observations of the destination cell instead of waiting for all animation to stop.
            if (pad && pad === padCandidate && SkillBag.field(w,"moveToCell") is Function) {
                adjustedPad = true;
                w.moveToCell(here.cell,pad.name,false);
            }
            padCandidate = pad;
            return null;
        }
        private static function savedPadOnFrame(map:Object, cell:String, wanted:String):DisplayObject {
            if (!map || !same(SkillBag.field(map,"currentLabel"),cell) ||
                !(SkillBag.field(map,"getChildAt") is Function)) return null;
            for (var i:int=0; i<int(map.numChildren); i++) {
                var child:DisplayObject = map.getChildAt(i) as DisplayObject;
                if (child && same(child.name,wanted) && /(^|::)Pad_\d+$/.test(getQualifiedClassName(child)))
                    return child;
            }
            return null;
        }
        private function finish(problem:String = null):String { cancel(); return problem; }
    }
}
