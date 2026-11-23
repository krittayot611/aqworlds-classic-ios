package {
    import flash.utils.getTimer;

    public final class SkillRules {
        public static function valid(steps:Array):Boolean {
            if (!steps || !steps.length || steps.length > 32) return false;
            for each (var step:Object in steps) {
                if (!step || !(step.slot is Number) || step.slot != int(step.slot) ||
                    step.slot < 2 || step.slot > 5 || !(step.rules is Array) || step.rules.length > 8 ||
                    !(step.wait is Boolean) || (step.match !== "all" && step.match !== "any")) return false;
                for each (var rule:Object in step.rules) {
                    if (!rule || (rule.who !== "self" && rule.who !== "target")) return false;
                    if (rule.kind === "aura") {
                        if (!(rule.name is String) || !clean(rule.name) || rule.name.length > 100 ||
                            (rule.op !== "present" && rule.op !== "missing" && rule.op !== "stacks")) return false;
                        if (rule.op === "stacks" && !integerBetween(rule.value,1,999)) return false;
                    } else if (rule.kind === "hp" || rule.kind === "mp") {
                        if ((rule.op !== "below" && rule.op !== "above") || !integerBetween(rule.value,0,100)) return false;
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
            if (!step.rules.length) return true;
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
            var self:Boolean = rule.who === "self";
            var unit:Object = self ? SkillBag.field(world,"myAvatar") : target;
            var leaf:Object = SkillBag.field(unit,"dataLeaf");
            if (!leaf) return false;
            if (rule.kind !== "aura") {
                var stat:String = rule.kind === "hp" ? "intHP" : "intMP";
                var current:* = SkillBag.field(leaf,stat), maximum:* = SkillBag.field(leaf,stat+"Max");
                if (current == null || maximum == null || !(Number(maximum)>0) || !(Number(current)>=0)) return false;
                var percent:Number = 100 * Number(current)/Number(maximum);
                return rule.op === "below" ? percent < rule.value : percent > rule.value;
            }
            var tree:Object = SkillBag.field(world,self ? "uoTree" : "monTree");
            var key:* = self ? SkillBag.nameOf(game) : SkillBag.field(leaf,"MonMapID");
            var entry:Object = key != null ? SkillBag.field(tree,String(key)) : null;
            var primary:Object = self && entry ? entry : leaf;
            var fallback:Object = primary === leaf ? entry : leaf;
            var stacks:int = auraStacks(primary,fallback,clean(rule.name));
            if (stacks < 0) return false;
            if (rule.op === "missing") return stacks == 0;
            return rule.op === "stacks" ? stacks >= rule.value : stacks > 0;
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
