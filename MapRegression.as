package {
    import flash.display.Bitmap;
    import flash.display.MovieClip;
    import flash.display.StageScaleMode;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.system.ApplicationDomain;
    import flash.utils.Timer;

    // Run only by the release smoke check; never creates a game session.
    public final class MapRegression {
        public static function checkRotation(note:Function):void {
            var target:Object = {dataLeaf:{intHP:100}, objData:{strMonName:"Fixture"},pMC:{}};
            var player:Object = {dataLeaf:{intHP:100,sta:{}},target:null};
            var used:Array = [];
            var bar:Array = [null,{id:2,isOK:true,cd:0,ts:0},{id:3,isOK:true,cd:0,ts:0},
                             {id:4,isOK:true,cd:0,ts:0},{id:5,isOK:true,cd:0,ts:0}];
            var world:Object = {myAvatar:player,strMapName:"fixture",strFrame:"Enter",actions:{active:bar},
                GCD:0,GCDTS:0,testAction:function(skill:Object):void { used.push(skill.id); }};
            var game:Object = {world:world,sfc:{myUserName:"One"}};
            var healer:Object = {ItemID:"11",CharItemID:"101",sType:"Class",sName:"Healer",bEquip:"1"};
            var mage:Object = {ItemID:22,CharItemID:"202",sES:"ar",sName:"Mage",bEquip:0};
            player.items = [healer,mage,{ItemID:11,sName:"Healer",sES:"ar"},
                            {ItemID:33,sType:"Armor",sES:"co",sName:"Robe",bEquip:1}];
            player.bank = [{ItemID:44,sType:"Class",sName:"Banked"}];
            var bag:SkillBag = new SkillBag(); var first:Object = bag.snapshot(game);
            var sid:uint = first.session;
            var state:String;
            var walking:int;
            var candidates:Array = [target];
            world.getMonstersByCell = function(frame:String):Array { return frame == "Enter" ? candidates : []; };
            world.setTarget = function(unit:Object):void { player.target = unit; };
            world.approachTarget = function():void { walking++; };
            var bot:SkuaRotation = new SkuaRotation(function():Object { return game; },
                function(text:String,on:Boolean):void { state = text; },bag);
            function step(slot:int, rules:Array=null, wait:Boolean=true, match:String="all"):Object {
                return {slot:slot,rules:rules || [],wait:wait,match:match};
            }
            function play(slots:Array, auto:Boolean):void {
                var steps:Array=[];
                for each (var n:int in slots) steps.push(step(n));
                bot.start(steps,auto,"11",sid);
            }
            function need(ok:Boolean, description:String):void {
                if (!ok) throw new Error("Rotation check: " + description + " (" + state + ")");
            }
            try {
                play([],false); need(!bot.running,"empty order");
                play([6],false); need(!bot.running,"invalid slot");
                play([3,2,3],false);
                need(bot.running && !used.length && !walking,"manual target");
                player.target = {dataLeaf:{intHP:100},objData:{strUsername:"Fixture"},pMC:{}};
                bot.tick(); need(!used.length,"ignore player target");
                player.target = target;
                world.GCD = 10000; world.GCDTS = new Date().time;
                bot.tick(); need(!used.length && walking == 1,"approach manually selected target while respecting cooldown");
                world.GCD = 0;
                bar[2].ts = new Date().time; bar[2].cd = 10000;
                bot.tick(); need(!used.length,"skill cooldown");
                bar[2].ts = 0;
                bot.tick(); bot.tick(); bot.tick();
                need(used.join(",") == "3,2,3","ordered repeat");
                world.strFrame = "Exit"; bot.tick();
                need(!bot.running && used.length == 3,"room change");
                world.strFrame = "Enter"; player.target = null; candidates = [];
                play([2,4],true); need(bot.running && walking == 1,"wait for respawn");
                candidates = [target]; bot.tick(); need(player.target === target && walking == 2,"auto target");
                bar[1].lock = true; bot.tick(); need(used[3] === 4,"skip locked slot");
                player.dataLeaf.intHP = 0; bot.tick(); need(!bot.running,"stop on death");
                player.dataLeaf.intHP = 100; play([5],false);
                game.world = null; bot.tick(); need(!bot.running,"logout");
                game.world = world; sid=bag.session(game); play([5],false); need(bot.running,"restart after login"); bot.stop();
                var count:int = used.length; bot.tick(); need(!bot.running && used.length == count,"manual stop");
                need(first.classes.length == 2 && first.classes[0].id == "11" && first.classes[1].id == "22" &&
                     first.equipped == "11" && !SkillBag.owned(player,"44"),"bag excludes bank, cosmetics and duplicates");
                var aura:Object = {kind:"aura",who:"self",name:"  Focus ",op:"stacks",value:3};
                var missing:Object = {kind:"aura",who:"target",name:"Seal",op:"missing"};
                var hp:Object = {kind:"hp",who:"self",op:"below",value:60};
                var mp:Object = {kind:"mp",who:"target",op:"above",value:30};
                var stacked:Object = step(3,[aura,missing,hp,mp]);
                player.target=target; player.dataLeaf.intHP=50; player.dataLeaf.intHPMax=100;
                target.dataLeaf.intMP=4; target.dataLeaf.intMPMax=10;
                world.uoTree={one:{hudAuras:{FOCUS:{n:3,end:0}}}};
                need(!SkillRules.allows(stacked,game,target),"missing aura data cannot match absence");
                target.dataLeaf.hudAuras={};
                need(SkillRules.valid([stacked]) && SkillRules.allows(stacked,game,target),"self stacks, target absence and resources");
                target.dataLeaf.hudAuras.Seal={n:1,persist:true};
                need(!SkillRules.allows(stacked,game,target) && SkillRules.allows(step(2,[missing,hp],true,"any"),game,target),"all or any");
                delete target.dataLeaf.hudAuras.Seal;
                world.uoTree.one.hudAuras.FOCUS.end=1;
                need(!SkillRules.allows(step(3,[aura]),game,target),"expired HUD aura");
                delete world.uoTree.one.hudAuras;
                world.uoTree.one.auras=[{nam:"Focus",val:4,e:0}];
                need(SkillRules.allows(stacked,game,target),"raw aura fallback");
                world.uoTree.one.auras[0].e=1;
                need(!SkillRules.allows(stacked,game,target),"expired raw aura");
                need(!SkillRules.valid([step(3,[{kind:"aura",who:"target",name:"",op:"missing"}])]),"blank aura rejected");
                need(!SkillRules.valid([step(3,[{kind:"hp",who:"self",op:"below",value:110}])]),"invalid percent rejected");
                bar[1].lock=false; bar[2].ts=new Date().time; bar[2].cd=50000;
                count=used.length;
                var readyStep:Object=step(4,[aura],false);
                readyStep.rulesEnabled=false;
                bar[2].isOK=false;
                bot.start([step(3,[],true),readyStep],false,"11",sid);
                need(used.length==count && state=="Waiting for skill 2","on holds the current cooling slot");
                bar[2].isOK=true; bar[2].ts=0;
                bot.tick(); need(used.length==count+1 && used[count]===3,"on resumes on the same slot");
                bot.stop(); bar[2].ts=new Date().time;
                bar[3].ts=new Date().time; bar[3].cd=50000;
                bot.start([step(3,[],false),readyStep],false,"11",sid);
                need(used.length==count+1 && bot.running,"off waits only when nothing is ready");
                bar[3].ts=0; bot.tick();
                need(used.length==count+2 && used[count+1]===4,"off uses the next ready slot with disabled conditions");
                bar[2].ts=0; bot.tick();
                need(used.length==count+3 && used[count+2]===3,"off revisits the skipped slot");
                bot.stop(); bar[2].ts=new Date().time;
                count=used.length; bot.start([stacked,step(3,[],false),step(4)],false,"11",sid);
                need(used.length==count+1 && used[count]===4,"skip unmet conditions and cooling skill");
                game.sfc.myUserName="Two"; bot.tick();
                need(!bot.running && used.length==count+1,"same avatar, switched account stops");
                player.objData={strUsername:"One"};
                need(bag.snapshot(game).classes.length==0,"stale avatar hidden during account transition");
                player.objData.strUsername="Two"; player.items=[mage]; var second:Object=bag.snapshot(game);
                need(second.session!=sid && second.classes.length==1 && second.classes[0].id=="22","different account bag");
                bot.start([step(3)],false,"11",second.session); need(!bot.running,"cannot start unowned class");
                bot.start([step(3)],false,"22",sid); need(!bot.running,"stale class picker rejected");
                var equips:int=0; world.sendEquipItemRequest=function(item:Object):void {if(item===mage) equips++;};
                bot.start([step(4)],false,"22",second.session);
                need(bot.running && equips==1 && used.length==count+1,"one equip request and no cast");
                mage.bEquip=1; bot.tick();
                need(used.length==count+1,"wait for new hotbar");
                bar[1]={id:12,isOK:true,ts:0,cd:0}; bot.tick();
                need(used.length==count+2 && used[used.length-1]===4,"confirmed hotbar and class");
                mage.bEquip=0; bot.tick(); need(!bot.running,"changing class stops");
                checkDestinations();
                note("MAP_TOOLS_CHECK passed: class ability names, room and pad, map-wide spawns, travel and cancellation");
                note("PROFILE_CHECK passed: bag isolation, shared class keys, equip acknowledgement, aura stacks/expiry, HP/MP, all/any and skip");
                checkResourceRules();
                note("STEP_CHECK passed: wait on/off, use the next ready skill, retry a skipped slot and disabled conditions");
                note("RULE_CHECK passed: inclusive points/percent, party membership and room, named aura stacks and saved rule modes");
                note("BOT_CHECK passed: right edge controls, ordered skills, targeting, cooldowns and stop");
            } finally { bot.dispose(); }
        }

        private static function checkDestinations():void {
            function expect(ok:Boolean, name:String):void {
                if (!ok) throw new Error("Map tools: " + name);
            }
            var player:Object = {items:[{ItemID:11,sName:"Mage",sType:"Class",bEquip:1},
                {ItemID:22,sName:"Healer",sType:"Class",bEquip:0}],objData:{strUsername:"Player"}};
            var game:MovieClip = new MovieClip();
            var bar:Array = [null,{nam:"Blue Impact"},{nam:"Two"},{nam:"Three"},{nam:"Four"}];
            var w:Object = {strAreaName:"fixture-1234",strMapName:"fixture",strFrame:"Enter",strPad:"Spawn",
                actions:{active:bar},myAvatar:player,mondefMap:{"3":{strMonName:"Wolf"}},
                monmap:[{MonMapID:5,MonID:3,strFrame:"r1"},{MonMapID:6,MonID:3,strFrame:"Enter"}]};
            game.world = w; game.sfc = {myUserName:"Player"};
            var bag:SkillBag = new SkillBag();
            expect(bag.snapshot(game).classes[1].skills[0]=="Blue Impact","button one reads the first class skill");
            player.items[0].bEquip=0; player.items[1].bEquip=1;
            expect(!bag.snapshot(game).classes[0].skills,"old bar never labeled with the incoming class");
            bar[1]={nam:"Heal"};
            expect(bag.snapshot(game).classes[0].skills[0]=="Heal","new class bar");
            var wolf:Object = {objData:{MonMapID:5,strMonName:"Wolf"},dataLeaf:{strFrame:"r1",intHP:10},pMC:{}};
            w.monsters = [wolf];
            var mobs:Array = MapDestinations.mobs(w);
            expect(mobs.length==2 && mobs[1].id=="5","map-wide spawns and live instances merge by map id");
            var nav:MapDestinations = new MapDestinations();
            nav.observe(game,1,0); w.strFrame="r1"; w.strPad="Left"; nav.observe(game,1,10);
            var mark:Object = nav.bookmark(game);
            expect(mark.area=="fixture-1234" && mark.cell=="r1" && mark.pad=="Left" && mark.route.length==2,"exact mark");
            var joined:String, walks:int=0, targets:int=0;
            w.gotoTown=function(a:String,c:String,p:String):void { joined=[a,c,p].join("/"); };
            w.getMonstersByCell=function(c:String):Array {return [wolf];};
            w.setTarget=function(unit:Object):void { if (unit===wolf) ++targets; };
            w.approachTarget=function():void { ++targets; };
            w.walkToPoint=function(x:Number,y:Number,fast:Boolean):Boolean { ++walks; return !fast; };
            var door:MovieClip=new MovieClip(); door.tCell="r1"; door.tPad="Left";
            door.graphics.beginFill(0); door.graphics.drawRect(0,0,10,10); door.graphics.endFill();
            game.addChild(door); w.arrEvent=[door];
            w.strAreaName="other-1";
            nav.begin(game,mark,null,1,20); nav.observe(game,1,30);
            expect(joined=="fixture-1234/Enter/Spawn" && nav.active && walks==0,"exact instance join before walking");
            w.strAreaName=mark.area; w.strFrame="Enter"; w.strPad="Spawn"; nav.observe(game,1,40);
            expect(walks==1 && nav.active,"walk onto map exit");
            w.strFrame="r1"; w.strPad="Left";
            expect(nav.observe(game,1,50).indexOf("At fixture-1234") == 0 && !nav.active,"confirmed destination");
            nav.begin(game,mark,"5",1,60); expect(targets==2 && !nav.active,"approach selected monster");
            w.strAreaName="other-2";
            expect(nav.begin(game,mark,"5",1,65).indexOf("Map changed")==0 && !nav.active,"stale mob selection");
            nav.begin(game,mark,null,1,70); nav.observe(game,2,80);
            expect(!nav.active,"stop on account switch");
            w.mapLoadInProgress=true; expect(!nav.bookmark(game),"ignore incomplete map transitions");
        }

        private static function checkResourceRules():void {
            var self:Object = {dataLeaf:{intHP:70000,intHPMax:200000,intMP:80,intMPMax:200}};
            var target:Object = {dataLeaf:{intHP:1200000,intMP:0,hudAuras:{"Battle Focus":{n:3,end:0}}}};
            var ally:Object = {strFrame:"A",intHP:180,intHPMax:600};
            var world:Object = {myAvatar:self,strFrame:"A",partyMembers:["Me","AlLy","Away","Dead","Unseen"],
                uoTree:{me:{strFrame:"A",intHP:1},ally:ally,away:{strFrame:"B",intHP:1,intHPMax:100},
                    dead:{strFrame:"A",intHP:0,intHPMax:50},stranger:{strFrame:"A",intHP:1,intHPMax:100}}};
            var game:Object = {world:world,sfc:{myUserName:"Me"}};
            var step:Object = {slot:2,wait:true,match:"all",rules:[]};
            function condition(kind:String, who:String, op:String, unit:String, value:int):Object {
                return {kind:kind,who:who,op:op,unit:unit,value:value};
            }
            function expect(rule:Object, yes:Boolean, detail:String):void {
                step.rules=[rule];
                if (!SkillRules.valid([step]) || SkillRules.allows(step,game,target) != yes) throw new Error("Rule: "+detail);
            }
            var hp:Object=condition("hp","self","lte","percent",35);
            var mana:Object=condition("mp","self","gte","raw",80);
            var party:Object=condition("partyhp","party","lte","percent",30);
            expect(hp,true,"equal health percent"); self.dataLeaf.intHP++; expect(hp,false,"one point above threshold");
            expect(mana,true,"equal mana points"); mana.value=81; expect(mana,false,"mana below threshold");
            expect(condition("mp","self","gte","percent",40),true,"mana percent equality");
            expect(condition("hp","target","gte","raw",1200000),true,"large points without max");
            expect(condition("hp","target","gte","percent",1),false,"unknown max");
            expect(condition("mp","target","lte","raw",0),true,"zero is observed");
            delete target.dataLeaf.intMP; expect(condition("mp","target","lte","raw",0),false,"missing is not zero");
            expect(party,true,"equal party health");
            expect(condition("partyhp","party","gte","raw",180),true,"party points");
            ally.strFrame="B"; expect(party,false,"exclude self, outsider, dead and other rooms");
            ally.strFrame="A"; world.partyMembers=[]; expect(party,false,"empty party");
            var aura:Object={kind:"aura",who:"target",name:" battle FOCUS ",op:"lte",value:3};
            expect(aura,true,"named aura at most"); aura.op="gte"; expect(aura,true,"exact stacks");
            aura.value=4; expect(aura,false,"insufficient stacks");
            aura.name="Absent"; aura.op="lte"; aura.value=0; expect(aura,true,"observed zero stacks");
            delete target.dataLeaf.hudAuras; expect(aura,false,"no aura snapshot");
            self.dataLeaf.intHP=70000;
            expect({kind:"hp",who:"self",op:"below",value:35},false,"legacy less than stays strict");
            expect({kind:"mp",who:"self",op:"above",value:40},false,"legacy greater than stays strict");
            step.rules=[hp,mana]; step.match="any";
            if (!SkillRules.allows(step,game,target)) throw new Error("Rule: any");
            step.match="all"; if (SkillRules.allows(step,game,target)) throw new Error("Rule: all");
            step.rulesEnabled=false; if (!SkillRules.valid([step]) || !SkillRules.allows(step,game,target)) throw new Error("Rule: off");
            step.rulesEnabled=true; if (SkillRules.allows(step,game,target)) throw new Error("Rule: enabled again");
            step.rules=[condition("hp","self","lte","percent",101)]; if (SkillRules.valid([step])) throw new Error("Rule: invalid percent");
            step.rules=[condition("partyhp","target","lte","raw",1)]; if (SkillRules.valid([step])) throw new Error("Rule: invalid party subject");
        }

        // Read the attached client first. Exercise two distinct names and logout
        // with a local world so CI never changes an account or joins a server.
        public static function checkReader(live:CurrentMapReader, config:File, note:Function):void {
            var input:FileStream = new FileStream();
            input.open(config, FileMode.READ);
            var names:Array;
            try { names = JSON.parse(input.readUTFBytes(input.bytesAvailable)) as Array; }
            finally { input.close(); }
            if (!names || names.length != 2 || names[0] == names[1]) throw new Error("Invalid map test data.");
            live.read(function(initial:String, failure:String):void {
                if (failure != null) { note("MAP_ERROR " + failure); return; }
                note("MAP_LIVE " + JSON.stringify(initial));
                var fixture:Object = {world:{strMapName:names[0]}};
                var reader:CurrentMapReader = new CurrentMapReader(function():Object { return fixture; });
                var index:int = 0;
                function received(map:String, error:String):void {
                    if (error != null) { note("MAP_ERROR " + error); reader.dispose(); return; }
                    note("MAP_SAMPLE " + JSON.stringify(map));
                    ++index;
                    if (index == 3) { reader.dispose(); return; }
                    fixture.world = index == 1 ? {strMapName:names[1]} : null;
                    reader.read(received);
                }
                reader.read(received);
            });
        }

        public static function run(game:MovieClip):Object {
            if (game.stage.scaleMode != StageScaleMode.SHOW_ALL ||
                game.stage.stageWidth != 960 || game.stage.stageHeight != 550 ||
                game.stage.getChildAt(0) != game || game.x != 0 || game.y != 0 ||
                game.scaleX != 1 || game.scaleY != 1 || game.scrollRect != null) {
                throw new Error("The legacy game coordinate system changed.");
            }
            var worldClass:Class = ApplicationDomain.currentDomain.getDefinition("World") as Class;
            var previous:Object = worldClass["currentInstance"];
            var host:MovieClip = new MovieClip();
            host.visible = false;
            host["ui"] = null;
            host["litePreference"] = {data: {bSmoothBG: false}};
            host["chatF"] = {mute: {timer: new Timer(1000)}, unmuteMe: function(event:Object):void {}};
            game.addChild(host);
            var world:MovieClip;
            try {
                world = new worldClass(host) as MovieClip;
                host["world"] = world;
                host.addChild(world);
                var map:MovieClip = world["map"] as MovieClip;
                var ground:MovieClip = new MovieClip();
                ground.graphics.beginFill(0x39A8D8);
                ground.graphics.drawRect(0, 0, 960, 500);
                ground.graphics.endFill();
                ground.graphics.beginFill(0xE83E8C);
                ground.graphics.drawRect(0, 0, 30, 500);
                ground.graphics.endFill();
                map.addChild(ground);

                // Negative control: the transform used by 0.1.6 must fail.
                host.x = 64;
                host.scaleX = host.scaleY = 0.75;
                world["applySmoothBG"]();
                var broken:Bitmap = map.getChildByName("bmp0") as Bitmap;
                var chars:MovieClip = world["CHARS"] as MovieClip;
                var wrong:Point = chars.globalToLocal(new Point(400, 300));
                if (broken == null || broken.bitmapData.getPixel(10, 100) == 0xE83E8C ||
                    (Math.abs(wrong.x - 400) < 0.01 && Math.abs(wrong.y - 300) < 0.01)) {
                    throw new Error("The regression check did not detect the old transform.");
                }

                host.x = 0;
                host.scaleX = host.scaleY = 1;
                world["applySmoothBG"]();
                var restored:Bitmap = map.getChildByName("bmp0") as Bitmap;
                var target:Point = chars.globalToLocal(new Point(400, 300));
                if (restored == null || restored.bitmapData.getPixel(10, 100) != 0xE83E8C ||
                    Math.abs(target.x - 400) > 0.01 || Math.abs(target.y - 300) > 0.01) {
                    throw new Error("Map rasterisation or movement coordinates are incorrect.");
                }
                return {old_transform_detected: true, map_left_edge_restored: true,
                    movement_coordinates_restored: true};
            } finally {
                if (world != null) {
                    world["cleanupMap"]();
                    world["killTimers"]();
                    world["killListeners"]();
                }
                if (host.parent != null) host.parent.removeChild(host);
                worldClass["currentInstance"] = previous;
            }
            return null;
        }
    }
}
