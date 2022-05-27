﻿/*
 * Geario - A cross-platform abstraction library with asynchronous I/O.
 *
 * Copyright (C) 2021-2022 Kerisy.com
 *
 * Website: https://www.kerisy.com
 *
 * Licensed under the Apache-2.0 License.
 *
 */


deprecated("It's buggy. Use geario.serialization.JsonSerializer instead.")
module geario.util.Serialize;

import std.traits;
import std.string;
import core.stdc.string;
import std.stdio;
import std.bitmanip;
import std.math;
public import std.json;

public:
enum IGNORE = 1024;

class UnIgnoreArray{
    
    void setUnIgnore(T)()
    {
        _unIgnore[T.stringof] = true;
    }

    bool ignore(T)()
    {
        return T.stringof !in _unIgnore;
    }

private:
    bool[string] _unIgnore;
}


private:

class RefClass
{
    size_t[size_t] map;
    void*[] arr;
    uint level;
    bool ignore;                     ///  all class or struct ignore or not. 
    UnIgnoreArray unIgnore;            ///  part class unignore. 
}

enum MAGIC_KEY = "o0o0o";

enum bool isType(T1, T2) = is(T1 == T2) || is(T1 == ImmutableOf!T2)
        || is(T1 == ConstOf!T2) || is(T1 == InoutOf!T2)
        || is(T1 == SharedOf!T2) || is(T1 == SharedConstOf!T2) || is(T1 == SharedInoutOf!T2);

enum bool isSignedType(T) = isType!(T, byte) || isType!(T, short) || isType!(T,
            int) || isType!(T, long);
enum bool isUnsignedType(T) = isType!(T, ubyte) || isType!(T, ushort)
        || isType!(T, uint) || isType!(T, ulong);
enum bool isBigSignedType(T) = isType!(T, int) || isType!(T, long);
enum bool isBigUnsignedType(T) = isType!(T, uint) || isType!(T, ulong);

//unsigned
ulong[] byte_dots = [1 << 7, 1 << 14, 1 << 21, 1 << 28, cast(ulong) 1 << 35,
    cast(ulong) 1 << 42, cast(ulong) 1 << 49, cast(ulong) 1 << 56, cast(ulong) 1 << 63,];

//signed
ulong[] byte_dots_s = [1 << 6, 1 << 13, 1 << 20, 1 << 27, cast(ulong) 1 << 34,
    cast(ulong) 1 << 41, cast(ulong) 1 << 48, cast(ulong) 1 << 55, cast(ulong) 1 << 62,];

ubyte getbytenum(ulong v)
{
    ubyte i = 0;
    for (; i < byte_dots.length; i++)
    {
        if (v < byte_dots[i])
        {
            break;
        }
    }
    return cast(ubyte)(i + 1);
}

ubyte getbytenums(ulong v)
{
    ubyte i = 0;
    for (; i < byte_dots_s.length; i++)
    {
        if (v < byte_dots_s[i])
        {
            break;
        }
    }

    return cast(ubyte)(i + 1);
}

//signed
byte[] toVariant(T)(T t) if (isSignedType!T)
{
    bool symbol = false;
    if (t < 0)
        symbol = true;

    ulong val = cast(ulong) abs(t);

    ubyte num = getbytenums(val);

    ubyte[] var;
    if(num == 1)
    {
        if (symbol)
            val = val | 0x40;
    }
    else{
        for (size_t i = num; i > 1; i--)
        {
            auto n = val / (byte_dots_s[i - 2] * 2);
            if (symbol && i == num)
                n = n | 0x40;
            var ~= cast(ubyte) n;
            val = (val % (byte_dots_s[i - 2] * 2));
        }
    }

    var ~= cast(ubyte)(val | 0x80);
    return cast(byte[]) var;
}

T toT(T)(const byte[] b, out long index) if (isSignedType!T)
{
    T val = 0;
    ubyte i = 0;
    bool symbol = false;

    if(b.length == 1)
    {
        val = (b[i] & 0x3F);
        if (b[i] & 0x40)
            symbol = true;
    }
    else
    {
        for (i = 0; i < b.length; i++)
        {
            if (i == 0)
            {
                val = (b[i] & 0x3F);
                if (b[i] & 0x40)
                    symbol = true;            
            }
            else
            {
                val = cast(T)((val << 7) + (b[i] & 0x7F));
            }
        
            if (b[i] & 0x80)
                break;
        }
    }

    index = i + 1;
    if (symbol)
        return cast(T)(val * -1);
    else
        return val;
}

//unsigned
byte[] toVariant(T)(T t) if (isUnsignedType!T)
{
    ubyte num = getbytenum(cast(ulong) t);
    T val = t;
    ubyte[] var;
    for (size_t i = num; i > 1; i--)
    {
        auto n = val / (byte_dots[i - 2]);
        var ~= cast(ubyte) n;
        val = val % (byte_dots[i - 2]);
    }
    var ~= cast(ubyte)(val | 0x80);
    return cast(byte[]) var;
}

//unsigned
T toT(T)(const byte[] b, out long index) if (isUnsignedType!T)
{
    T val = 0;
    ubyte i = 0;
    for (i = 0; i < b.length; i++)
    {

        val = cast(T)((val << 7) + (b[i] & 0x7F));
        if (b[i] & 0x80)
            break;
    }
    index = i + 1;
    return val;
}

byte getbasictype(long size)
{
    if (size == 1)
        return 0;
    else if (size == 2)
        return 1;
    else if (size == 4)
        return 2;
    else if (size == 8)
        return 3;
    else
        assert(0);
}

byte getbasicsize(byte type)
{
    if (type == 0)
        return 1;
    else if (type == 1)
        return 2;
    else if (type == 2)
        return 4;
    else if (type == 3)
        return 8;
    else
        assert(0);
}

