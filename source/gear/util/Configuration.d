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

module gear.util.Configuration;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.regex;
import std.stdio;
import std.string;
import std.traits;

import gear.logging;
import gear.Exceptions;

/**
 * 
 */
struct Configuration {
    string name;
}

/**
 * 
 */
struct ConfigurationFile {
    string name;
}

/**
 * 
 */
struct Value {
    this(bool opt) {
        optional = opt;
    }

    this(string str, bool opt = false) {
        name = str;
        optional = opt;
    }

    string name;
    bool optional = false;
}

class BadFormatException : Exception {
    mixin basicExceptionCtors;
}

class EmptyValueException : Exception {
    mixin basicExceptionCtors;
}

/**
 * 
 */
T as(T = string)(string value, T v = T.init) {
    if (value.empty)
        return v;

    static if (is(T == bool)) {
        if (toLower(value) == "false" || value == "0")
            return false;
        else
            return true;
    } else static if (is(T == string)) {
        return value;
    } else static if (std.traits.isNumeric!(T)) {
        return to!T(value);
    } else static if(is(T U : U[])) {
        string[] values = split(value, ",");
        U[] r = new U[values.length];
        for(size_t i=0; i<values.length; i++) {
            r[i] = strip(values[i]).as!(U)();
        }
        return r;
    } else {
        Infof("T:%s, %s", T.stringof, value);
        return cast(T) value;
    }
}


private auto ArrayItemParttern = ctRegex!(`(\w+)\[([0-9]+)\]`);

/**
 * 
 */
class ConfigurationItem {
    ConfigurationItem parent;

    this(string name, string parentPath = "") {
        // version(GEAR_CONFIG_DEBUG) Tracef("new item: %s, parent: %s", name, parentPath);
        _name = name;
    }

    @property ConfigurationItem SubItem(string name) {
        ConfigurationItem v = _map.get(name, null);
        if (v is null) {
            string path = this.FullPath();
            if (path.empty)
                path = name;
            else
                path = path ~ "." ~ name;
            // throw new EmptyValueException(format("The item for '%s' is undefined! ", path));
            Warningf("The items for '%s' is undefined! Use the defaults now", path);
        }
        return v;
    }

    @property ConfigurationItem[] SubItems(string name) {
        ConfigurationItem[] r;
        foreach(string key; _map.byKey()) {
            Captures!string p = matchFirst(key, ArrayItemParttern);
            if(!p.empty && p[1] == name) {
                ConfigurationItem it = _map[key];
                r ~= _map[key];
            }
        }
        
        if(r is null) {
            string path = this.FullPath();
            if (path.empty)
                path = name;
            else
                path = path ~ "." ~ name;
            // throw new EmptyValueException(format("The items for '%s' is undefined! ", path));
            Warningf("The items for '%s' is undefined! Use the defaults now", path);
        }
        return r;
    }

    bool Exists(string name) {
        auto v = _map.get(name, null);
        bool r = v !is null;
        if(!r) {
            // try to check array items
            foreach(string key; _map.byKey) {
                Captures!string p = matchFirst(key, ArrayItemParttern);
                if(!p.empty && p[1] == name) {
                    return true;
                }
            }
        }
        return r;
    }

    @property string Name() {
        return _name;
    }

    @property string FullPath() {
        return _fullPath;
    }

    @property string Value() {
        return _value;
    }

    ConfigurationItem OpDispatch(string s)() {
        return SubItem(s);
    }

    ConfigurationItem OpIndex(string s) {
        return SubItem(s);
    }

    T as(T = string)(T v = T.init) {
        return _value.as!(T)(v);
    }

    void ApppendChildNode(string key, ConfigurationItem subItem) {
        subItem.parent = this;
        _map[key] = subItem;
    }

    override string toString() {
        return _fullPath;
    }

