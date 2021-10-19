module gear.codec.Framed;


import gear.buffer.Buffer;
import gear.buffer.Bytes;
import gear.codec.Codec;
import gear.logging.ConsoleLogger;
import gear.net.TcpListener;
import gear.net.TcpStream;
import gear.net.channel.Common;

alias FrameHandler(T) = void delegate(T bufer);

/** 
 * 
 */
class Framed(T) {
    private TcpStream _tcpStream;
    private Codec _codec;
    private FrameHandler!T _handler;

    this(TcpStream tcpStream, Codec codec) {  
        codec.GetDecoder().OnFrame((Object frame) {
            T f = cast(T) frame;
            if (_handler !is null) {
                _handler(f);
            }
        });

        tcpStream.Received((Bytes bytes) {

            Buffer buffer;    
            buffer.Append(bytes);
                  
            DataHandleStatus status = codec.GetDecoder().Decode(buffer);

            version(GEAR_IO_DEBUG) {
                Trace("DataHandleStatus :", status);
            }

            return status;
        });
    }

    void OnFrame(FrameHandler!T handler) {
        _handler = handler;
    }



}