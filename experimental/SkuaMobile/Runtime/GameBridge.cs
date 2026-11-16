using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

namespace Aqw.SkuaMobile;

/// <summary>Worker-to-AIR mailbox; the native host must drain it on the AIR thread.</summary>
public sealed class GameBridge(Func<bool> isGameThread) : IDisposable
{
    private sealed record CallState(TaskCompletionSource<string?> Completion, CancellationToken Token, long Start, TimeSpan Timeout)
    {
        public bool Active => !Token.IsCancellationRequested && Stopwatch.GetElapsedTime(Start) < Timeout;
        public void Expire()
        {
            if (Token.IsCancellationRequested) Completion.TrySetCanceled(Token);
            else Completion.TrySetException(new TimeoutException("AIR command timed out."));
        }
    }
    private readonly ConcurrentQueue<string> outgoing = new();
    private readonly ConcurrentDictionary<long, CallState> pending = new();
    private readonly object gate = new();
    private long nextId;
    private bool disposed;
    public string Session { get; } = Guid.NewGuid().ToString("N");
    public int PendingCount => pending.Count;

    public string? Call(string method, object?[] args, TimeSpan timeout, CancellationToken token = default)
    {
        if (isGameThread()) throw new InvalidOperationException("Run synchronous bridge calls off the AIR/UI thread.");
        return CallAsync(method, args, timeout, token).GetAwaiter().GetResult();
    }

    public async Task<string?> CallAsync(string method, object?[] args, TimeSpan timeout, CancellationToken token = default)
    {
        if (timeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(timeout));
        if (string.IsNullOrWhiteSpace(method)) throw new ArgumentException("A method is required.", nameof(method));
        token.ThrowIfCancellationRequested();
        long id = Interlocked.Increment(ref nextId);
        if (id > 9007199254740991) throw new InvalidOperationException("Create a new bridge session before IDs exceed ActionScript precision.");
        var json = JsonSerializer.Serialize(new Dictionary<string, object?> { ["v"] = 1, ["session"] = Session, ["id"] = id, ["method"] = method, ["args"] = args });
        if (json.Length > 65536) throw new ArgumentException("Bridge request is too large.");
        var completion = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (pending.Count >= 128 || outgoing.Count >= 256) throw new InvalidOperationException("AIR host is not draining the bounded bridge queue.");
            pending[id] = new(completion, token, Stopwatch.GetTimestamp(), timeout);
            outgoing.Enqueue(json);
        }
        try { return await completion.Task.WaitAsync(timeout, token).ConfigureAwait(false); }
        finally { pending.TryRemove(id, out _); }
    }

    public bool TryTakeRequest(out string? request)
    {
        while (outgoing.TryDequeue(out var json))
        {
            using var doc = JsonDocument.Parse(json);
            long id = doc.RootElement.GetProperty("id").GetInt64();
            if (!pending.TryGetValue(id, out var call)) continue;
            if (call.Active) { request = json; return true; }
            if (pending.TryRemove(id, out var expired)) expired.Expire();
        }
        request = null; return false;
    }

    public bool CompleteResponse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.GetProperty("v").GetInt32() != 1 || root.GetProperty("session").GetString() != Session) return false;
        long id = root.GetProperty("id").GetInt64();
        bool ok = root.GetProperty("ok").GetBoolean();
        // Parse the whole response before removing a waiter: malformed replies cannot lose it.
        string? value = root.GetProperty(ok ? "result" : "error").GetString();
        if (!pending.TryRemove(id, out var call)) return false;
        if (!call.Active) { call.Expire(); return false; }
        if (ok) call.Completion.TrySetResult(value);
        else call.Completion.TrySetException(new GameBridgeException(value ?? "AIR command failed."));
        return true;
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            foreach (long id in pending.Keys)
                if (pending.TryRemove(id, out var call)) call.Completion.TrySetException(new ObjectDisposedException(nameof(GameBridge)));
            while (outgoing.TryDequeue(out _)) { }
        }
    }
}

public sealed class GameBridgeException(string message) : Exception(message) { }

/// <summary>Basic Skua Flash method names and JSON-string results, without ActiveX.</summary>
public sealed class MobileFlashClient(GameBridge bridge, TimeSpan timeout, CancellationToken token = default)
{
    public string? Call(string method, params object?[] args) => bridge.Call(method, args, timeout, token);
    public string? GetGameObject(string path) => Call("getGameObject", path);
    public T? GetGameObject<T>(string path) => JsonSerializer.Deserialize<T>(GetGameObject(path) ?? "null");
    public bool IsNull(string path) => bool.Parse(Call("isNull", path) ?? throw new GameBridgeException("Missing isNull result."));
    public string? CallGameFunction(string path, params object?[] args) => Call("callGameFunction", new object?[] { path }.Concat(args).ToArray());
}
