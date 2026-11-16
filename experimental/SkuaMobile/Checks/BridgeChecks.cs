using Aqw.SkuaMobile;
using System.Text.Json;

internal static class BridgeChecks
{
    public static async Task Run()
    {
        void Check(bool value, string label)
        { if (!value) throw new Exception("FAIL bridge: " + label); Console.WriteLine("PASS bridge: " + label); }
        using var bridge = new GameBridge(() => false);
        string Reply(string request, string value, bool ok = true, string? session = null)
        {
            using var doc = JsonDocument.Parse(request);
            return JsonSerializer.Serialize(new { v = 1, session = session ?? bridge.Session,
                id = doc.RootElement.GetProperty("id").GetInt64(), ok, result = value, error = value });
        }
        var first = bridge.CallAsync("getGameObject", ["world.strMapName"], TimeSpan.FromSeconds(5));
        var second = bridge.CallAsync("isNull", ["world"], TimeSpan.FromSeconds(5));
        Check(bridge.TryTakeRequest(out var a) && a is not null, "first request queued");
        Check(bridge.TryTakeRequest(out var b) && b is not null, "second request queued");
        bridge.CompleteResponse(Reply(b!, "false")); bridge.CompleteResponse(Reply(a!, "\"battleon\""));
        Check(await first == "\"battleon\"" && await second == "false", "out-of-order replies preserve Skua JSON results");
        Check(!bridge.CompleteResponse(Reply(a!, "duplicate")), "duplicate replies ignored");

        using var stop = new CancellationTokenSource();
        var cancelled = bridge.CallAsync("callGameFunction", ["world.jump", "Enter", "Spawn"], TimeSpan.FromSeconds(5), stop.Token);
        stop.Cancel();
        Check(!bridge.TryTakeRequest(out _), "cancelled queued command never dispatched");
        try { await cancelled; throw new Exception("Cancellation ignored"); } catch (OperationCanceledException) { }
        var timedOut = bridge.CallAsync("getGameObject", ["world"], TimeSpan.FromMilliseconds(10));
        bridge.TryTakeRequest(out var late);
        try { await timedOut; throw new Exception("Timeout ignored"); } catch (TimeoutException) { }
        Check(!bridge.CompleteResponse(Reply(late!, "null")) && bridge.PendingCount == 0, "late reply rejected and waiter released");

        var failed = bridge.CallAsync("unsupported", [], TimeSpan.FromSeconds(5)); bridge.TryTakeRequest(out var errorRequest);
        Check(!bridge.CompleteResponse(Reply(errorRequest!, "null", session: "old-session")), "old game attachment rejected");
        try { bridge.CompleteResponse("{\"v\":1,\"session\":\"" + bridge.Session + "\",\"id\":5,\"ok\":true}"); }
        catch (KeyNotFoundException) { }
        Check(bridge.PendingCount == 1, "malformed response preserves pending call");
        bridge.CompleteResponse(Reply(errorRequest!, "Unsupported bridge method", ok: false));
        try { await failed; throw new Exception("AIR error swallowed"); }
        catch (GameBridgeException e) { Check(e.Message == "Unsupported bridge method", "AIR error reaches script worker"); }
        using var ui = new GameBridge(() => true);
        try { ui.Call("isNull", ["world"], TimeSpan.FromSeconds(1)); throw new Exception("UI-thread call allowed"); }
        catch (InvalidOperationException) { Check(ui.PendingCount == 0, "UI-thread sync call rejected before enqueue"); }
        using var detached = new GameBridge(() => false);
        var abandoned = detached.CallAsync("isNull", ["world"], TimeSpan.FromSeconds(5)); detached.Dispose();
        try { await abandoned; throw new Exception("Disposal ignored"); }
        catch (ObjectDisposedException) { Check(detached.PendingCount == 0, "detach releases pending calls"); }
    }
}