string serializeMembers(T)()
{
    string str;
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {
            str ~= "data ~= Serialize(t." ~ m ~ " , stack , level + 1);";
        }
    }
    return str;
}

string unserializeMembers(T)()
{
    string str;
    // str ~= "long parse = 0; ";
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {
            str ~= " if ( index < parse_index)";
            str ~= "{";
            str ~= "t." ~ m ~ " = unserialize!(typeof(t." ~ m
                ~ "))(data[cast(uint)index .. data.length] , parse , stack); ";
            str ~= "index += parse; }";
        }

    }
    return str;
}

string getsizeMembers(T)()
{
    string str;
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {
        str ~= "total += getsize(t." ~ m ~ " , stack , level + 1);";
        }        
    }
    return str;
}

///////////////////////////////////////////////////////////
// basic
// type           size
//  0     -         1
//  1     -            2
//  2     -            4
//  3     -             8
//    data
///////////////////////////////////////////////////////////
///
byte[] Serialize(T)(T t, RefClass stack, uint level)
        if (isScalarType!T && !isBigSignedType!T && !isBigUnsignedType!T && !is(T == enum))
{
    byte[] data;
    data.length = T.sizeof + 1;
    data[0] = getbasictype(T.sizeof);
    memcpy(data.ptr + 1, &t, T.sizeof);
    return data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (isScalarType!T && !isBigSignedType!T && !isBigUnsignedType!T && !is(T == enum))
{
    assert(cast(byte) T.sizeof == getbasicsize(data[0]));

    T value;
    memcpy(&value, data.ptr + 1, T.sizeof);

    parse_index = T.sizeof + 1;
    return value;
}

size_t getsize(T)(T t, RefClass stack, uint level)
        if (isScalarType!T && !isBigSignedType!T && !isBigUnsignedType!T && !is(T == enum))
{
    return T.sizeof + 1;
}

///////////////////////////////////////////////////////////
// variant
// type           size
//  5 (4)    -         
//  6 (8)     -
//    data
///////////////////////////////////////////////////////////
byte[] Serialize(T)(T t, RefClass stack, uint level)
        if (isBigSignedType!T || isBigUnsignedType!T)
{
    byte[] data = toVariant!T(t);
    long index;
    byte[1] h;
    h[0] = (T.sizeof == 4) ? 5 : 8;
    return h ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (isBigSignedType!T || isBigUnsignedType!T)
{
    assert((T.sizeof == 4 ? 5 : 8) == data[0]);
    long index;
    T t = toT!T(data[1 .. $], index);
    parse_index = index + 1;
    return t;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (isBigSignedType!T)
{
    return getbytenums(abs(t)) + 1;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (isBigUnsignedType!T)
{
    return getbytenum(abs(t)) + 1;
}

// TString
// 1 type 7
// [uint] variant 
//  data

byte[] Serialize(T)(T str, RefClass stack, uint level) if (is(T == string))
{
    byte[] data;
    uint len = cast(uint) str.length;
    byte[] dlen = toVariant(len);
    data.length = 1 + dlen.length + len;

    data[0] = 7;
    memcpy(data.ptr + 1, dlen.ptr, dlen.length);
    memcpy(data.ptr + 1 + dlen.length, str.ptr, len);
    return data;
}

string Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (is(T == string))
{
    assert(data[0] == 7);
    long index;
    uint len = toT!uint(data[1 .. $], index);
    parse_index += 1 + index + len;
    return cast(T)(data[cast(size_t)(1 + index) .. cast(size_t) parse_index].dup);
}

size_t getsize(T)(T str, RefClass stack, uint level) if (is(T == string))
{
    uint len = cast(uint) str.length;
    return cast(size_t)(1 + toVariant(len).length + str.length);
}

// TUnion            don't support TUnion
// 1 type 6
// 1 len 
//      data

/*
byte[] Serialize(T)(T t) if(is(T == union))
{
    byte[] data;
    data.length = T.sizeof + 2;
    data[0] = 5;
    data[1] = T.sizeof;
    memcpy(data.ptr + 2 , &t , T.sizeof);
    return data;
}
T Unserialize(T)(const byte[] data ) if(is(T == union))
{
    long parser_index;
    return unserialize!T(data , parser_index);
}
T Unserialize(T)(const byte[] data , out long parse_index) if(is(T == union))
{
    assert(data[0] == 5);
    
    T value;
    byte len;
    memcpy(&len , data.ptr + 1 , 1);
    parse_index = 2 + len;
    memcpy(&value , data.ptr + 2 , len);
    return value;
}
size_t getsize(T)(T t) if(is(T == union))
{
    return 2 + T.sizeof;
}
*/

// TSArray
// 1 type 8
// size[uint] variant
// len[uint] variant
// data

byte[] Serialize(T)(T t, RefClass stack, uint level) if (isStaticArray!T)
{
    byte[1] header;
    header[0] = 8;
    uint uSize = cast(uint) t.length;
    byte[] dh = cast(byte[]) header;
    dh ~= toVariant(uSize);

    byte[] data;
    for (size_t i = 0; i < uSize; i++)
    {
        data ~= Serialize(t[i], stack, level + 1);
    }
    uint len = cast(uint) data.length;
    dh ~= toVariant(len);
    return dh ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (isStaticArray!T)
{
    assert(data[0] == 8);
    T value;
    uint uSize;
    uint len;
    long index1;
    long index2;
    uSize = toT!uint(data[1 .. $], index1);

    len = toT!uint(data[cast(size_t)(index1 + 1) .. $], index2);
    parse_index += 1 + index1 + index2;

    long index = parse_index;
    long parse = 0;
    for (size_t i = 0; i < uSize; i++)
    {
        parse = 0;
        value[i] = unserialize!(typeof(value[0]))(data[cast(size_t) index .. data.length],
                parse, stack);
        index += parse;
    }

    parse_index += len;

    return value;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (isStaticArray!T)
{
    long total = 1;
    total += getbytenum(t.length);
    uint uSize = cast(uint) t.length;
    for (size_t i = 0; i < uSize; i++)
    {
        total += getsize(t[i], stack, level + 1);
    }
    total += getbytenum(total);
    return total;
}

//  TDArray
// 1  type 9
// size[uint]    variant
// length[uint]    variant
// data

byte[] Serialize(T)(T t, RefClass stack, uint level)
        if (isDynamicArray!T && !is(T == string) && !is(T == enum))
{
    byte[1] header;
    header[0] = 9;

    uint uSize = cast(uint) t.length;
    byte[] dh = cast(byte[]) header;
    dh ~= toVariant(uSize);

    byte[] data;
    for (size_t i = 0; i < uSize; i++)
    {
        data ~= Serialize(t[i], stack, level + 1);
    }
    uint len = cast(uint) data.length;
    dh ~= toVariant(len);

    return dh ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (isDynamicArray!T && !is(T == string) && !is(T == enum))
{
    assert(data[0] == 9);

    T value;
    uint uSize;
    uint len;
    long index1;
    long index2;
    uSize = toT!uint(data[1 .. $], index1);
    len = toT!uint(data[cast(size_t)(1 + index1) .. $], index2);

    parse_index += 1 + index1 + index2;
    value.length = uSize;
    ulong index = parse_index;
    long parse = 0;
    for (size_t i = 0; i < uSize; i++)
    {
        value[i] = unserialize!(typeof(value[0]))(data[cast(size_t) index .. data.length],
                parse, stack);
        index += parse;
    }
    parse_index += len;

    return value;
}

size_t getsize(T)(T t, RefClass stack, uint level)
        if (isDynamicArray!T && !is(T == string) && !is(T == enum) )
{
    long total = 1;
    total += getbytenum(t.length);
    uint uSize = cast(uint) t.length;
    for (size_t i = 0; i < uSize; i++)
    {
        total += getsize(t[i], stack, level + 1);
    }
    total += getbytenum(total);
    return total;
}

// TStruct
// 1 type 10
// [uint] variant
// data

byte[] Serialize(T)(T t, RefClass stack, uint level) if (is(T == struct))
{
    byte[1] header;
    header[0] = 10;
    byte[] data;

    mixin(serializeMembers!T());
    byte[] dh = cast(byte[]) header;
    uint len = cast(uint) data.length;
    dh ~= toVariant(len);
    return dh ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (is(T == struct))
{
    assert(data[0] == 10);

    T t;
    long index1;
    uint len = toT!uint(data[1 .. $], index1);

    parse_index = 1 + index1 + len;
    long index = 1 + index1;
    long parse = 0; 
    mixin(unserializeMembers!T());

    return t;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (is(T == struct))
{
    long total = 1;

    mixin(getsizeMembers!T());

    total += getbytenum(total);
    return cast(uint) total;
}

// TClass 
// 1 type 11
// [uint] len variant
//    data

// TClass ref
// 1 type 12
// id variant

byte[] Serialize(T, bool isRecursive=true)(T t, RefClass stack, uint level) if (is(T == class))
{
    byte[1] header;
    size_t* id = null;

    if (t !is null)
    {
        id = t.toHash() in stack.map;
    }

    if (id == null)
    {
        header[0] = 11;
        byte[] data;
        byte[] dh = cast(byte[]) header;
        if (t !is null)
        {
            stack.map[t.toHash()] = stack.map.length;
            static if(isRecursive) {
                static foreach(S; BaseClassesTuple!(T)) {
                    mixin(serializeMembers!S());
                }
            }
            mixin(serializeMembers!T());
        }
        uint len = cast(uint) data.length;
        dh ~= toVariant(len);

        return dh ~ data;
    }
    else
    {
        header[0] = 12;
        byte[] dh = cast(byte[]) header;
        dh ~= toVariant(*id);
        return dh;
    }

}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (is(T == class) && !isAbstractClass!T)
{
    if(data.length < 2)
        return T.init;
        
    assert(data[0] == 11 || data[0] == 12);

    if (data[0] == 11)
    {
        long index1;
        uint len = toT!uint(data[1 .. $], index1);
        if (len == 0)
            return null;
        T t = new T;
        parse_index = index1 + 1 + len;
        long index = index1 + 1;
        stack.arr ~= cast(void*) t;

        long parse = 0; 

        static foreach(S; BaseClassesTuple!(T)) {
            mixin(unserializeMembers!S());
        }
        mixin(unserializeMembers!T());

        return t;
    }
    else
    {
        long index1;
        size_t id = toT!size_t(data[1 .. $], index1);
        parse_index += index1 + 1;
        return cast(T) stack.arr[id];
    }

}

size_t getsize(T)(T t, RefClass stack, uint level) if (is(T == class))
{
    long total = 1;

    size_t* id = null;

    if (t !is null)
    {
        id = t.toHash() in stack.map;
    }

    if (id == null)
    {
        if (t !is null)
        {
            stack.map[t.toHash()] = stack.map.length;
            mixin(getsizeMembers!T());
        }

        total += getbytenum(total - 1);
        return total;
    }
    else
    {
        return getbytenum(*id) + 1;
    }

}

// AssociativeArray
// 1 type 13
// [uint] len variant
// (k,v)

byte[] Serialize(T)(T t, RefClass stack, uint level) if (isAssociativeArray!T)
{
    byte[1] header;
    header[0] = 13;
    byte[] dh;
    dh ~= cast(byte[]) header;
    byte[] data;
    foreach (k, v; t)
    {
        data ~= Serialize(k, stack, level + 1);
        data ~= Serialize(v, stack, level + 1);
    }
    uint len = cast(uint) data.length;
    dh ~= toVariant(len);
    return dh ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (isAssociativeArray!T)
{
    assert(data[0] == 13);

    T t;
    long index1;
    uint len = toT!uint(data[1 .. $], index1);

    parse_index = index1 + 1 + len;
    long index = index1 + 1;
    while (index < parse_index)
    {
        long out_len;
        auto k = unserialize!(KeyType!T)(data[index .. $], out_len, stack);
        index += out_len;
        out_len = 0;
        auto v = unserialize!(ValueType!T)(data[index .. $], out_len, stack);
        index += out_len;
        t[k] = v;
    }
    return t;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (isAssociativeArray!T)
{
    long total = 1;
    foreach (k, v; t)
    {
        total += Serialize(k).length;
        total += Serialize(v).length;
    }
    total += getbytenum(total - 1);
    return total;
}

// named enum
// 1 type 14
// 2 [uint] len 
// 3 other
byte[] Serialize(T)(T t, RefClass stack, uint level) if (is(T == enum))
{
    byte[1] header;
    header[0] = 14;
    byte[] dh;
    dh ~= cast(byte[]) header;
    OriginalType!T v = cast(OriginalType!T)t;
    byte[] data =  Serialize(v);
    uint len = cast(uint)data.length;
    dh ~= toVariant(len);
    return dh ~ data;
}

T Unserialize(T)(const byte[] data, out long parse_index, RefClass stack)
        if (is(T == enum))
{
    assert(data[0] == 14);

    T t;
    long index1;
    uint len = toT!uint(data[1 .. $], index1);

    parse_index = index1 + 1 + len;
    long index = index1 + 1;
    while (index < parse_index)
    {
        long out_len = 0;
        t = cast(T)unserialize!(OriginalType!T)(data[index .. $], out_len, stack);
        index += out_len;
    }
    return t;
}

size_t getsize(T)(T t, RefClass stack, uint level) if (is(T == enum))
{
    long total = 1;
    
    total += Serialize(cast(OriginalType!T)t).length;
    
    total += getbytenum(total - 1);
    return total;
}



public:

T Unserialize(T)(const(ubyte)[] data ) {
    return unserialize!(T)(cast(const byte[])data);
}

T Unserialize(T)(const byte[] data )
{
    long parse_index;
    return unserialize!T(data, parse_index);
}

T Unserialize(T)(const(ubyte)[] data, out long parse_index ) {
    return unserialize!(T)(cast(const byte[])data, parse_index);
}

T Unserialize(T)(const byte[] data, out long parse_index )
{
    RefClass stack = new RefClass();
    return unserialize!T(data, parse_index, stack);
}

byte[] Serialize(T)(T t ) if (!is(T == class))
{
    RefClass stack = new RefClass();
    return serialize!T(t, stack, 0);
}

byte[] Serialize(T, bool isRecursive=true)(T t ) if (is(T == class))
{
    RefClass stack = new RefClass();
    return serialize!(T, isRecursive)(t, stack, 0);
}

size_t getsize(T)(T t )
{
    RefClass stack = new RefClass();
    return getsize!T(t, stack, 0);
}

//////////////////////////////////////////////////////////////////json///////////////////////////
private:
enum bool isFloatType(T) = isType!(T, float) || isType!(T, double);

JSONValue toJson(T)(T t, RefClass stack, uint level)
        if (isSignedType!T || isUnsignedType!T || is(T == string) || is(T == bool) || isFloatType!T)
{
    return JSONValue(t);
}

// uinteger
T toObject(T)(JSONValue v, RefClass stack) if (isUnsignedType!T)
{
    if(v.type() == JSONType.uinteger)
        return cast(T) v.uinteger;
    else
        return T.init;
}

// integer
T toObject(T)(JSONValue v, RefClass stack) if (isSignedType!T)
{
    if(v.type() == JSONType.integer)
        return cast(T) v.integer;
    else
        return T.init;
}

// string
T toObject(T)(JSONValue v, RefClass stack) if (is(T == string))
{
    if(v.type() == JSONType.string)
        return v.str;
    else
        return T.init;
}

// bool
T toObject(T)(JSONValue v, RefClass stack) if (is(T == bool))
{
    if(v.type() == JSONType.true_ || v.type() == JSONType.false_)
        return v.type() == JSONType.true_;
    else
        return T.init;
}

// floating
T toObject(T)(JSONValue v, RefClass stack) if (isFloatType!T)
{
    if(v.type() == JSONType.float_)
        return cast(T) v.floating;
    else
        return  T.init;
}


// array
JSONValue toJson(T)(T t, RefClass stack, uint level)
        if (isStaticArray!T || (isDynamicArray!T && !is(T == string) && !is(T == enum)))
{
    JSONValue[] j;
    foreach (e; t)
    {
        j ~= toJson(e, stack, level);
    }

    return JSONValue(j);
}

T toObject(T)(JSONValue v, RefClass stack) if (isStaticArray!T)
{
    T t;
    if(v.type() == JSONType.array)
    {
        for (size_t i = 0; i < t.length; i++)
        {
            t[i] = toObject!(typeof(t[i]))(v.array[i], stack);
        }
    }
    return t;
    
}

T toObject(T)(JSONValue v, RefClass stack) if (isDynamicArray!T && !is(T == string)&& !is(T == enum))
{
    T t;
    if(v.type() == JSONType.array)
    {
        t.length = v.array.length;
        for (size_t i = 0; i < t.length; i++)
        {
            t[i] = toObject!(typeof(t[i]))(v.array[i], stack);
        }
    }
    return t;
}

// struct & class

string toJsonMembers(T , bool ignore)()
{
    string str;
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {
            if(!ignore || !hasUDA!(__traits(getMember , T , m) ,IGNORE ))
            {
                str ~= "j[\"" ~ m ~ "\"] = toJson(t." ~ m ~ " , stack , level + 1);";
            }    
        }
    }
    return str;
}

string toJsonMembersAll(T)()
{
    string str;
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {        
            str ~= "j[\"" ~ m ~ "\"] = toJson(t." ~ m ~ " , stack , level + 1);";
        }
    }
    return str;
}



string toObjectMembers(T)()
{
    string str;
    foreach (m; FieldNameTuple!T)
    {
        static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
        {
            str ~= " if ( \"" ~ m ~ "\"  in j )";
            str ~= "t." ~ m ~ " = toObject!(typeof(t." ~ m ~ "))(j[\"" ~ m ~ "\"] , stack);";
        }

    }
    return str;
}

JSONValue toJson(T)(T t, RefClass stack, uint level) if (is(T == struct))
{
    JSONValue j;

    static if (is(T == JSONValue))
    {
        return t;
    }
    else{
        bool ignore = (stack.unIgnore is null)? stack.ignore :(stack.unIgnore.ignore!T);

        if(ignore)
            mixin(toJsonMembers!(T,true));
        else
            mixin(toJsonMembers!(T,false));
        return j;
    }
}

T toObject(T)(JSONValue j, RefClass stack) if (is(T == struct))
{
    static if (is(T == JSONValue))
    {
        return j;
    }
    else
    {
        T t;
        if(j.type() == JSONType.object)
        {
            mixin(toObjectMembers!T);
        }
        return t;
    }
}

JSONValue toJson(T)(T t, RefClass stack, uint level) if (is(T == class))
{
    if (t is null || level >= stack.level)
    {
        return JSONValue(null);
    }

    auto id = t.toHash() in stack.map;
    if (id == null)
    {
        stack.map[t.toHash()] = stack.map.length;
        JSONValue j;
        bool ignore = (stack.unIgnore is null)? stack.ignore :(stack.unIgnore.ignore!T);

        if(ignore)
            mixin(toJsonMembers!(T,true));
        else
            mixin(toJsonMembers!(T,false));
        return j;
    }
    else
    {
        JSONValue j;
        j[MAGIC_KEY] = *id;
        return j;
    }
}

T toObject(T)(JSONValue j, RefClass stack) if (is(T == class))
{
    if ( j.type() != JSONType.object)
        return T.init;
    assert(j.type() == JSONType.object);

    if (MAGIC_KEY in j)
    {
        return cast(T) stack.arr[j[MAGIC_KEY].uinteger];
    }
    else
    {
        T t = new T;
        stack.arr ~= cast(void*) t;
        mixin(toObjectMembers!T);
        return t;
    }
}

//AssociativeArray
JSONValue toJson(T)(T t, RefClass stack, uint level) if (isAssociativeArray!T)
{
    JSONValue j;
    import std.conv;

    foreach (k, v; t)
        j[to!string(k)] = toJson(v, stack, level);
    return j;
}

T toObject(T)(JSONValue j, RefClass stack) if (isAssociativeArray!T)
{
    import std.conv;
    if ( j.type() != JSONType.object)
        return T.init;
    T t;
    foreach (k, v; j.object)
    {
        t[to!(KeyType!T)(k)] = toObject!(ValueType!T)(v, stack);
    }
    return t;
}

//enum
JSONValue toJson(T)(T t, RefClass stack, uint level) if (is(T == enum))
{
    
    auto j =  JSONValue(cast(OriginalType!T)t);
    writeln(j.type());
    return j;
}

T toObject(T)(JSONValue j, RefClass stack) if (is(T == enum))
{
    import std.conv;
    writeln(j , " " , j.type() , typeid(T));
    OriginalType!T val;
    static if (is(OriginalType!T == string ))
    {
        if(j.type() == JSONType.string)
            val = cast(OriginalType!T)j.str;
        else
            return T.init;
    }
    else static if (is(OriginalType!T == int))
    {
        if(j.type() == JSONType.integer)
            val = cast(OriginalType!T)j.integer;
        else if(j.type() == JSONType.uinteger)
            val = cast(OriginalType!T)j.uinteger;
        else
            return T.init;
    }

    return cast(T)val;    
}

public:

JSONValue toJson(T)(T t , uint level = uint.max , bool ignore = true)
{
    RefClass stack = new RefClass();
    stack.level = level;
    stack.ignore = ignore;
    return toJson!T(t, stack, 0);
}

JSONValue toJson(T)(T t   , UnIgnoreArray array  ,  uint level = uint.max)
{
    RefClass stack = new RefClass();
    stack.level = level;
    stack.unIgnore = array;
    return toJson!T(t, stack, 0);
}

T toObject(T)(JSONValue j)
{
    RefClass stack = new RefClass();
    return toObject!T(j, stack);
}

deprecated("Use toJson instead.")
alias toJSON = toJson;

deprecated("Using toObject instead.")
alias toOBJ = toObject;

/// toTextString
/**
Takes a tree of JSON values and returns the serialized string.

Any Object types will be serialized in a key-sorted order.

If `pretty` is false no whitespaces are generated.
If `pretty` is true serialized string is formatted to be human-readable.
Set the $(LREF JSONOptions.specialFloatLiterals) flag is set in `options` to encode NaN/Infinity as strings.
*/
string toTextString(const ref JSONValue root, in bool pretty = false, in JSONOptions options = JSONOptions.none) @safe
{
    import std.array;
    import std.conv;
    import std.string;

    auto json = appender!string();

    void toStringImpl(Char)(string str) @safe
    {
        json.put('"');

        foreach (Char c; str)
        {
            switch (c)
            {
                case '"':       json.put("\\\"");       break;
                case '\\':      json.put("\\\\");       break;

                case '/':
                    if (!(options & JSONOptions.doNotEscapeSlashes))
                        json.put('\\');
                    json.put('/');
                    break;

                case '\b':      json.put("\\b");        break;
                case '\f':      json.put("\\f");        break;
                case '\n':      json.put("\\n");        break;
                case '\r':      json.put("\\r");        break;
                case '\t':      json.put("\\t");        break;
                default:
                {
                    import std.ascii : isControl;
                    import std.utf : encode;

                    // Make sure we do UTF decoding iff we want to
                    // escape Unicode characters.
                    assert(((options & JSONOptions.escapeNonAsciiChars) != 0)
                        == is(Char == dchar), "JSONOptions.escapeNonAsciiChars needs dchar strings");

                    with (JSONOptions) if (isControl(c) ||
                        ((options & escapeNonAsciiChars) >= escapeNonAsciiChars && c >= 0x80))
                    {
                        // Ensure non-BMP characters are encoded as a pair
                        // of UTF-16 surrogate characters, as per RFC 4627.
                        wchar[2] wchars; // 1 or 2 UTF-16 code units
                        size_t wNum = encode(wchars, c); // number of UTF-16 code units
                        foreach (wc; wchars[0 .. wNum])
                        {
                            json.put("\\u");
                            foreach_reverse (i; 0 .. 4)
                            {
                                char ch = (wc >>> (4 * i)) & 0x0f;
                                ch += ch < 10 ? '0' : 'A' - 10;
                                json.put(ch);
                            }
                        }
                    }
                    else
                    {
                        json.put(c);
                    }
                }
            }
        }

        json.put('"');
    }

    void toString(string str) @safe
    {
        // Avoid UTF decoding when possible, as it is unnecessary when
        // processing JSON.
        if (options & JSONOptions.escapeNonAsciiChars)
            toStringImpl!dchar(str);
        else
            toStringImpl!char(str);
    }

    void toValue(ref const JSONValue value, ulong indentLevel) @safe
    {
        void putTabs(ulong additionalIndent = 0)
        {
            if (pretty)
                foreach (i; 0 .. indentLevel + additionalIndent)
                    json.put("    ");
        }
        void putEOL()
        {
            if (pretty)
                json.put('\n');
        }
        void putCharAndEOL(char ch)
        {
            json.put(ch);
            putEOL();
        }

        final switch (value.type)
        {
            case JSONType.object:
                auto obj = value.objectNoRef;
                if (!obj.length)
                {
                    json.put("{}");
                }
                else
                {
                    putCharAndEOL('{');
                    bool first = true;

                    void emit(R)(R names)
                    {
                        foreach (name; names)
                        {
                            auto member = obj[name];
                            if (!first)
                                putCharAndEOL(',');
                            first = false;
                            putTabs(1);
                            toString(name);
                            json.put(':');
                            if (pretty)
                                json.put(' ');
                            toValue(member, indentLevel + 1);
                        }
                    }

                    import std.algorithm.sorting : sort;
                    // @@@BUG@@@ 14439
                    // auto names = obj.keys;  // aa.keys can't be called in @safe code
                    auto names = new string[obj.length];
                    size_t i = 0;
                    foreach (k, v; obj)
                    {
                        names[i] = k;
                        i++;
                    }
                    sort(names);
                    emit(names);

                    putEOL();
                    putTabs();
                    json.put('}');
                }
                break;

            case JSONType.array:
                auto arr = value.arrayNoRef;
                if (arr.empty)
                {
                    json.put("[]");
                }
                else
                {
                    putCharAndEOL('[');
                    foreach (i, el; arr)
                    {
                        if (i)
                            putCharAndEOL(',');
                        putTabs(1);
                        toValue(el, indentLevel + 1);
                    }
                    putEOL();
                    putTabs();
                    json.put(']');
                }
                break;

            case JSONType.string:
                toString(value.str);
                break;

            case JSONType.integer:
                json.put(to!string(value.integer));
                break;

            case JSONType.uinteger:
                json.put(to!string(value.uinteger));
                break;

            case JSONType.float_:
                import std.math : isNaN, isInfinity;

                auto val = value.floating;

                if (val.isNaN)
                {
                    if (options & JSONOptions.specialFloatLiterals)
                    {
                        toString(JSONFloatLiteral.nan);
                    }
                    else
                    {
                        throw new JSONException(
                            "Cannot encode NaN. Consider passing the specialFloatLiterals flag.");
                    }
                }
                else if (val.isInfinity)
                {
                    if (options & JSONOptions.specialFloatLiterals)
                    {
                        toString((val > 0) ?  JSONFloatLiteral.inf : JSONFloatLiteral.negativeInf);
                    }
                    else
                    {
                        throw new JSONException(
                            "Cannot encode Infinity. Consider passing the specialFloatLiterals flag.");
                    }
                }
                else
                {
                    import std.format : format;
                    // The correct formula for the number of decimal digits needed for lossless round
                    // trips is actually:
                    //     ceil(Log(pow(2.0, double.mant_dig - 1)) / Log(10.0) + 1) == (double.dig + 2)
                    // Anything less will round off (1 + double.epsilon)
                    json.put("%s".format(val));
                }
                break;

            case JSONType.true_:
                json.put("true");
                break;

            case JSONType.false_:
                json.put("false");
                break;

            case JSONType.null_:
                json.put("null");
                break;
        }
    }

    toValue(root, 0);
    return json.data;
}


/**
*/
mixin template SerializationMember(T) {
    import std.traits;
    debug(GEAR_DEBUG_MORE) import geario.logging;

    alias baseClasses = BaseClassesTuple!T;

    static if(baseClasses.length == 1 && is(baseClasses[0] == Object)) {
        ubyte[] Serialize() {
            ubyte[] bytes = cast(ubyte[]).serialize!(T, false)(this);
            debug(GEAR_DEBUG_MORE) 
                log.trace("this level (%s), length: %d, data: %(%02X %)", T.stringof, bytes.length, bytes);
            return bytes;
        }
        
        // void deserialize(ubyte[] data) {

        // }
    } else {
        // pragma(msg, T.stringof);
        override ubyte[] Serialize() {
            auto bytes = cast(ubyte[])geario.util.Serialize.serialize!(T, false)(this);
            debug(GEAR_DEBUG_MORE) 
                log.trace("current level (%s), length: %d, data: %(%02X %)", T.stringof, bytes.length, bytes);
            
            ubyte[] data = super.Serialize();
            data[1] = cast(ubyte)(data[1] + bytes.length - 2);
            data ~= bytes[2..$];
            debug(GEAR_DEBUG_MORE) 
                log.trace("all levels (%s), length: %d, data: %(%02X %)", T.stringof, data.length, data);

            // auto bytes = cast(ubyte[])geario.util.Serialize.Serialize(this);
            // log.trace("length: %d, data: %(%02X %)", bytes.length, bytes);
            return data;
        }    

        // override void deserialize(ubyte[] data) {

        // }
    }


}


// only for , nested , new T
/*
version (unittest)
{
    //test struct
        void test1(T)(T t)
        {
            assert(unserialize!T(Serialize(t)) == t);
            assert(Serialize(t).length == getsize(t));
            assert(toObject!T(toJson(t)) == t);
        }
        struct T1
        {
            bool b;
            byte ib;
            ubyte ub;
            short ish;
            ushort ush;
            int ii;
            uint ui;
            long il;
            ulong ul;
            string s;
            uint[10] sa;
            long[] sb;
        }
        struct T2
        {
            string n;
            T1[] t;
        }
        struct T3
        {
            T1 t1;
            T2 t2;
            string[] name;
        }
        //test class
        class C
        {
            int age;
            string name;
            T3 t3;
            override bool opEquals(Object c)
            {
                auto c1 = cast(C) c;
                return age == c1.age && name == c1.name && t3 == c1.t3;
            }
            C clone()
            {
                auto c = new C();
                c.age = age;
                c.name = name;
                c.t3 = t3;
                return c;
            }
        }
        class C2
        {
            C[] c;
            C c1;
            T1 t1;
            override bool opEquals(Object c)
            {
                auto c2 = cast(C2) c;
                return this.c == c2.c && c1 == c2.c1 && t1 == c2.t1;
            }
        }
        //ref test
        class School
        {
            string name;
            User[] users;
            override bool opEquals(Object c)
            {
                auto school = cast(School) c;
                return school.name == this.name;
            }
        }
        class User
        {
            int age;
            string name;
            School school;
            override bool opEquals(Object c)
            {
                auto user = cast(User) c;
                return user.age == this.age && user.name == this.name && user.school == this.school;
            }
        }
        struct J{
            string data;
            JSONValue val;
        
        }

        enum MONTH
        {
            M1,
            M2
        }

        enum WEEK : int
        {
            K1 = 1,
            K2 = 2
        }

        enum DAY : string
        {
            D1 = "one",
            D2 = "two"
        }

        class Date1
        {
            MONTH month;
            WEEK week;
            DAY day;
            override bool opEquals(Object c)
            {
                auto date = cast(Date1) c;
                return date.month == this.month && date.week == this.week && date.day == this.day;
            }

        }

        void test_enum_ser()
        {
            Date1 date = new Date1();
            date.month = MONTH.M2;
            date.week = WEEK.K2;
            date.day = DAY.D2;
            test1(date);
            
        }

        void test_json_ser()
        {
            J j;
            j.data = "test";
            j.val = "FUC";
            toObject!J(toJson(j));
        }
        void test_ref_class()
        {
            School school = new School();
            User user1 = new User();
            user1.age = 30;
            user1.name = "zhangyuchun";
            user1.school = school;
            User user2 = new User();
            user2.age = 31;
            user2.name = "wulishan";
            user2.school = school;
            school.name = "putao";
            school.users ~= user1;
            school.users ~= user2;
            test1(user1);
            test1(user2);
        }
        void test_struct_class_array()
        {
            T1 t;
            t.b = true;
            t.ib = -11;
            t.ub = 128 + 50;
            t.ish = -50;
            t.ush = (1 << 15) + 50;
            t.ii = -50;
            t.ui = (1 << 31) + 50;
            t.il = (cast(long) 1 << 63) - 50;
            t.ul = (cast(long) 1 << 63) + 50;
            t.s = "test";
            t.sa[0] = 10;
            t.sa[1] = 100;
            t.sb ~= 10;
            t.sb ~= 100;
            test1(t);
            T2 t2;
            t2.t ~= t;
            t2.t ~= t;
            t2.n = "testt2";
            test1(t2);
            T3 t3;
            t3.t1 = t;
            t3.t2 = t2;
            t3.name ~= "123";
            t3.name ~= "456";
            test1(t3);
            C c1 = new C();
            c1.age = 100;
            c1.name = "test";
            c1.t3 = t3;
            test1(c1);
            C2 c2 = new C2();
            c2.c ~= c1;
            c2.c ~= c1.clone();
            c2.c1 = c1.clone();
            c2.t1 = t;
            test1(c2);
            C2 c3 = null;
            test1(c3);
            string[string] map1 = ["1" : "1", "2" : "2"];
            string[int] map2 = [1 : "1", 2 : "2"];
            T1[string] map3;
            T1 a1;
            a1.ib = 1;
            T1 a2;
            a2.ib = 2;
            map3["1"] = a1;
            map3["2"] = a2;
            test1(map1);
            test1(map2);
            test1(map3);
        }
    
}
unittest
{
    import std.stdio;
    long index;
    void test(T)(T v)
    {
        long index;
        byte[] bs = toVariant(v);
        long length = bs.length;
        bs ~= ['x', 'y'];
        assert(toT!T(bs, index) == v && index == length);
        assert(toObject!T(toJson(v)) == v);
    }
    //test variant
    //unsigned
    {
        ubyte j0 = 0;
        ubyte j1 = 50;
        ubyte j2 = (1 << 7) + 50;
        ubyte j3 = 0xFF;
        ushort j4 = (1 << 14) + 50;
        ushort j5 = 0xFFFF;
        uint j6 = (1 << 21) + 50;
        uint j7 = (1 << 28) + 50;
        uint j8 = 128;
        uint j9 = 0xFFFFFFFF;
        {
        }
        ulong j10 = (cast(ulong) 1 << 35) + 50;
        ulong j11 = (cast(ulong) 1 << 42) + 50;
        ulong j12 = (cast(ulong) 1 << 49) + 50;
        ulong j13 = (cast(ulong) 1 << 56) + 50;
        ulong j14 = j9 + j10 + j11 + j12;
        ulong j15 = 0xFFFFFFFFFFFFFFFF;
        test(j0);
        test(j1);
        test(j2);
        test(j3);
        test(j4);
        test(j5);
        test(j6);
        test(j7);
        test(j8);
        test(j9);
        test(j10);
        test(j11);
        test(j12);
        test(j13);
        test(j14);
        test(j15);
    }
    //signed
    {
        byte i0 = 0;
        byte i1 = (1 << 6) + 50;
        byte i2 = (1 << 7) - 1;
        byte i3 = -i2;
        byte i4 = -i1;
        test(i0);
        test(i1);
        test(i2);
        test(i3);
        test(i4);
        short i5 = (1 << 7) + 50;
        short i6 = (1 << 14) + 50;
        short i7 = -i5;
        short i8 = -i6;
        test(i5);
        test(i6);
        test(i7);
        test(i8);
        int i9 = (1 << 16) + 50;
        int i10 = (1 << 25) + 50;
        int i11 = (1 << 30) + 50;
        int i12 = 64;
        int i13 = -i10;
        int i14 = -i11;
        int i15 = i9 + i10 + i11;
        int i16 = -i15;
        test(i9);
        test(i10);
        test(i11);
        test(i12);
        test(i13);
        test(i14);
        test(i15);
        test(i16);
        long i17 = (cast(long) 1 << 32) + 50;
        long i18 = (cast(long) 1 << 48) + 50;
        long i19 = (cast(long) 1 << 63) + 50;
        long i20 = i17 + i18 + i19;
        long i21 = -i17;
        long i22 = -i20;
        test(i17);
        test(i18);
        test(i19);
        test(i20);
        test(i21);
        test(i22);
        int i23 = -11;
        test(i23);
    }
    //test serialize
    //basic: byte ubyte short ushort int uint long ulong
    {
        byte b1 = 123;
        byte b2 = -11;
        ubyte b3 = 233;
        short s1 = -11;
        short s2 = (1 << 8) + 50;
        short s3 = (1 << 15) - 50;
        ushort s4 = (1 << 16) - 50;
        int i1 = -11;
        int i2 = (1 << 16) + 50;
        int i3 = (1 << 31) - 50;
        uint i4 = (1 << 31) + 50;
        long l1 = -11;
        long l2 = (cast(long) 1 << 32) + 50;
        long l3 = (cast(long) 1 << 63) - 50;
        ulong l4 = (cast(long) 1 << 63) + 50;
        test1(b1);
        test1(b2);
        test1(b3);
        test1(s1);
        test1(s2);
        test1(s3);
        test1(s4);
        test1(i1);
        test1(i2);
        test1(i3);
        test1(i4);
        test1(l1);
        test1(l2);
        test1(l3);
        test1(l4);
    }
    //test string
    {
        string s1 = "";
        string s2 = "1";
        string s3 = "123";
        test1(s1);
        test1(s2);
        test1(s3);
    }
    //test static arrary
    {
        string[5] sa;
        sa[0] = "test0";
        sa[1] = "test1";
        sa[2] = "test2";
        sa[3] = "test3";
        sa[4] = "test4";
        test1(sa);
    }
    //test dynamic arrary
    {
        string[] sa;
        sa ~= "test1";
        sa ~= "test2";
        sa ~= "test3";
        sa ~= "test4";
        test1(sa);
        string[] sa2;
        test1(sa2);
    }
    //test enum \ struct \ class \ associative array
    test_enum_ser();
    test_struct_class_array();
    test_ref_class();
    test_json_ser();
    ////unsigned
        uint ut1 = 1 << 7;
        uint ut2 = 1 << 14;
        uint ut3 = 1 << 21;
        uint ut4 = 1 << 28;
//signed
        int it1 = 1 << 6;
        int it2 = 1 << 13;
        int it3 = 1 << 20;
        int it4 = 1 << 27;
        test1(ut1);
        test1(ut2);
        test1(ut3);
        test1(ut4);
        test1(it1);
        test1(it2);
        test1(it3);
        test1(it4);
}
*/
