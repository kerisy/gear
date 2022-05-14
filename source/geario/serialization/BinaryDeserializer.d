module geario.serialization.BinaryDeserializer;

import geario.serialization.Common;
import geario.serialization.Specify;
import std.traits;

/**
 * 
 */
struct BinaryDeserializer {

    private {
        const(ubyte)[] _buffer;
    }

    this(ubyte[] buffer) {
        this._buffer = buffer;
    }

    const(ubyte[]) Bytes() const nothrow {
        return _buffer;
    }

    ulong BytesLeft() const {
        return _buffer.length;
    }

    T iArchive(SerializationOptions options, T)()
            if (!isDynamicArray!T && !isAssociativeArray!T && !is(T == class) && __traits(compiles, T())) {
        T obj;
        specify!(options)(this, obj);
        return obj;
    }

    T iArchive(SerializationOptions options, T)()
            if (!isDynamicArray!T && !isAssociativeArray!T && !is(T == class)
                && !__traits(compiles, T())) {
        T obj = void;
        specify!(options)(this, obj);
        return obj;
    }

    T iArchive(SerializationOptions options, T, A...)(A args) if (is(T == class)) {
        T obj = new T(args);
        specify!(options)(this, obj);
        return obj;
    }

    T iArchive(SerializationOptions options, T)() if (isDynamicArray!T || isAssociativeArray!T) {
        return iArchive!(options, T, ushort)();
    }

    T iArchive(SerializationOptions options, T, U)() if (isDynamicArray!T || isAssociativeArray!T) {
        T obj;
        specify!(options)(this, obj);
        return obj;
    }

    void PutUbyte(ref ubyte val) {
        val = _buffer[0];
        _buffer = _buffer[1 .. $];
    }

    void PutClass(SerializationOptions options, T)(T val) if (is(T == class)) {
        specifyClass!(options)(this, val);
    }

    deprecated("Using take instead.")
    alias PutRaw = Take;

    const(ubyte)[] Take(size_t length) {
        const(ubyte)[] res = _buffer[0 .. length];
        _buffer = _buffer[length .. $];
        return res;
    }

    // T takeAs(T, SerializationOptions options)() 
    //     if (!is(T == enum) && (isSigned!T || isBoolean!T || is(T == char) || isFloatingPoint!T)) {
    //     T r;
    //     // T* val = &r;

    //     // ubyte val0 = (val >> 24);
    //     // ubyte val1 = cast(ubyte)(val >> 16);
    //     // ubyte val2 = cast(ubyte)(val >> 8);
    //     // ubyte val3 = val & 0xff;
    //     // PutUbyte(val0);
    //     // PutUbyte(val1);
    //     // PutUbyte(val2);
    //     // PutUbyte(val3);
    //     // val = (val0 << 24) + (val1 << 16) + (val2 << 8) + val3;
    //     return r;
    // }

    // T takeAs(T, SerializationOptions options)() {
    //     return T.init;
    // }

    bool IsNullObj() {
        return _buffer[0 .. 4] == NULL ? true : false;
    }
}
