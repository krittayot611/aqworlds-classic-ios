using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Aqw.SkuaMobile;

// The bundled script can ask AIR for the current map and display the result.
public sealed class MapReadout(Func<string?> read, Action<string?> show)
{
    public string? CurrentMap => read();
    public void Show(string? map) => show(map);
}

internal static class MapHost
{
    private static readonly object CompilerLock = new();
    private static CompilationResult? compiled;

    private static CompilationResult LoadScript(string root)
    {
        lock (CompilerLock)
        {
            if (compiled is not null) return compiled;
            var script = new ScriptPackageReader(Path.Combine(root, "scripts")).Read("ReadMap.cs");
            var refs = Directory.GetFiles(Path.Combine(root, "metadata"), "*.dll");
            var result = new ScriptCompiler().Compile(script, refs);
            if (!result.Success) throw new InvalidOperationException(string.Join('\n', result.Errors));
            return compiled = result;
        }
    }

    private static unsafe string Exchange(nint callback, nint context, string request)
    {
        var send = (delegate* unmanaged[Cdecl]<nint, byte*, byte*, int, int>)callback;
        byte[] envelope = Encoding.UTF8.GetBytes(request + "\0");
        byte[] reply = new byte[8192];
        fixed (byte* input = envelope, output = reply)
        {
            int length = send(context, input, output, reply.Length);
            if (length < 0 || length >= reply.Length)
                throw new IOException("AIR did not return a map response.");
            return Encoding.UTF8.GetString(reply, 0, length);
        }
    }

    // Called on a native worker. Only AIR's status-event handler touches the game.
    [UnmanagedCallersOnly(EntryPoint = "aqw_read_current_map", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static unsafe int Read(nint rootPtr, nint context, nint callback, byte* output, int capacity)
    {
        if (rootPtr == 0 || context == 0 || callback == 0 || output == null || capacity < 2) return -1;
        try
        {
            string root = Marshal.PtrToStringUTF8(rootPtr)!;
            var script = LoadScript(root);
            using var bridge = new GameBridge(() => false);
            string? ReadFromAir()
            {
                var pending = bridge.CallAsync("currentMap", [], TimeSpan.FromSeconds(20));
                if (!bridge.TryTakeRequest(out var request) || request is null)
                    throw new InvalidOperationException("No map request queued.");
                string reply = Exchange(callback, context, request);
                if (!bridge.CompleteResponse(reply)) throw new IOException("Unexpected AIR map reply.");
                return JsonSerializer.Deserialize<string>(pending.GetAwaiter().GetResult() ?? "null");
            }
            bool displayed = false;
            string? map = null;
            new ScriptCompiler().Execute(script, new MapReadout(ReadFromAir, value => { map = value; displayed = true; }));
            if (!displayed) throw new InvalidOperationException("The map script returned without a result.");
            return Write(output, capacity, map ?? "") ? 0 : -1;
        }
        catch (Exception error)
        {
            Write(output, capacity, error.GetBaseException().Message);
            return -1;
        }
    }

    private static unsafe bool Write(byte* output, int capacity, string value)
    {
        output[0] = 0;
        int length = Encoding.UTF8.GetByteCount(value);
        if (length >= capacity) return false;
        Encoding.UTF8.GetBytes(value.AsSpan(), new Span<byte>(output, length));
        output[length] = 0;
        return true;
    }
}
