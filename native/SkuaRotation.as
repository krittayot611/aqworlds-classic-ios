package {
    import flash.events.TimerEvent;
    import flash.utils.Timer;
    import flash.utils.getTimer;

    public final class SkuaRotation {
        private var getGame:Function, report:Function;
        private var bag:SkillBag;
        private var timer:Timer = new Timer(100);
        private var clock:Function;
        private var world:Object, avatar:Object;
        private var map:String, room:String, classId:String;
        private var token:uint;
        private var order:Array;
        private var cursor:int;
        private var autoTarget:Boolean, resetOnTarget:Boolean;
        private var targetKey:Object;
        private var timeoutMs:int;
        private var cooldownSince:Number = NaN, readySince:Number = NaN;
        private var oldBarSkill:Object, oldBarId:String, equipDeadline:int;
        private var lastMessage:String;
        private var approached:Object;

        public function SkuaRotation(game:Function, update:Function, inventory:SkillBag, timestamp:Function = null) {
            getGame = game; report = update; bag = inventory; clock = timestamp || getTimer;
            timer.addEventListener(TimerEvent.TIMER, tick);
        }
        private function firstSkill():Object { return world.actions.active[1]; }
        private function signature(skill:Object):String {
            if (!skill) return "";
            return [SkillBag.field(skill,"id"),SkillBag.field(skill,"nam"),SkillBag.field(skill,"ref")].join("|");
        }
        public function start(steps:Array, auto:Boolean, id:String, session:uint,
                              resetOnTargetChange:Boolean = false, waitLimit:int = 0):void {
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
                resetOnTarget = resetOnTargetChange; timeoutMs = Math.max(0,waitLimit);
                targetKey = null; cooldownSince = readySince = NaN;
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
            timer.reset(); targetKey = null; approached = null; cooldownSince = readySince = NaN; equipDeadline = 0; oldBarSkill = null;
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
        private function observeTarget(unit:Object):void {
            var key:Object = unit ? SkillBag.field(unit.objData,"MonMapID") : null;
            if (unit && key == null) key = SkillBag.field(unit.dataLeaf,"MonMapID");
            if (unit) key = key == null ? unit : String(key);
            if (key === targetKey) return;
            if (targetKey != null && resetOnTarget) cursor = 0;
            targetKey = key;
            cooldownSince = readySince = NaN;
        }
        private function advance():void {
            cursor = (cursor + 1) % order.length;
            cooldownSince = readySince = NaN;
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
                    observeTarget(null);
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
                observeTarget(avatar.target);
                if (approached !== avatar.target) {
                    world.approachTarget();
                    approached = avatar.target;
                }
                var now:Number = new Date().time;
                if (now - Number(world.GCDTS) < Number(world.GCD)) { status("Global cooldown",true); return; }
                var active:Object = world.actions.active;
                var instant:Number = clock();
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
                        if (cooling && step.wait) {
                            readySince = NaN;
                            if (isNaN(cooldownSince)) cooldownSince = instant;
                            if (!timeoutMs || instant - cooldownSince < timeoutMs) {
                                status("Waiting for cooldown",true); return;
                            }
                        } else if (!cooling && skill.isOK) {
                            cooldownSince = NaN;
                            var delay:int = int(step.delayMs);
                            if (delay > 0) {
                                if (isNaN(readySince)) readySince = instant;
                                if (instant - readySince < delay) { status("Waiting before skill",true); return; }
                            }
                            world.testAction(skill);
                            advance();
                            status("Running",true);
                            return;
                        }
                    }
                    advance();
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