    // string buildFullPath()
    // {
    //     string r = name;
    //     ConfigurationItem cur = parent;
    //     while (cur !is null && !cur.name.empty)
    //     {
    //         r = cur.name ~ "." ~ r;
    //         cur = cur.parent;
    //     }
    //     return r;
    // }

private:
    string _value;
    string _name;
    string _fullPath;
    ConfigurationItem[string] _map;
}

// dfmt off
__gshared const string[] reservedWords = [
    "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool",
    "break", "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat", 
    "char", "class","const", "continue", "creal", "dchar", "debug", "default", 
    "delegate", "delete", "deprecated", "do", "double", "else", "enum", "export", 
    "extern", "false", "final", "finally", "float", "for", "foreach", "foreach_reverse",
    "function", "goto", "idouble", "if", "ifloat", "immutable", "import", "in", "inout", 
    "int", "interface", "invariant", "ireal", "is", "lazy", "long",
    "macro", "mixin", "module", "new", "nothrow", "null", "out", "override", "package",
    "pragma", "private", "protected", "public", "pure", "real", "ref", "return", "scope", 
    "shared", "short", "static", "struct", "super", "switch", "synchronized", "template", 
    "this", "throw", "true", "try", "typedef", "typeid", "typeof", "ubyte", "ucent", 
    "uint", "ulong", "union", "unittest", "ushort", "version", "void", "volatile", "wchar",
    "while", "with", "__FILE__", "__FILE_FULL_PATH__", "__MODULE__", "__LINE__", 
    "__FUNCTION__", "__PRETTY_FUNCTION__", "__gshared", "__traits", "__vector", "__parameters",
    "subItem", "RootItem"
];
// dfmt on

/**
*/
class ConfigBuilder {

    this() {
        _value = new ConfigurationItem("");
    }


    this(string filename, string section = "") {
        _section = section;
        _value = new ConfigurationItem("");
        
        string rootPath = dirName(thisExePath());
        filename = buildPath(rootPath, filename);
        LoadConfig(filename);
    }


    ConfigurationItem SubItem(string name) {
        return _value.SubItem(name);
    }

    @property ConfigurationItem RootItem() {
        return _value;
    }

    ConfigurationItem OpDispatch(string s)() {
        return _value.OpDispatch!(s)();
    }

    ConfigurationItem OpIndex(string s) {
        return _value.SubItem(s);
    }

    /**
     * Searches for the property with the specified key in this property list.
     * If the key is not found in this property list, the default property list,
     * and its defaults, recursively, are then checked. The method returns
     * {@code null} if the property is not found.
     *
     * @param   key   the property key.
     * @return  the value in this property list with the specified key value.
     */
    string GetProperty(string key) {
        return _itemMap.get(key, "");
    }

    /**
     * Searches for the property with the specified key in this property list.
     * If the key is not found in this property list, the default property list,
     * and its defaults, recursively, are then checked. The method returns
     * {@code null} if the property is not found.
     *
     * @param   key   the property key.
     * @return  the value in this property list with the specified key value.
     * @see     #setProperty
     * @see     #defaults
     */
    string GetProperty(string key, string defaultValue) {
        return _itemMap.get(key, defaultValue);
    }

    bool HasProperty(string key) {
        auto p = key in _itemMap;
        return p !is null;
    }

    bool IsEmpty() {
        return _itemMap.length == 0;
    }

    alias setProperty = SetValue;

