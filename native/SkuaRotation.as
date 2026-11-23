package {
    import flash.events.TimerEvent;
    import flash.utils.Timer;

    /** A foreground rotation of the equipped class's visible hotbar skills. */
    public final class SkuaRotation {
        private var getGame:Function;
        private var report:Function;
        private var timer:Timer = new Timer(450);
        private var world:Object;
        private var avatar:Object;
        private var map:String;
        private var room:String;
        private var order:Array;
        private var cursor:int;
        private var autoTarget:Boolean;
        private var lastMessage:String;

        public function SkuaRotation(game:Function, update:Function) {
            getGame = game;
            report = update;
            timer.addEventListener(TimerEvent.TIMER, tick);
        }

        public function start(slots:Array, auto:Boolean):void {
            if (timer.running) { status("Running", true); return; }
            try {
                if (!slots || slots.length < 1 || slots.length > 8) { stop("Choose 1–8 skills"); return; }
                for each (var key:* in slots) {
                    if (!(key is Number) || key != int(key) || key < 2 || key > 5) {
                        stop("Choose skills 2–5"); return;
                    }
                }
                var game:Object = getGame();
                var current:Object = game && "world" in game ? game.world : null;
                if (!current || !current.myAvatar || !current.strMapName || !current.strFrame ||
                    !living(current.myAvatar)) { stop("Enter a map to start"); return; }
                if (!current.actions || !current.actions.active || !("testAction" in current)) {
                    stop("Waiting for the skill bar"); return;
                }
                world = current; avatar = world.myAvatar;
                map = world.strMapName; room = world.strFrame;
                order = slots.concat(); autoTarget = auto; cursor = 0;
                timer.start();
                tick();
            } catch (error:Error) { stop("Game controls unavailable"); }
        }

        public function stop(message:String = "Stopped"):void {
            timer.reset();
            world = null; avatar = null; order = null;
            lastMessage = null;
            status(message, false);
        }
        public function get running():Boolean { return timer.running; }

        private function status(text:String, active:Boolean):void {
            if (lastMessage === text) return;
            lastMessage = text;
            report(text,active);
        }
        private function living(unit:Object):Boolean {
            return unit && unit.dataLeaf && Number(unit.dataLeaf.intHP) > 0;
        }
        private function monster(unit:Object):Boolean {
            return living(unit) && unit.objData && unit.objData.strMonName && unit.pMC;
        }

        public function tick(event:TimerEvent = null):void {
            if (!timer.running) return;
            try {
                var game:Object = getGame();
                if (!game || game.world !== world || world.myAvatar !== avatar ||
                    world.strMapName !== map || world.strFrame !== room) {
                    stop("Stopped · room changed"); return;
                }
                if (!living(avatar)) { stop("Stopped · player down"); return; }
                if (!monster(avatar.target)) {
                    if (autoTarget) {
                        for each (var next:Object in world.getMonstersByCell(room)) {
                            if (!monster(next)) continue;
                            world.setTarget(next);
                            world.approachTarget();
                            status("Acquiring target",true);
                            return;
                        }
                    }
                    status(autoTarget ? "Waiting for a monster" : "Tap a monster in the game",true);
                    return;
                }
                var now:Number = new Date().time;
                if (now - Number(world.GCDTS) < Number(world.GCD)) { status("Global cooldown",true); return; }
                var active:Object = world.actions.active;
                for (var i:int = 0; i < order.length; i++) {
                    var slot:int = int(order[cursor]);
                    var skill:Object = active[slot-1];
                    if (skill && skill.isOK && !skill.skillLock && !skill.lock) {
                        var stats:Object = avatar.dataLeaf.sta;
                        var haste:Number = stats ? Number(stats["$tha"]) : 0;
                        if (isNaN(haste)) haste = 0;
                        var cooldown:Number = Number(skill.OldCD != null ? skill.OldCD : skill.cd);
                        if (now - Number(skill.ts) < cooldown * (1 - Math.min(.5,Math.max(-1,haste)))) {
                            status("Waiting for skill " + slot,true); return;
                        }
                        // testAction is the game's hotbar action path, including its own checks.
                        world.testAction(skill);
                        cursor = (cursor + 1) % order.length;
                        status("Running · skill " + slot,true);
                        return;
                    }
                    cursor = (cursor + 1) % order.length;
                }
                status("Waiting for available skills",true);
            } catch (error:Error) { stop("Stopped · game controls unavailable"); }
        }
        public function dispose():void {
            timer.reset();
            timer.removeEventListener(TimerEvent.TIMER, tick);
            world = null; avatar = null; order = null;
            getGame = null; report = null;
        }
    }
}
