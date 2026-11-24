package {
    import flash.utils.getTimer;

    public final class SkillRules {
        public static function valid(steps:Array):Boolean {
            if (!steps || !steps.length || steps.length > 32) return false;
            for each (var step:Object in steps) {
                if (!step || !(step.slot is Number) || step.slot != int(step.slot) ||
                    step.slot < 2 || step.slot > 5 || !(step.rules is Array) || step.rules.length > 8 ||
                    !(step.wait is Boolean) || ("rulesEnabled" in step && !(step.rulesEnabled is Boolean)) ||
                    (step.match !== "all" && step.match !== "any")) return false;
                for each (var rule:Object in step.rules) {
                    if (!rule) return false;
                    var party:Boolean = rule.kind === "partyhp";
                    if (party ? rule.who !== "party" : rule.who !== "self" && rule.who !== "target") return false;
                    var inclusive:Boolean = rule.op === "lte" || rule.op === "gte";
                    if (rule.kind === "aura") {
                        if (!(rule.name is String) || !clean(rule.name) || rule.name.length > 100 ||
                            (!inclusive && rule.op !== "present" && rule.op !== "missing" && rule.op !== "stacks")) return false;
                        if (inclusive && !integerBetween(rule.value,0,999)) return false;
                        if (rule.op === "stacks" && !integerBetween(rule.value,1,999)) return false;
                    } else if (party || rule.kind === "hp" || rule.kind === "mp") {
                        if (!inclusive && rule.op !== "below" && rule.op !== "above") return false;
                        if (rule.unit !== "raw" && rule.unit !== "percent" && (inclusive || "unit" in rule)) return false;
                        if (!integerBetween(rule.value,0,rule.unit === "raw" ? int.MAX_VALUE : 100)) return false;
                    } else return false;
                }
            }
            return true;
        }
        private static function integerBetween(v:*, low:int, high:int):Boolean {
            return v is Number && v == int(v) && v >= low && v <= high;
        }
        private static function clean(s:String):String { return s.replace(/^\s+|\s+$/g,"").toLowerCase(); }

        public static function allows(step:Object, game:Object, target:Object):Boolean {
            if (step.rulesEnabled === false || !step.rules.length) return true;
            var any:Boolean = step.match === "any";
            for each (var rule:Object in step.rules) {
                var yes:Boolean = satisfied(rule,game,target);
                if (any && yes) return true;
                if (!any && !yes) return false;
            }
            return !any;
        }
        private static function satisfied(rule:Object, game:Object, target:Object):Boolean {
            var world:Object = SkillBag.field(game,"world");
            if (rule.kind === "partyhp") {
                var frame:* = SkillBag.field(world,"strFrame");
                var members:Array = SkillBag.field(world,"partyMembers") as Array;
                var users:Object = SkillBag.field(world,"uoTree");
                var me:String = SkillBag.nameOf(game);
                if (!frame || !members || !users || !me) return false;
                for each (var member:* in members) {
                    if (!(member is String) || clean(member) == me) continue;
                    var ally:Object = SkillBag.field(users,clean(member));
                    if (SkillBag.field(ally,"strFrame") === frame && Number(SkillBag.field(ally,"intHP")) > 0 &&
                        resourceMatches(rule,ally,"intHP")) return true;
                }
                return false;
            }
            var self:Boolean = rule.who === "self";
            var unit:Object = self ? SkillBag.field(world,"myAvatar") : target;
            var leaf:Object = SkillBag.field(unit,"dataLeaf");
            if (!leaf) return false;
            if (rule.kind !== "aura") return resourceMatches(rule,leaf,rule.kind === "hp" ? "intHP" : "intMP");
            var tree:Object = SkillBag.field(world,self ? "uoTree" : "monTree");
            var key:* = self ? SkillBag.nameOf(game) : SkillBag.field(leaf,"MonMapID");
            var entry:Object = key != null ? SkillBag.field(tree,String(key)) : null;
            var primary:Object = self && entry ? entry : leaf;
            var fallback:Object = primary === leaf ? entry : leaf;
            var stacks:int = auraStacks(primary,fallback,clean(rule.name));
            if (stacks < 0) return false;
            if (rule.op === "missing") return stacks == 0;
            if (rule.op === "present") return stacks > 0;
            return rule.op === "lte" ? stacks <= rule.value : stacks >= rule.value;
        }
        private static function resourceMatches(rule:Object, leaf:Object, stat:String):Boolean {
            var current:* = SkillBag.field(leaf,stat);
            if (current == null || current === "" || !isFinite(Number(current)) || Number(current) < 0) return false;
            var measured:Number = Number(current);
            var threshold:Number = rule.value;
            if (rule.unit !== "raw") {
                var maximum:* = SkillBag.field(leaf,stat+"Max");
                if (maximum == null || !isFinite(Number(maximum)) || Number(maximum) <= 0) return false;
                // Compare without rounding away a one-point difference at the boundary.
                measured *= 100;
                threshold *= Number(maximum);
            }
            switch (rule.op) {
                case "lte": return measured <= threshold;
                case "gte": return measured >= threshold;
                case "below": return measured < threshold;
                case "above": return measured > threshold;
            }
            return false;
        }
        private static function auraStacks(primary:Object, fallback:Object, name:String):int {
            var hud:Object = SkillBag.field(primary,"hudAuras");
            if (!hud) hud = SkillBag.field(fallback,"hudAuras");
            var aura:Object, count:int = 0;
            if (hud) {
                for (var key:String in hud) {
                    if (clean(key) !== name) continue;
                    aura = hud[key];
                    if (aura && (aura.persist == true || !(Number(aura.end)>0) || Number(aura.end)>getTimer()))
                        count = Math.max(count,1,int(aura.n));
                }
                return count;
            }
            var raw:Array = SkillBag.field(primary,"auras") as Array;
            if (!raw) raw = SkillBag.field(fallback,"auras") as Array;
            if (!raw) return -1; // No observed aura collection yet.
            for each (aura in raw) {
                if (aura && aura.nam && aura.e != 1 && clean(String(aura.nam)) == name)
                    count = Math.max(count,1,int(aura.val));
            }
            return count;
        }
    }
}
