/*
 * Gear - A cross-platform abstraction library with asynchronous I/O.
 *
 * Copyright (C) 2021-2022 Kerisy.com
 *
 * Website: https://www.kerisy.com
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module gear.serialization.JsonSerializer;

import gear.serialization.Common;
import gear.logging.ConsoleLogger;


import std.algorithm : map;
import std.array;
import std.conv;
import std.datetime;
import std.json;
import std.stdio;
import std.traits;


enum MetaTypeName = "__metatype__";

/* -------------------------------------------------------------------------- */
/*                                 Annotations                                */
/* -------------------------------------------------------------------------- */

// https://github.com/FasterXML/jackson-annotations
// http://tutorials.jenkov.com/java-json/jackson-annotations.html

enum JsonIgnore;

struct JsonProperty {
    string name;
}

/**
 * 
 */
interface JsonSerializable {

    JSONValue jsonSerialize();

    void jsonDeserialize(const(JSONValue) value);
}


/**
 * 
 */
final class JsonSerializer {

    static T GetItemAs(T, bool CanThrow = false)(ref const(JSONValue) json, string name, 
        T defaultValue = T.init) if (!is(T == void)) {
        if (json.type() != JSONType.object) {            
            return handleException!(T, CanThrow)(json, "wrong member type", defaultValue);
        }

        auto item = name in json;
        if (item is null) {            
            return handleException!(T, CanThrow)(json, "wrong member type", defaultValue);
        }
        else {
            return toObject!T(*item); // , defaultValue
        }
    }

    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (string json, T defaultValue = T.init) if (is(T == class)) {
        return toObject!(T, options)(parseJSON(json));
    }

    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (string json, T defaultValue = T.init) if (!is(T == class)) {
        return toObject!(T, options.TraverseBase(false))(parseJSON(json), defaultValue);
    }

    /**
     * Converts a `JSONValue` to an object of type `T` by filling its fields with the JSON's fields.
     */
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (auto ref const(JSONValue) json, T defaultValue = T.init) 
            if (is(T == class)) { // is(typeof(new T()))

        if(json.isNull())
            return defaultValue;

        if (json.type() != JSONType.object) {
            return handleException!(T, options.CanThrow())(json, "wrong object type", defaultValue);
        }

        static if(__traits(compiles, new T())) {
            auto result = new T();

            static if(is(T : JsonSerializable)) {
                result.jsonDeserialize(json);
            } else {
                try {
                    deserializeObject!(T, options)(result, json);
                } catch (JSONException e) {
                    return handleException!(T, options.CanThrow())(json, e.msg, defaultValue);
                }
            }
            return result;
        } else {
            Warningf("The %s does NOT define the default constructor. So a null will be returned.", typeid(T));
            return defaultValue;          
        }
    }
    

