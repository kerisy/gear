module geario.serialization.Specify;

import std.traits;
import std.range;

import geario.serialization.Common;
import geario.serialization.BinarySerializer;
import geario.serialization.BinaryDeserializer;

import geario.logging;

template PtrType(T) {
    static if (is(T == bool) || is(T == char)) {
        alias PtrType = ubyte*;
    } else static if (is(T == float)) {
        alias PtrType = uint*;
    } else static if (is(T == double)) {
        alias PtrType = ulong*;
    } else {
        alias PtrType = Unsigned!T*;
    }
}

enum ubyte[] NULL = ['n', 'u', 'l', 'l'];

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == wchar)) {
    specify!(options)(obj, *cast(ushort*)&val);
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == dchar)) {
    specify!(options)(obj, *cast(uint*)&val);
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == ushort)) {
    ubyte valh = (val >> 8);
    ubyte vall = val & 0xff;
    obj.PutUbyte(valh);
    obj.PutUbyte(vall);
    val = (valh << 8) + vall;
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == uint)) {
    ubyte val0 = (val >> 24);
    ubyte val1 = cast(ubyte)(val >> 16);
    ubyte val2 = cast(ubyte)(val >> 8);
    ubyte val3 = val & 0xff;
    obj.PutUbyte(val0);
    obj.PutUbyte(val1);
    obj.PutUbyte(val2);
    obj.PutUbyte(val3);
    val = (val0 << 24) + (val1 << 16) + (val2 << 8) + val3;
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == ulong)) {
    T newVal;
    for (int i = 0; i < T.sizeof; ++i) {
        immutable shiftBy = 64 - (i + 1) * T.sizeof;
        ubyte byteVal = (val >> shiftBy) & 0xff;
        obj.PutUbyte(byteVal);
        newVal |= (cast(T) byteVal << shiftBy);
    }
    val = newVal;
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (isStaticArray!T) {
    static if (is(Unqual!(ElementType!T) : ubyte) && T.sizeof == 1) {
        obj.PutRaw(cast(ubyte[]) val);
    } else {
        foreach (ref v; val) {
            specify!(options)(obj, v);
        }
    }
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == string)) {
    ushort len = cast(ushort) val.length;
    specify!(options)(obj, len);

    static if (is(C == BinarySerializer)) {
        obj.PutRaw(cast(ubyte[]) val);
    } else {
        val = cast(string) obj.Take(len).idup;
    }
}

void Specify(SerializationOptions options, U, C, T)(auto ref C obj, ref T val) if(is(T == string)) {
    U length = cast(U)val.length;
    assert(length == val.length, "overflow");
    specify!(options)(obj,length);

    static if(is(C == BinarySerializer))
        obj.PutRaw(cast(ubyte[])val);
    else
        val = cast(string) obj.PutRaw(length).idup;
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (isAssociativeArray!T) {
    ushort length = cast(ushort) val.length;
    specify!(options)(obj, length);
    const keys = val.keys;
    for (ushort i = 0; i < length; ++i) {
        KeyType!T k = keys.length ? keys[i] : KeyType!T.init;
        auto v = keys.length ? val[k] : ValueType!T.init;

        specify!(options)(obj, k);
        specify!(options)(obj, v);
        val[k] = v;
    }
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (isPointer!T) {
    alias ValueType = PointerTarget!T;
    specify!(options)(obj, *val);
}

//ubyte
void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == ubyte)) {
    obj.PutUbyte(val);
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val)
        if (!is(T == enum) && (isSigned!T || isBoolean!T || is(T == char) || isFloatingPoint!T)) {
    specifyPtr!(options)(obj, val);
}

//ENUM
void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == enum)) {
    specify!(options)(obj, cast(Unqual!(OriginalType!(T))) val);
}

void Specify(SerializationOptions options, C, T : E[], E)(auto ref C obj, ref T val)
        if (is(C == BinarySerializer) && isInputRange!T && !isInfinite!T
            && !is(T == string) && !isStaticArray!T && !isAssociativeArray!T) {
    enum hasLength = is(typeof(() { auto l = val.length; }));
    ushort length = cast(ushort) val.length;
    specify!(options)(obj, length);

    static if (hasSlicing!(Unqual!T) && is(Unqual!(ElementType!T) : ubyte) && T.sizeof == 1) {
        obj.PutRaw(cast(ubyte[]) val.array);
    } else {
        foreach (ref v; val) {
            specify!(options)(obj, v);
        }
    }
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val)
        if (isAggregateType!T && !isInputRange!T && !isOutputRange!(T, ubyte)) {
    
    debug(GEAR_DEBUG_MORE) log.trace("Setting: %s, value: %s", T.stringof, val);
    loopMembers!(options, C, T)(obj, val);
}

void Specify(SerializationOptions options, C, T)(auto ref C obj, ref T val)
        if (isDecerealiser!C && !isOutputRange!(T, ubyte) && isDynamicArray!T && !is(T == string)) {
    ushort length;

    specify!(options)(obj, length);
    decerealiseArrayImpl!(options)(obj, val, length);
}

