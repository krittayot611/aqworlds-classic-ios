package {
    import flash.events.TimerEvent;
    import flash.utils.Timer;
    import flash.utils.getTimer;

    public final class SkuaRotation {
        private var getGame:Function, report:Function;
        private var bag:SkillBag;
        private var timer:Timer = new Timer(450);
        private var world:Object, avatar:Object;
        private var map:String, room:String, classId:String;
        private var token:uint;
        private var order:Array;
        private var cursor:int;
        private var autoTarget:Boolean;
        private var oldBarSkill:Object, oldBarId:String, equipDeadline:int;
        private var lastMessage:String;
        private var approached:Object;

        public function SkuaRotation(game:Function, update:Function, inventory:SkillBag) {
            getGame = game; report = update; bag = inventory;
            timer.addEventListener(TimerEvent.TIMER, tick);
        }
        private function firstSkill():Object { return world.actions.active[1]; }
        private function signature(skill:Object):String {
            if (!skill) return "";
            return [SkillBag.field(skill,"id"),SkillBag.field(skill,"nam"),SkillBag.field(skill,"ref")].join("|");
        }
        public function start(steps:Array, auto:Boolean, id:String, session:uint):void {
            if (timer.running) return;
            try {
                if (!SkillRules.valid(steps)) { stop("Choose a valid skill set"); return; }
                var game:Object = getGame();
                var current:Object = SkillBag.field(game,"world");
                if (!current || !current.myAvatar || !current.strMapName || !current.strFrame ||
                    !living(current.myAvatar)) { stop("Enter a map to start"); return; }
                if (session != bag.session(game) || !SkillBag.accountReady(game,current.myAvatar) || !SkillBag.owned(current.myAvatar,id)) {
                    stop("Choose a class from this bag"); return;
                }
                if (!current.actions || !current.actions.active || !("testAction" in current)) {
                    stop("Waiting for the skill bar"); return;
                }
                world = current; avatar = world.myAvatar; classId = id; token = session;
                map = world.strMapName; room = world.strFrame;
                order = steps; autoTarget = auto; cursor = 0;
                if (SkillBag.equippedId(avatar) !== id) {
                    if (!("sendEquipItemRequest" in world)) { stop("Equip this class in the game"); return; }
                    oldBarSkill = firstSkill(); oldBarId = signature(oldBarSkill);
                    equipDeadline = getTimer() + 8500;
                    // Use the same request as the inventory Equip button. The game may decline it.
                    world.sendEquipItemRequest(SkillBag.owned(avatar,id));
                }
                timer.start();
                tick();
            } catch (error:Error) { stop("Game controls unavailable"); }
        }
        public function stop(message:String = "Stopped"):void {
            timer.reset(); approached = null; equipDeadline = 0; oldBarSkill = null;
            world = null; avatar = null; order = null; classId = null; lastMessage = null;
            status(message, false);
        }
        public function get running():Boolean { return timer.running; }
        private function status(message:String, active:Boolean):void {
            if (lastMessage === message) return;
            lastMessage = message; report(message,active);
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
                if (bag.session(game) != token || !SkillBag.accountReady(game,avatar) || !game || game.world !== world || world.myAvatar !== avatar ||
                    world.strMapName !== map || world.strFrame !== room) {
                    stop("Stopped · room or account changed"); return;
                }
                if (!living(avatar)) { stop("Stopped · player down"); return; }
                var worn:String = SkillBag.equippedId(avatar);
                if (equipDeadline) {
                    var skillNow:Object = firstSkill();
                    if (worn === classId && skillNow && (skillNow !== oldBarSkill || signature(skillNow) !== oldBarId)) {
                        equipDeadline = 0; oldBarSkill = null;
                    } else {
                        if (!SkillBag.owned(avatar,classId) || getTimer() >= equipDeadline)
                            stop("Equip the class in-game, then start");
                        else status("Waiting for the selected class",true);
                        return;
                    }
                }
                if (worn !== classId) { stop("Stopped · equipped class changed"); return; }
                if (!monster(avatar.target)) {
                    approached = null;
                    if (autoTarget) {
                        for each (var next:Object in world.getMonstersByCell(room)) {
                            if (!monster(next)) continue;
                            world.setTarget(next);
                            world.approachTarget(); approached = next;
                            status("Acquiring target",true);
                            return;
                        }
                    }
                    status(autoTarget ? "Waiting for a monster" : "Tap a monster in the game",true);
                    return;
                }
                if (approached !== avatar.target) {
                    world.approachTarget();
                    approached = avatar.target;
                }
                var now:Number = new Date().time;
                if (now - Number(world.GCDTS) < Number(world.GCD)) { status("Global cooldown",true); return; }
                var active:Object = world.actions.active;
                for (var i:int = 0; i < order.length; i++) {
                    var step:Object = order[cursor];
                    var slot:int = int(step.slot);
                    var skill:Object = active[slot-1];
                    if (skill && !skill.skillLock && !skill.lock && SkillRules.allows(step,game,avatar.target)) {
                        var stats:Object = avatar.dataLeaf.sta;
                        var haste:Number = stats ? Number(stats["$tha"]) : 0;
                        if (isNaN(haste)) haste = 0;
                        var cooldown:Number = Number(skill.OldCD != null ? skill.OldCD : skill.cd);
                        var cooling:Boolean = now - Number(skill.ts) < cooldown * (1 - Math.min(.5,Math.max(-1,haste)));
                        if (cooling && step.wait) { status("Waiting for cooldown",true); return; }
                        if (!cooling && skill.isOK) {
                            world.testAction(skill);
                            cursor = (cursor + 1) % order.length;
                            status("Running",true);
                            return;
                        }
                    }
                    cursor = (cursor + 1) % order.length;
                }
                status("Waiting for a ready skill or condition",true);
            } catch (error:Error) { stop("Stopped · game controls unavailable"); }
        }
        public function dispose():void {
            timer.reset();
            timer.removeEventListener(TimerEvent.TIMER, tick);
            world = null; avatar = null; order = null; oldBarSkill = null;
            getGame = null; report = null; bag = null;
        }
    }
}
