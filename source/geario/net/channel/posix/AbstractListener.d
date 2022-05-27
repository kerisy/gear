module geario.net.channel.posix.AbstractListener;

// dfmt off
version(Posix):
// dfmt on

import geario.event.selector.Selector;
import geario.net.channel.AbstractSocketChannel;
import geario.net.channel.Types;
import geario.logging;

import std.conv;
import std.socket;

import core.sys.posix.sys.socket;



/**
 *  TCP Server
 */
abstract class AbstractListener : AbstractSocketChannel {
    this(Selector loop, AddressFamily family = AddressFamily.INET) {
        super(loop, ChannelType.Accept);
        setFlag(ChannelFlag.Read, true);
        this.socket = new TcpSocket(family);
    }

    protected bool OnAccept(scope AcceptHandler handler) {
        version (GEAR_DEBUG)
            Trace("new connection coming...");
        this.ClearError();

        // http://man7.org/linux/man-pages/man2/accept.2.html
        version(HAVE_EPOLL) {
            socket_t clientFd = cast(socket_t)(accept4(this.handle, null, null, SOCK_NONBLOCK | SOCK_CLOEXEC));
            //socket_t clientFd = cast(socket_t)(accept(this.handle, null, null));

        } else {
            socket_t clientFd = cast(socket_t)(accept(this.handle, null, null));
        }
        if (clientFd == socket_t.init)
            return false;

        version (GEAR_DEBUG)
            log.trace("Listener fd=%d, sslClient fd=%d", this.handle, clientFd);

        if (handler !is null)
            handler(new Socket(clientFd, this.LocalAddress.addressFamily));
        return true;
    }

    override void OnWriteDone() {
        version (GEAR_DEBUG)
            log.trace("a new connection created");
    }
}


extern (C) nothrow @nogc {
    int     accept4(int, sockaddr*, socklen_t*, int);
}

enum int SOCK_CLOEXEC = std.conv.octal!(2000000); /* Atomically set close-on-exec flag for the
                   new descriptor(s).  */
enum int SOCK_NONBLOCK = std.conv.octal!4000; /* Atomically mark descriptor(s) as
                   non-blocking.  */
