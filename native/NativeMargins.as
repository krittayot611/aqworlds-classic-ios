package {
    import flash.external.ExtensionContext;
    import flash.system.Capabilities;

    public final class NativeMargins {
        private static var context:ExtensionContext;
        public static function show(verify:Boolean = false):String {
            if (Capabilities.os.indexOf("iPhone") != 0) return "desktop preview";
            if (context == null) context = ExtensionContext.createExtensionContext("com.aqw.classic.margins", "");
            if (context == null) throw new Error("The native background extension is unavailable.");
            return String(context.call("show", verify));
        }
    }
}