    void SetValue(string key, string value) {

        version (GEAR_CONFIG_DEBUG)
            Tracef("setting item: key=%s, value=%s", key, value);
        _itemMap[key] = value;

        string currentPath;
        string[] list = split(key, '.');
        ConfigurationItem cvalue = _value;
        foreach (str; list) {
            if (str.length == 0)
                continue;

            if (canFind(reservedWords, str)) {
                version (GEAR_CONFIG_DEBUG) Warningf("Found a reserved word: %s. It may cause some errors.", str);
            }

            if (currentPath.empty)
                currentPath = str;
            else
                currentPath = currentPath ~ "." ~ str;

            // version (GEAR_CONFIG_DEBUG)
            //     Tracef("checking node: path=%s", currentPath);
            ConfigurationItem tvalue = cvalue._map.get(str, null);
            if (tvalue is null) {
                tvalue = new ConfigurationItem(str);
                tvalue._fullPath = currentPath;
                cvalue.ApppendChildNode(str, tvalue);
                version (GEAR_CONFIG_DEBUG)
                    Tracef("new node: key=%s, parent=%s, node=%s", key, cvalue.FullPath, str);
            }
            cvalue = tvalue;
        }

        if (cvalue !is _value)
            cvalue._value = value;
    }

    T Build(T, string nodeName = "")() {
        static if (!nodeName.empty) {
            // version(GEAR_CONFIG_DEBUG) pragma(msg, "node name: " ~ nodeName);
            return BuildItem!(T)(this.SubItem(nodeName));
        } else static if (hasUDA!(T, Configuration)) {
            enum string name = getUDAs!(T, Configuration)[0].name;
            // pragma(msg,  "node name: " ~ name);
            // Warning("node name: ", name);
            static if (!name.empty) {
                return BuildItem!(T)(this.SubItem(name));
            } else {
                return BuildItem!(T)(this.RootItem);
            }
        } else {
            return BuildItem!(T)(this.RootItem);
        }
    }

    private static T CreatT(T)() {
        static if (is(T == struct)) {
            return T();
        } else static if (is(T == class)) {
            return new T();
        } else {
            static assert(false, T.stringof ~ " is not supported!");
        }
    }

    private static T BuildItem(T)(ConfigurationItem item) {
        auto r = CreatT!T();
        enum generatedCode = BuildSetFunction!(T, r.stringof, item.stringof)();
        // pragma(msg, generatedCode);
        mixin(generatedCode);
        return r;
    }

    private static string BuildSetFunction(T, string returnParameter, string incomingParameter)() {
        import std.format;

        string str = "import gear.logging;";
        foreach (memberName; __traits(allMembers, T)) // TODO: // foreach (memberName; __traits(derivedMembers, T))
        {
            enum memberProtection = __traits(getProtection, __traits(getMember, T, memberName));
            static if (memberProtection == "private"
                    || memberProtection == "protected" || memberProtection == "export") {
                // version (GEAR_CONFIG_DEBUG) pragma(msg, "skip private member: " ~ memberName);
            } else static if (isType!(__traits(getMember, T, memberName))) {
                // version (GEAR_CONFIG_DEBUG) pragma(msg, "skip inner type member: " ~ memberName);
            } else static if (__traits(isStaticFunction, __traits(getMember, T, memberName))) {
                // version (GEAR_CONFIG_DEBUG) pragma(msg, "skip static member: " ~ memberName);
            } else {
                alias memberType = typeof(__traits(getMember, T, memberName));
                enum memberTypeString = memberType.stringof;

                static if (hasUDA!(__traits(getMember, T, memberName), Value)) {
                    enum itemName = getUDAs!((__traits(getMember, T, memberName)), Value)[0].name;
                    enum settingItemName = itemName.empty ? memberName : itemName;
                } else {
                    enum settingItemName = memberName;
                }

                static if (!is(memberType == string) && is(memberType T : T[])) {
                    static if(is(T == struct) || is(T == struct)) {
                        enum isArrayMember = true;
                    } else {
                        enum isArrayMember = false;
                    }
                } else {
                    enum isArrayMember = false;
                }

                // 
                static if (is(memberType == interface)) {
                    pragma(msg, "interface (unsupported): " ~ memberName);
                } else static if (is(memberType == struct) || is(memberType == class)) {
                    str ~= SetClassMemeber!(memberType, settingItemName,
                            memberName, returnParameter, incomingParameter)();
                } else static if (isFunction!(memberType)) {
                    enum r = SetFunctionMemeber!(memberType, settingItemName,
                                memberName, returnParameter, incomingParameter)();
                    if (!r.empty)
                        str ~= r;
                } else static if(isArrayMember) { // struct or class
                    enum memberModuleName = moduleName!(T);
                    str ~= "import " ~ memberModuleName ~ ";";
                    str ~= q{
                        if(%5$s.Exists("%1$s")) {
                            ConfigurationItem[] items = %5$s.SubItems("%1$s");
                            %3$s tempValues;
                            foreach(ConfigurationItem it; items) {
                                // version (GEAR_CONFIG_DEBUG) Tracef("name:%%s, value:%%s", it.name, item.value);
                                tempValues ~= BuildItem!(%6$s)(it); // it.as!(%6$s)();
                            }
                            %4$s.%2$s = tempValues;
                        } else {
                            version (GEAR_CONFIG_DEBUG) Warningf("Undefined item: %%s.%1$s" , %5$s.FullPath);
                        }                        
                        version (GEAR_CONFIG_DEBUG) Tracef("%4$s.%2$s=%%s", %4$s.%2$s);

                    }.format(settingItemName, memberName,
                            memberTypeString, returnParameter, incomingParameter, T.stringof);
                } else {
                    // version (GEAR_CONFIG_DEBUG) pragma(msg,
                    //         "setting " ~ memberName ~ " with item " ~ settingItemName);

                    str ~= q{
                        if(%5$s.Exists("%1$s")) {
                            %4$s.%2$s = %5$s.SubItem("%1$s").as!(%3$s)();
                        } else {
                            version (GEAR_CONFIG_DEBUG) Warningf("Undefined item: %%s.%1$s" , %5$s.FullPath);
                        }                        
                        version (GEAR_CONFIG_DEBUG) Tracef("%4$s.%2$s=%%s", %4$s.%2$s);

                    }.format(settingItemName, memberName,
                            memberTypeString, returnParameter, incomingParameter);
                }
            }
        }
        return str;
    }