void DecerealiseArrayImpl(SerializationOptions options, C, T : E[], E, U)(auto ref C obj, ref T val, U length)
        if (is(T == E[], E) && isDecerealiser!C) {

    ulong neededBytes(T)(ulong length) {
        alias E = ElementType!T;
        static if (isScalarType!E)
            return length * E.sizeof;
        else static if (isInputRange!E)
            return neededBytes!E(length);
        else
            return 0;
    }

    immutable needed = neededBytes!T(length);

    static if (is(Unqual!(ElementType!T) : ubyte) && T.sizeof == 1) {
        val = obj.PutRaw(length).dup;
    } else {
        if (val.length != length)
            val.length = cast(uint) length;

        foreach (ref e; val) {
            obj.specify!(options)(e);
        }
    }
}

void SpecifyPtr(SerializationOptions options, C, T)(auto ref C obj, ref T val) {
    auto ptr = cast(PtrType!T)(&val);
    specify!(options)(obj, *ptr);
}

void LoopMembers(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == struct)) {
    loopMembersImpl!(T, options)(obj, val);
}

void LoopMembers(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == class)) {

    debug(GEAR_DEBUG_MORE) log.trace("Setting: %s, value: %s", T.stringof, val);

    static if (is(C == BinarySerializer)) {
        if (val is null) {
            obj.PutRaw(NULL);
            return;
        }
        //assert(val !is null, "null value cannot be serialised");
    }

    static if (is(C == BinaryDeserializer)) {
        if (obj.isNullObj) {
            obj.Take(NULL.length);
            val = null;
            return;
        }
    }

    static if (is(typeof(() { val = new T; }))) {
        if (val is null)
            val = new T;
    } 

    obj.putClass!(options, T)(val);
}


void LoopMembersImpl(T, SerializationOptions options, C, VT)
        (auto ref C obj, ref VT val) {
    // foreach (member; __traits(derivedMembers, T)) {
    //     enum isMemberVariable = is(typeof(() {
    //                 __traits(getMember, val, member) = __traits(getMember, val, member).init;
    //             }));
    //     static if (isMemberVariable) {
    //         specifyAggregateMember!member(obj, val);
    //     }
    // }
    
        debug(GEAR_DEBUG_MORE) pragma(msg, "T=> " ~ T.stringof);
    static foreach (string member; FieldNameTuple!T) {
        debug(GEAR_DEBUG_MORE) pragma(msg, "Field member: " ~ member);
        static if(!member.empty())
        {{
            alias currentMember = __traits(getMember, T, member);
            alias memberType = typeof(currentMember);

            static if(hasUDA!(currentMember, Ignore)) {
                enum canDeserialize = false;
                version(GEAR_DEBUG) {
                    log.info("Ignore a member: %s %s", memberType.stringof, member);
                } 
            } else static if(options.OnlyPublic) {
                static if (__traits(getProtection, currentMember) == "public") {
                    enum canDeserialize = true;
                } else {
                    enum canDeserialize = false;
                }
            } else {
                enum canDeserialize = true;
            }

            static if(canDeserialize) {
                debug(GEAR_DEBUG_MORE) log.trace("name: %s", member);
                specify!(options)(obj, __traits(getMember, val, member));
                debug(GEAR_DEBUG_MORE) log.info("value: %s", __traits(getMember, val, member));
            }
        }}
    }    
}


// void specifyAggregateMember(string member, SerializationOptions options, C, T)(auto ref C obj, ref T val) {
//     import std.meta : staticIndexOf;

//     enum NoCereal;
//     enum noCerealIndex = staticIndexOf!(NoCereal, __traits(getAttributes,
//                 __traits(getMember, val, member)));
//     static if (noCerealIndex == -1) {
//         specifyMember!(member, options)(obj, val);
//     }
// }

// void specifyMember(string member, SerializationOptions options, C, T)(auto ref C obj, ref T val) {
//     // alias currentMember = __traits(getMember, val, member);
//     // static if(isAggregateType!(typeof(currentMember))) {
//     //     specify!(options)(obj, __traits(getMember, val, member));
//     // } else {
//     //     Specify(obj, __traits(getMember, val, member));
//     // }
//     debug(GEAR_DEBUG_MORE) log.trace("name: %s", member);
//     specify!(options)(obj, __traits(getMember, val, member));
//     debug(GEAR_DEBUG_MORE) log.info("value: %s", __traits(getMember, val, member));
// }

void SpecifyBaseClass(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == class)) {
    foreach (base; BaseTypeTuple!T) {
        loopMembersImpl!(base, options)(obj, val);
    }
}

void SpecifyClass(SerializationOptions options, C, T)(auto ref C obj, ref T val) if (is(T == class)) {
    static if(options.TraverseBase) {
        specifyBaseClass!(options)(obj, val);
    }
    loopMembersImpl!(T, options)(obj, val);
}

void CheckDecerealiser(T)() {
    //static assert(T.type == CerealType.ReadBytes);
    auto dec = T();
    ulong bl = dec.bytesLeft;
}

enum isDecerealiser(T) = (is(T == BinaryDeserializer) && is(typeof(checkDecerealiser!T)));
