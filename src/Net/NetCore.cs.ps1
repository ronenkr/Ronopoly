#
# Ronopoly - the socket engine, as inline C#.
#
# This is the ONLY place in the project where a background thread exists, and
# it deliberately touches nothing but lock-free queues. It never sees a WPF
# object, so there is nothing to marshal back to the UI thread: the UI simply
# POLLS Inbox from a DispatcherTimer.
#
# That choice removes the single hardest problem in PowerShell 5.1 + WPF work.
# The usual advice - do the socket read in a runspace and marshal back with
# $window.Dispatcher.Invoke({...}) - fails intermittently with "There is no
# Runspace available to run scripts in this thread", because a scriptblock
# handed to Dispatcher.Invoke carries the session state of the runspace that
# created it. Polling a ConcurrentQueue has no such failure mode.
#
# Wire format: a 4-byte big-endian length prefix followed by UTF-8 JSON.
# Length prefixing is trivially correct across partial reads (unlike newline
# delimiting, which has to scan and then handle a split escape), and it gives a
# free sanity check: a frame claiming more than 4 MB is a malformed peer.
#

function Initialize-RonNetCore {
    # Add-Type can only compile a given type name ONCE per session, and a
    # PowerShell class cannot be redefined either - so this guard is what lets
    # the app be re-bootstrapped in a live console during development.
    if ('Ronopoly.Net.RonConnection' -as [type]) { return }

    $source = @'
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace Ronopoly.Net
{
    /// <summary>One TCP peer. A dedicated reader thread pushes whole frames
    /// into Inbox; the UI thread drains it whenever it likes.</summary>
    public class RonConnection
    {
        public const int MaxFrameBytes = 4 * 1024 * 1024;

        private readonly TcpClient _client;
        private readonly NetworkStream _stream;
        private readonly Thread _reader;
        private readonly object _writeLock = new object();
        private volatile bool _closed;

        public ConcurrentQueue<string> Inbox { get; private set; }
        public string LastError { get; private set; }
        public string RemoteName { get; set; }
        public int PlayerId { get; set; }
        public long LastSeenTicks;

        public RonConnection(TcpClient client)
        {
            _client = client;
            _client.NoDelay = true;
            _stream = client.GetStream();
            Inbox = new ConcurrentQueue<string>();
            LastError = "";
            RemoteName = "";
            PlayerId = -1;
            LastSeenTicks = DateTime.UtcNow.Ticks;

            _reader = new Thread(ReadLoop);
            _reader.IsBackground = true;   // never keeps the process alive
            _reader.Name = "ronopoly-read";
            _reader.Start();
        }

        public bool IsConnected { get { return !_closed && _client.Connected; } }

        public string Endpoint
        {
            get
            {
                try { return _client.Client.RemoteEndPoint.ToString(); }
                catch { return "?"; }
            }
        }

        public void Send(string message)
        {
            if (_closed) return;
            byte[] payload = Encoding.UTF8.GetBytes(message);
            byte[] frame = new byte[4 + payload.Length];
            frame[0] = (byte)((payload.Length >> 24) & 0xFF);
            frame[1] = (byte)((payload.Length >> 16) & 0xFF);
            frame[2] = (byte)((payload.Length >> 8) & 0xFF);
            frame[3] = (byte)(payload.Length & 0xFF);
            Buffer.BlockCopy(payload, 0, frame, 4, payload.Length);
            try
            {
                // One writer at a time, or two frames interleave and both are lost.
                lock (_writeLock) { _stream.Write(frame, 0, frame.Length); _stream.Flush(); }
            }
            catch (Exception ex) { Fail(ex.Message); }
        }

        private void ReadLoop()
        {
            byte[] header = new byte[4];
            try
            {
                while (!_closed)
                {
                    if (!ReadExactly(header, 4)) break;
                    int length = (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
                    if (length < 0 || length > MaxFrameBytes)
                    {
                        Fail("frame length " + length + " is out of range");
                        break;
                    }
                    byte[] payload = new byte[length];
                    if (!ReadExactly(payload, length)) break;
                    Inbox.Enqueue(Encoding.UTF8.GetString(payload));
                    Interlocked.Exchange(ref LastSeenTicks, DateTime.UtcNow.Ticks);
                }
            }
            catch (Exception ex) { Fail(ex.Message); }
            finally { _closed = true; }
        }

        private bool ReadExactly(byte[] buffer, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int read = _stream.Read(buffer, offset, count - offset);
                if (read <= 0) return false;   // clean close
                offset += read;
            }
            return true;
        }

        private void Fail(string message)
        {
            if (string.IsNullOrEmpty(LastError)) LastError = message;
            _closed = true;
        }

        public void Close()
        {
            _closed = true;
            try { _stream.Close(); } catch { }
            try { _client.Close(); } catch { }
        }
    }

    /// <summary>Accepts connections on a background thread and queues them.</summary>
    public class RonListener
    {
        private TcpListener _listener;
        private Thread _accept;
        private volatile bool _closed;

        public ConcurrentQueue<RonConnection> Pending { get; private set; }
        public string LastError { get; private set; }
        public int Port { get; private set; }

        public RonListener()
        {
            Pending = new ConcurrentQueue<RonConnection>();
            LastError = "";
        }

        /// <summary>Returns false and sets LastError rather than throwing, so
        /// the caller can show a firewall or port-in-use message instead of a
        /// stack trace.</summary>
        public bool Start(int port, bool loopbackOnly)
        {
            try
            {
                IPAddress bind = loopbackOnly ? IPAddress.Loopback : IPAddress.Any;
                _listener = new TcpListener(bind, port);
                _listener.Start();
                Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
                _accept = new Thread(AcceptLoop);
                _accept.IsBackground = true;
                _accept.Name = "ronopoly-accept";
                _accept.Start();
                return true;
            }
            catch (Exception ex) { LastError = ex.Message; return false; }
        }

        private void AcceptLoop()
        {
            try
            {
                while (!_closed)
                {
                    TcpClient client = _listener.AcceptTcpClient();
                    Pending.Enqueue(new RonConnection(client));
                }
            }
            catch (Exception ex) { if (!_closed) LastError = ex.Message; }
        }

        public void Stop()
        {
            _closed = true;
            try { if (_listener != null) _listener.Stop(); } catch { }
        }
    }

    public static class RonDial
    {
        /// <summary>Connects with a timeout. Returns null and fills error on
        /// failure; a blocking Connect would otherwise hang the lobby for the
        /// full 20-second TCP timeout.</summary>
        public static RonConnection Connect(string host, int port, int timeoutMs, out string error)
        {
            error = "";
            TcpClient client = new TcpClient();
            try
            {
                IAsyncResult ar = client.BeginConnect(host, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs))
                {
                    client.Close();
                    error = "timed out connecting to " + host + ":" + port;
                    return null;
                }
                client.EndConnect(ar);
                return new RonConnection(client);
            }
            catch (Exception ex)
            {
                error = ex.Message;
                try { client.Close(); } catch { }
                return null;
            }
        }

        public static string GetLocalAddress()
        {
            try
            {
                // Opening a UDP socket to a public address picks the interface
                // Windows would actually route over, without sending anything.
                using (Socket s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0))
                {
                    s.Connect("8.8.8.8", 65530);
                    return ((IPEndPoint)s.LocalEndPoint).Address.ToString();
                }
            }
            catch { return "127.0.0.1"; }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -ReferencedAssemblies 'System', 'System.Core' -ErrorAction Stop
}