    private static string SetFunctionMemeber(memberType, string settingItemName,
            string memberName, string returnParameter, string incomingParameter)() {
        string r = "";
        alias memeberParameters = Parameters!(memberType);
        static if (memeberParameters.length == 1) {
            alias parameterType = memeberParameters[0];

            static if (is(parameterType == struct) || is(parameterType == class)
                    || is(parameterType == interface)) {
                // version (GEAR_CONFIG_DEBUG) pragma(msg, "skip method with class: " ~ memberName);
            } else {
                // version (GEAR_CONFIG_DEBUG) pragma(msg, "method: " ~ memberName);

                r = q{
                    if(%5$s.Exists("%1$s")) {
                        %4$s.%2$s(%5$s.SubItem("%1$s").as!(%3$s)());
                    } else {
                        version (GEAR_CONFIG_DEBUG) Warningf("Undefined item: %%s.%1$s" , %5$s.FullPath);
                    }
                    
                    version (GEAR_CONFIG_DEBUG) Tracef("%4$s.%2$s=%%s", %4$s.%2$s);
                    }.format(settingItemName, memberName,
                        parameterType.stringof, returnParameter, incomingParameter);
            }
        } else {
            // version (GEAR_CONFIG_DEBUG) pragma(msg, "skip method: " ~ memberName);
        }

        return r;
    }

