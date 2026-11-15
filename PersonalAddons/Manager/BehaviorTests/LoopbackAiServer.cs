using System.Net;
using System.Net.Sockets;
using System.Text;

// Real local transport only: verifies default-handler redirect behavior that an
// injected stub cannot exercise. No credentials or external requests are used.
internal sealed class LoopbackAiServer : IAsyncDisposable
{
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    private readonly CancellationTokenSource shutdown = new();
    private readonly Task serving;
    private int requests;
    public int Requests => Volatile.Read(ref requests);
    public string BaseUrl { get; }

    public LoopbackAiServer()
    {
        listener.Start();
        BaseUrl = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}";
        serving = ServeAsync();
    }

    private async Task ServeAsync()
    {
        try
        {
            while (!shutdown.IsCancellationRequested)
            {
                using var client = await listener.AcceptTcpClientAsync(shutdown.Token);
                await using var stream = client.GetStream();
                var header = new List<byte>();
                var single = new byte[1];
                while (header.Count < 16 * 1024)
                {
                    if (await stream.ReadAsync(single, shutdown.Token) == 0) break;
                    header.Add(single[0]);
                    if (header.Count >= 4 && Encoding.ASCII.GetString(header.TakeLast(4).ToArray()) == "\r\n\r\n") break;
                }
                var lines = Encoding.ASCII.GetString(header.ToArray()).Split("\r\n");
                var lengthHeader = lines.FirstOrDefault(l => l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase));
                var length = lengthHeader is null ? 0 : int.Parse(lengthHeader.Split(':', 2)[1].Trim());
                if (length > 64 * 1024) throw new InvalidDataException("Fixture request too large");
                var body = new byte[length];
                await stream.ReadExactlyAsync(body, shutdown.Token);
                var number = Interlocked.Increment(ref requests);
                var content = number == 1 ? "" : "{\"choices\":[{\"message\":{\"content\":\"fixture\"}}]}";
                var response = number == 1
                    ? $"HTTP/1.1 307 Temporary Redirect\r\nLocation: {BaseUrl}/unselected-endpoint\r\n"
                    : "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n";
                response += $"Content-Length: {Encoding.UTF8.GetByteCount(content)}\r\nConnection: close\r\n\r\n{content}";
                await stream.WriteAsync(Encoding.UTF8.GetBytes(response), shutdown.Token);
            }
        }
        catch (OperationCanceledException) when (shutdown.IsCancellationRequested) { }
        catch (SocketException) when (shutdown.IsCancellationRequested) { }
        catch (ObjectDisposedException) when (shutdown.IsCancellationRequested) { }
    }

    public async ValueTask DisposeAsync()
    {
        shutdown.Cancel();
        listener.Stop();
        await serving;
        shutdown.Dispose();
    }
}