    /**
     * struct
     */
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)(
            auto ref const(JSONValue) json, T defaultValue = T.init) 
            if (is(T == struct) && !is(T == SysTime)) {

        if(json.isNull)
            return defaultValue;

        JSONType jt = json.type();
        if (jt != JSONType.object) {
            return handleException!(T, options.CanThrow())(json, "wrong object type", defaultValue);
        }

        auto result = T();

        try {
            static foreach (string member; FieldNameTuple!T) {
                deserializeMember!(member, options.TraverseBase(false))(result, json);
            }
        } catch (JSONException e) {
            return handleException!(T, options.CanThrow())(json, e.msg, defaultValue);
        }

        return result;
    }


    static void DeserializeObject(T, SerializationOptions options = SerializationOptions.Default)
            (ref T target, auto ref const(JSONValue) json)
         if(is(T == struct)) {
        enum SerializationOptions fixedOptions = options.TraverseBase(false);
        static foreach (string member; FieldNameTuple!T) {
            // current fields
            deserializeMember!(member, fixedOptions)(target, json);
        }
    }

    /**
     * 
     */
    static void DeserializeObject(T, SerializationOptions options = SerializationOptions.Default)
            (T target, auto ref const(JSONValue) json) if(is(T == class)) {

        static foreach (string member; FieldNameTuple!T) {
            // current fields
            deserializeMember!(member, options)(target, json);
        }

        // super fields
        static if(options.TraverseBase()) {
            alias baseClasses = BaseClassesTuple!T;
            alias BaseType = baseClasses[0];

            static if(baseClasses.length >= 1 && !is(BaseType == Object)) {
                debug(GEAR_DEBUG_MORE) {
                    Infof("TODO: deserializing fields in base %s for %s", BaseType.stringof, T.stringof);
                }
                auto jsonItemPtr = "super" in json;
                if(jsonItemPtr !is null) {
                    deserializeObject!(BaseType, options)(target, *jsonItemPtr);
                }
            }
        }
    }

    private static void DeserializeMember(string member, SerializationOptions options, T)
            (ref T target, auto ref const(JSONValue) json) {
        
        alias currentMember = __traits(getMember, T, member);
        alias memberType = typeof(currentMember);
        debug(GEAR_DEBUG_MORE) {
            Infof("deserializing member: %s %s", memberType.stringof, member);
        }

        static if(hasUDA!(currentMember, Ignore) || hasUDA!(currentMember, JsonIgnore)) {
            enum canDeserialize = false;
            version(GEAR_DEBUG) {
                Infof("Ignore a member: %s %s", memberType.stringof, member);
            } 
        } else static if(options.OnlyPublic) {
            static if (__traits(getProtection, currentMember) == "public") {
                enum canDeserialize = true;
            } else {
                enum canDeserialize = false;
            }
        } else static if(is(memberType == interface) && !is(memberType : JsonSerializable)) {
            enum canDeserialize = false;
            version(GEAR_DEBUG) Warning("skipped a interface member (not JsonSerializable): " ~ member);
        } else {
            enum canDeserialize = true;
        }

        static if(canDeserialize) {
            alias jsonPropertyUDAs = getUDAs!(currentMember, JsonProperty);
            static if(jsonPropertyUDAs.length > 0) {
                enum PropertyName = jsonPropertyUDAs[0].name;
                enum jsonKeyName = (PropertyName.length == 0) ? member : PropertyName;
            } else {
                enum jsonKeyName = member;
            }

            auto jsonItemPtr = jsonKeyName in json;
            if(jsonItemPtr is null) {
                version(GEAR_DEBUG) {
                    if(jsonKeyName != member)
                        Warningf("No data available for member: %s as %s", member, jsonKeyName);
                    else
                        Warningf("No data available for member: %s", member);
                }
            } else {
                debug(GEAR_DEBUG_MORE) Tracef("available data: %s = %s", member, jsonItemPtr.toString());
                static if(is(memberType == class)) {
                    __traits(getMember, target, member) = toObject!(memberType, options)(*jsonItemPtr);
                } else {
                    __traits(getMember, target, member) = toObject!(memberType, options)(*jsonItemPtr);
                }
            }
        }   
    }

    /// JsonSerializable
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)(
            auto ref const(JSONValue) json, 
            T defaultValue = T.init) 
            if(is(T == interface) && is(T : JsonSerializable)) {

        auto jsonItemPtr = MetaTypeName in json;
        if(jsonItemPtr is null) {
            Warningf("Can't find 'type' item for interface %s", T.stringof);
            return T.init;
        }
        string typeId = jsonItemPtr.str;
        T t = cast(T) Object.factory(typeId);
        if(t is null) {
            Warningf("Can't create instance for %s", T.stringof);
        }
        t.jsonDeserialize(json);
        return t;
    
    }

    /// SysTime
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)(
            auto ref const(JSONValue) json, 
            T defaultValue = T.init) 
            if(is(T == SysTime)) {
  
        JSONType jt = json.type();
        if(jt == JSONType.string) {
            return SysTime.fromSimpleString(json.str);
        } else if(jt == JSONType.integer) {
            return SysTime(json.integer);  // STD time
        } else {
            return handleException!(T, options.CanThrow())(json, "wrong SysTime type", defaultValue);
        }
    }

    // static N toObject(N : Nullable!T, T, bool CanThrow = false)(auto ref const(JSONValue) json) {

    //     return (json.type == JSONType.null_) ? N() : toObject!T(json).nullable;
    // }

    /// JSONValue
    static T toObject(T : JSONValue, SerializationOptions options = SerializationOptions.Default)(auto ref const(JSONValue) json) {
        import std.typecons : nullable;
        return json.nullable.get();
    }

    /// ditto
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (auto ref const(JSONValue) json, T defaultValue = T.init) 
            if (isNumeric!T || isSomeChar!T) {

        switch (json.type) {
        case JSONType.null_, JSONType.false_:
            return 0.to!T;

        case JSONType.true_:
            return 1.to!T;

        case JSONType.float_:
            return json.floating.to!T;

        case JSONType.integer:
            return json.integer.to!T;

        case JSONType.uinteger:
            return json.uinteger.to!T;

        case JSONType.string:
            try {
                return json.str.to!T;
            } catch(Exception ex) {
                return handleException!(T, options.CanThrow())(json, ex.msg, defaultValue);
            }

        default:
            return handleException!(T, options.CanThrow())(json, "", defaultValue);
        }
    }

    static T HandleException(T, bool CanThrow = false) (auto ref const(JSONValue) json, 
        string message, T defaultValue = T.init) {
        static if (CanThrow) {
            throw new JSONException(json.toString() ~ " is not a " ~ T.stringof ~ " type");
        } else {
        version (GEAR_DEBUG)
            Warningf(" %s is not a %s type. Using the defaults instead! \n Exception: %s",
                json.toString(), T.stringof, message);
            return defaultValue;
        }
    }

    /// bool
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (auto ref const(JSONValue) json) if (isBoolean!T) {

        switch (json.type) {
        case JSONType.null_, JSONType.false_:
            return false;

        case JSONType.float_:
            return json.floating != 0;

        case JSONType.integer:
            return json.integer != 0;

        case JSONType.uinteger:
            return json.uinteger != 0;

        case JSONType.string:
            return json.str.length > 0;

        default:
            return true;
        }
    }

    /// string
    static T toObject(T, SerializationOptions options = SerializationOptions.Default)
            (auto ref const(JSONValue) json, T defaultValue = T.init)
                if (isSomeString!T || is(T : string) || is(T : wstring) || is(T : dstring)) {

        static if (is(T == enum)) {
            foreach (member; __traits(allMembers, T)) {
                auto m = __traits(getMember, T, member);

                if (json.str == m) {
                    return m;
                }
            }
            return handleException!(T, options.CanThrow())(json, 
                " is not a member of " ~ typeid(T).toString(), defaultValue);
        } else {
            return (json.type == JSONType.string ? json.str : json.toString()).to!T;
        }
    }

    /// Object array
    static T toObject(T : U[], SerializationOptions options = SerializationOptions.Default, U)
            (auto ref const(JSONValue) json, 
            T defaultValue = T.init)
            if (isArray!T && !isSomeString!T && !is(T : string) && !is(T
                : wstring) && !is(T : dstring)) {

        switch (json.type) {
            case JSONType.null_:
                return [];

            case JSONType.false_:
                return [toObject!(U, options)(JSONValue(false))];

            case JSONType.true_:
                return [toObject!(U, options)(JSONValue(true))];

            case JSONType.array:
                return json.array
                    .map!(value => toObject!(U, options)(value))
                    .array
                    .to!T;

            case JSONType.object:
                return handleException!(T, options.CanThrow())(json, "", defaultValue);

            default:
                try {
                    U obj = toObject!(U, options.CanThrow(true))(json);
                    return [obj];
                } catch(Exception ex) {
                    Warning(ex.msg);
                    version(GEAR_DEBUG) Warning(ex);
                    if(options.CanThrow)
                        throw ex;
                    else {
                        return [];
                    }
                }
        }
    }

    /// AssociativeArray
    static T toObject(T : U[K], SerializationOptions options = SerializationOptions.Default, U, K)(
            auto ref const(JSONValue) json, T defaultValue = T.init) 
            if (isAssociativeArray!T) {
        
        U[K] result;

        switch (json.type) {
        case JSONType.null_:
            return result;

        case JSONType.object:
            foreach (key, value; json.object) {
                Warning(typeid(value));
                result[key.to!K] = toObject!(U, options)(value);
            }

            break;

        case JSONType.array:
            foreach (key, value; json.array) {
                result[key.to!K] = toObject!(U, options)(value);
            }

            break;

        default:
            return handleException!(T, options.CanThrow())(json, "", defaultValue);
        }

        return result;
    }


    /* -------------------------------------------------------------------------- */
    /*                                   toJson                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * class
     */
    static JSONValue toJson(int Depth=-1, T)(T value) if (is(T == class)) {
        enum options = SerializationOptions().Depth(Depth);
        return toJson!(options)(value);
    }


    /// ditto
    static JSONValue toJson(SerializationOptions options, T)
            (T value) if (is(T == class)) {
                
        bool[size_t] serializationStates;
        return toJsonImpl!(options)(value, serializationStates);
    }

    /**
     * Implements for class to json
     */
    private static JSONValue toJsonImpl(SerializationOptions options, T)
            (T value, ref bool[size_t] serializationStates) if (is(T == class)) {
        
        debug(GEAR_DEBUG_MORE) {
            Info("======== current type: class " ~ T.stringof);
            Tracef("%s, T: %s",
                options, T.stringof);
        }
        static if(is(T : JsonSerializable)) {
            // JsonSerializable first
            return toJson!(JsonSerializable, IncludeMeta.no)(value);
        } else {
            JSONValue v = serializeObject!(options, T)(value, serializationStates);

            version(GEAR_DEBUG_MORE) {
                error(serializationStates);
            }

            return v;
        }
    }

    deprecated("Using the other form of toJson(options) instead.")
    static JSONValue toJson(T, TraverseBase traverseBase,
            OnlyPublic onlyPublic = OnlyPublic.no, 
            IncludeMeta includeMeta = IncludeMeta.no)
            (T value) if (is(T == class)) {
        enum options = SerializationOptions(OnlyPublic, TraverseBase, IncludeMeta);
        bool[size_t] serializationStates;
        return serializeObject!(options, T)(value, serializationStates);
    }


    deprecated("Using SerializeObject(SerializationOptions) instead.")
    static JSONValue SerializeObject(OnlyPublic onlyPublic, TraverseBase traverseBase,
        IncludeMeta includeMeta, T) (T value) if (is(T == class)) {

        enum options = SerializationOptions(OnlyPublic, TraverseBase, IncludeMeta);
        bool[size_t] serializationStates;
        return serializeObject!(options, T)(value, serializationStates);
    }

    /**
     * class object
     */
    static JSONValue SerializeObject(SerializationOptions options = SerializationOptions.Full, T)
            (T value, ref bool[size_t] serializationStates) if (is(T == class)) {
        import std.traits : isSomeFunction, isType;

        debug(GEAR_DEBUG_MORE) {
            Info("======== current type: class " ~ T.stringof);
            Tracef("%s, T: %s", options, T.stringof);
            // Tracef("TraverseBase = %s, OnlyPublic = %s, IncludeMeta = %s, T: %s",
            //     TraverseBase, OnlyPublic, IncludeMeta, T.stringof);
        }

        if (value is null) {
            version(GEAR_DEBUG) Warning("value is null");
            return JSONValue(null);
        }

        size_t objHash = value.toHash() + hashOf(T.stringof);
        auto itemPtr = objHash in serializationStates;
        if(itemPtr !is null && *itemPtr) {
            debug(GEAR_DEBUG_MORE) Tracef("%s serialized.", T.stringof);
            return JSONValue(null);
        }
        
        serializationStates[objHash] = true;

        auto result = JSONValue();
        static if(options.IncludeMeta) {
            result[MetaTypeName] = typeid(T).name;
        }
        // debug(GEAR_DEBUG_MORE) pragma(msg, "======== current type: class " ~ T.stringof);
        
        // super fields
        static if(options.TraverseBase) {
            alias baseClasses = BaseClassesTuple!T;
            static if(baseClasses.length >= 1) {

                alias BaseType = baseClasses[0];
                debug(GEAR_DEBUG_MORE) {
                    Tracef("BaseType: %s", BaseType.stringof);
                }
                static if(!is(BaseType == Object)) {
                    JSONValue superResult = serializeObject!(options, BaseType)(value, serializationStates);
                    if(!superResult.isNull)
                        result["super"] = superResult;
                }
            }
        }
        
        // current fields
        static foreach (string member; FieldNameTuple!T) {
            serializeMember!(member, options)(value, result, serializationStates);
        }

        return result;
    }

    /**
     * struct
     */
    
    static JSONValue toJson(SerializationOptions options = SerializationOptions(), T)(T value)
            if (is(T == struct) && !is(T == SysTime)) {
        bool[size_t] serializationStates;
        return toJsonImpl!(options)(value, serializationStates);
    }

    /**
     * Implements for struct to json
     */
    static JSONValue toJsonImpl(SerializationOptions options = SerializationOptions(), T)(T value, 
            ref bool[size_t] serializationStates) if (is(T == struct) && !is(T == SysTime)) {

        static if(is(T == JSONValue)) {
            return value;
        } else {
            auto result = JSONValue();
            // debug(GEAR_DEBUG_MORE) pragma(msg, "======== current type: struct " ~ T.stringof);
            debug(GEAR_DEBUG_MORE) Info("======== current type: struct " ~ T.stringof);
                
            static foreach (string member; FieldNameTuple!T) {
                serializeMember!(member, options)(value, result, serializationStates);
            }

            return result;
        }
    }

    /**
     * Object's memeber
     */
    private static void SerializeMember(string member, 
            SerializationOptions options = SerializationOptions.Default, T)
            (T obj, ref JSONValue result, ref bool[size_t] serializationStates) {

        // debug(GEAR_DEBUG_MORE) pragma(msg, "\tfield=" ~ member);

        alias currentMember = __traits(getMember, T, member);

        static if(options.OnlyPublic) {
            static if (__traits(getProtection, currentMember) == "public") {
                enum canSerialize = true;
            } else {
                enum canSerialize = false;
            }
        } else static if(hasUDA!(currentMember, Ignore) || hasUDA!(currentMember, JsonIgnore)) {
            enum canSerialize = false;
        } else {
            enum canSerialize = true;
        }
        
        debug(GEAR_DEBUG_MORE) {
            Tracef("name: %s, %s", member, options);
        }

        static if(canSerialize) {
            alias memberType = typeof(currentMember);
            debug(GEAR_DEBUG_MORE) Infof("memberType: %s in %s", memberType.stringof, T.stringof);

            static if(is(memberType == interface) && !is(memberType : JsonSerializable)) {
                version(GEAR_DEBUG) Warning("skipped a interface member(not JsonSerializable): " ~ member);
            } else {
                auto m = __traits(getMember, obj, member);

                alias jsonPropertyUDAs = getUDAs!(currentMember, JsonProperty);
                static if(jsonPropertyUDAs.length > 0) {
                    enum PropertyName = jsonPropertyUDAs[0].name;
                    enum jsonKeyName = (PropertyName.length == 0) ? member : PropertyName;
                } else {
                    enum jsonKeyName = member;
                }

                auto json = serializeMember!(options)(m, serializationStates);

                debug(GEAR_DEBUG_MORE) {
                    Tracef("name: %s, value: %s", member, json.toString());
                }

                bool canSetValue = true;
                if(json.isNull) {
                    static if(options.IgnoreNull) {
                        canSetValue = false;
                    }
                }

                if (canSetValue) {
                        // Trace(result);
                    if(!result.isNull) {
                        auto jsonItemPtr = jsonKeyName in result;
                        if(jsonItemPtr !is null) {
                            version(GEAR_DEBUG) Warning("overrided field: " ~ member);
                        }
                    }
                    result[jsonKeyName] = json;
                }
            }
        } else {
            debug(GEAR_DEBUG_MORE) Tracef("skipped member, name: %s", member);
        }
    }

    private static JSONValue SerializeMember(SerializationOptions options, T)(T m, 
            ref bool[size_t] serializationStates) {
        JSONValue json;
        enum Depth = options.Depth;
        static if(is(T == interface) && is(T : JsonSerializable)) {
            static if(Depth == -1 || Depth > 0) { json = toJson!(JsonSerializable)(m);}
        } else static if(is(T == SysTime)) {
            json = toJson!SysTime(m);
        // } else static if(isSomeString!T) {
        //     json = toJson(m);
        } else static if(is(T == class)) {
            if(m !is null) {
                json = serializeObjectMember!(options)(m, serializationStates);
            }
        } else static if(is(T == struct)) {
            json = serializeObjectMember!(options)(m, serializationStates);
        } else static if(is(T : U[], U)) { 
            if(m is null) {
                static if(!options.IgnoreNull) {
                    static if(isSomeString!T) {
                        json = toJson(m);
                    } else {
                        json = JSONValue[].init;
                    }
                }
            } else {
                static if (is(U == class) || is(U == struct) || is(U == interface)) {
                    // class[] obj; struct[] obj;
                    json = serializeObjectMember!(options)(m, serializationStates);
                } else {
                    json = toJson(m);
                }
            }
        } else {
            json = toJson(m);
        }

        return json;
        
    }

    private static JSONValue SerializeObjectMember(SerializationOptions options = 
            SerializationOptions.Default, T)(ref T m, ref bool[size_t] serializationStates) {
        enum Depth = options.Depth;
        static if(Depth > 0) {
            enum SerializationOptions memeberOptions = options.Depth(options.Depth-1);
            return toJsonImpl!(memeberOptions)(m, serializationStates);
        } else static if(Depth == -1) {
            return toJsonImpl!(options)(m, serializationStates);
        } else {
            return JSONValue.init;
        }
    }

    /**
     * SysTime
     */
    static JSONValue toJson(T)(T value, bool asInteger=true) if(is(T == SysTime)) {
        if(asInteger)
            return JSONValue(value.stdTime()); // STD time
        else 
            return JSONValue(value.toString());
    }

    /**
     * JsonSerializable
     */
    static JSONValue toJson(T, IncludeMeta includeMeta = IncludeMeta.yes)
                    (T value) if (is(T == interface) && is(T : JsonSerializable)) {

        debug(GEAR_DEBUG_MORE) {
            if(value is null) {
                Infof("======== current type: interface = %s, Object = null", 
                    T.stringof);
            } else {
                Infof("======== current type: interface = %s, Object = %s", 
                    T.stringof, typeid(cast(Object)value).name);
            }
        }
        
        if(value is null) {
            return JSONValue(null);
        }

        JSONValue v = value.jsonSerialize();
        static if(IncludeMeta) {
            auto itemPtr = MetaTypeName in v;
            if(itemPtr is null)
                v[MetaTypeName] = typeid(cast(Object)value).name;
        }
        // TODO: Tasks pending completion -@zhangxueping at 2019-09-28T07:45:09+08:00
        // Remove the MetaTypeName memeber
        debug(GEAR_DEBUG_MORE) Trace(v.toString());
        return v;
    }

    /**
     * Basic type
     */
    static JSONValue toJson(T)(T value) if (isBasicType!T) {
        static if(is(T == double) || is(T == float)) {
            import std.math : isNaN;
            if(isNaN(value)) {
                Warning("Uninitialized float/double value. It will be set to zero.");
                value = 0;
            }
        }
        return JSONValue(value);
    }

    /**
     * T[]
     */
    static JSONValue toJson(SerializationOptions options = SerializationOptions.Default, T: U[], U)(T value) {
        bool[size_t] serializationStates;
        return toJsonImpl!(options)(value, serializationStates);
    }

    private static JSONValue toJsonImpl(SerializationOptions options = SerializationOptions.Default, T: U[], U)(T value, 
            ref bool[size_t] serializationStates) {

        static if(is(U == class)) { // class[]
            if(value is null) {
                return JSONValue(JSONValue[].init);
            } else {
                return JSONValue(value.map!(item => toJsonImpl!(options)(item, serializationStates))()
                        .map!(json => json.isNull ? JSONValue(null) : json).array);
            }
        } else static if(is(U == struct)) { // struct[]
            if(value is null) {
                return JSONValue(JSONValue[].init);
            } else {
                static if(is(U == SysTime)) {
                    return JSONValue(value.map!(item => toJson(item))()
                            .map!(json => json.isNull ? JSONValue(null) : json).array);
                } else {
                    return JSONValue(value.map!(item => toJsonImpl!(options)(item, serializationStates))()
                            .map!(json => json.isNull ? JSONValue(null) : json).array);
                }
            }
        } else static if(is(U : S[], S)) { // S[][]
            if(value is null) 
                return JSONValue(JSONValue[].init);

            JSONValue[] items;
            foreach(S[] element; value) {
                static if(is(S == struct) || is(S == class)) {
                    items ~= toJsonImpl(element, serializationStates);
                } else {
                    items ~= toJson(element);
                }
            }

            return JSONValue(items);
        } else {
            return JSONValue(value);
        }
    }


    /**
     * V[K]
     */
    static JSONValue toJson(SerializationOptions options = SerializationOptions.Default,
            T : V[K], V, K)(T value) {
        bool[size_t] serializationStates;
        return toJsonImpl!(options)(value, serializationStates);
    }

    private static JSONValue toJsonImpl(SerializationOptions options = SerializationOptions.Default,
            T : V[K], V, K)(T value, ref bool[size_t] serializationStates) {
        auto result = JSONValue();

        foreach (key; value.keys) {
            static if(is(V == SysTime)) {
                auto json = toJson(value[key]);
            } else static if(is(V == class) || is(V == struct) || is(V == interface)) {
                auto json = toJsonImpl!(options)(value[key], serializationStates);
            } else {
                auto json = toJson(value[key]);
            }
            result[key.to!string] = json.isNull ? JSONValue(null) : json;
        }

        return result;
    }

    deprecated("Using toObject instead.")
    alias fromJson = toObject;
}


alias toJson = JsonSerializer.toJson;
alias toObject = JsonSerializer.toObject;


deprecated("Using toObject instead.")
alias fromJson = JsonSerializer.toObject;