    private static SetClassMemeber(memberType, string settingItemName,
            string memberName, string returnParameter, string incomingParameter)() {
        enum fullTypeName = fullyQualifiedName!(memberType);
        enum memberModuleName = moduleName!(memberType);

        static if (settingItemName == memberName && hasUDA!(memberType, Configuration)) {
            // try to get the ItemName from the UDA Configuration in a class or struct
            enum newSettingItemName = getUDAs!(memberType, Configuration)[0].name;
        } else {
            enum newSettingItemName = settingItemName;
        }

        // version (GEAR_CONFIG_DEBUG)
        // {
        //     pragma(msg, "module name: " ~ memberModuleName);
        //     pragma(msg, "full type name: " ~ fullTypeName);
        //     pragma(msg, "setting " ~ memberName ~ " with item " ~ newSettingItemName);
        // }

        string r = q{
            import %1$s;
            
            // Tracef("%5$s.%3$s is a class/struct.");
            if(%6$s.Exists("%2$s")) {
                %5$s.%3$s = BuildItem!(%4$s)(%6$s.SubItem("%2$s"));
            }
            else {
                version (GEAR_CONFIG_DEBUG) Warningf("Undefined item: %%s.%2$s" , %6$s.FullPath);
            }
        }.format(memberModuleName, newSettingItemName,
                memberName, fullTypeName, returnParameter, incomingParameter);
        return r;
    }

    private void LoadConfig(string filename) {
        if (!exists(filename) || isDir(filename)) {
            throw new ConfigurationException("The config file doesn't exist: " ~ filename);
        }

        auto f = File(filename, "r");
        if (!f.isOpen())
            return;
        scope (exit)
            f.close();
        string section = "";
        int line = 1;
        while (!f.eof()) {
            scope (exit)
                line += 1;
            string str = f.readln();
            str = strip(str);
            if (str.length == 0)
                continue;
            if (str[0] == '#' || str[0] == ';')
                continue;
            auto len = str.length - 1;
            if (str[0] == '[' && str[len] == ']') {
                section = str[1 .. len].strip;
                continue;
            }
            if (section != _section && section != "")
                continue;

            str = StripInlineComment(str);
            auto site = str.indexOf("=");
            enforce!BadFormatException((site > 0),
                    format("Bad format in file %s, at line %d", filename, line));
            string key = str[0 .. site].strip;
            SetValue(key, str[site + 1 .. $].strip);
        }
    }

    private string StripInlineComment(string line) {
        ptrdiff_t index = indexOf(line, "# ");

        if (index == -1)
            return line;
        else
            return line[0 .. index];
    }

    
    private string _section;
    private ConfigurationItem _value;
    private string[string] _itemMap;
}

// version (unittest) {
//     import gear.util.Configuration;

//     @Configuration("app")
//     class TestConfig {
//         string test;
//         double time;

//         TestHttpConfig http;

//         @Value("optial", true)
//         int optial = 500;

//         @Value(true)
//         int optial2 = 500;

//         // mixin ReadConfig!TestConfig;
//     }

//     @Configuration("http")
//     struct TestHttpConfig {
//         @Value("listen")
//         int value;
//         string addr;

//         // mixin ReadConfig!TestHttpConfig;
//     }
// }

// unittest {
//     import std.stdio;
//     import FE = std.file;

//     FE.Write("test.config", `app.http.listen = 100
//     http.listen = 100
//     app.test = 
//     app.time = 0.25 
//     # this is  
//      ; start dev
//     [dev]
//     app.test = dev`);

//     auto conf = new ConfigBuilder("test.config");
//     assert(conf.http.listen.value.as!long() == 100);
//     assert(conf.app.test.value() == "");

//     auto confdev = new ConfigBuilder("test.config", "dev");
//     long tv = confdev.http.listen.value.as!long;
//     assert(tv == 100);
//     assert(confdev.http.listen.value.as!long() == 100);
//     writeln("----------", confdev.app.test.value());
//     string tvstr = cast(string) confdev.app.test.value;

//     assert(tvstr == "dev");
//     assert(confdev.app.test.value() == "dev");
//     bool tvBool = confdev.app.test.value.as!bool;
//     assert(tvBool);

//     assertThrown!(EmptyValueException)(confdev.app.host.value());

//     TestConfig test = confdev.build!(TestConfig)();
//     assert(test.test == "dev");
//     assert(test.time == 0.25);
//     assert(test.http.value == 100);
//     assert(test.optial == 500);
//     assert(test.optial2 == 500);
// }
