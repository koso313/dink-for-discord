using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace DinkHelper
{
    /// <summary>
    /// Parses a WoW SavedVariables file (plain Lua assignments of tables, strings, numbers, booleans).
    /// Tables become LuaTable: array part in List, keyed part in Dictionary.
    /// </summary>
    public sealed class LuaTable
    {
        public readonly List<object> Array = new List<object>();
        public readonly Dictionary<string, object> Hash = new Dictionary<string, object>();

        public object this[string key] => Hash.TryGetValue(key, out var v) ? v : null;
        public LuaTable Table(string key) => this[key] as LuaTable;
        public string Str(string key) => this[key] as string;
        public bool Bool(string key, bool fallback) => this[key] is bool b ? b : fallback;
    }

    public static class LuaSv
    {
        public static Dictionary<string, object> Parse(byte[] src)
        {
            var p = new Parser(src);
            var result = new Dictionary<string, object>();
            while (true)
            {
                p.Skip();
                if (p.AtEnd) break;
                string name = p.Identifier();
                p.Skip(); p.Expect('=');
                result[name] = p.Value();
            }
            return result;
        }

        sealed class Parser
        {
            readonly byte[] s;
            int i;
            public Parser(byte[] src)
            {
                s = src;
                if (s.Length >= 3 && s[0] == 0xEF && s[1] == 0xBB && s[2] == 0xBF) i = 3; // BOM
            }
            public bool AtEnd => i >= s.Length;

            Exception Error(string what) => new FormatException($"SavedVariables parse error at byte {i}: {what}");

            public void Skip()
            {
                while (i < s.Length)
                {
                    byte c = s[i];
                    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
                    if (c == '-' && i + 1 < s.Length && s[i + 1] == '-')
                    {
                        while (i < s.Length && s[i] != '\n') i++;
                        continue;
                    }
                    break;
                }
            }

            public void Expect(char c)
            {
                if (i >= s.Length || s[i] != c) throw Error($"expected '{c}'");
                i++;
            }

            public string Identifier()
            {
                int start = i;
                while (i < s.Length && (char.IsLetterOrDigit((char)s[i]) || s[i] == '_')) i++;
                if (i == start) throw Error("expected a name");
                return Encoding.ASCII.GetString(s, start, i - start);
            }

            public object Value()
            {
                Skip();
                if (i >= s.Length) throw Error("unexpected end");
                byte c = s[i];
                if (c == '{') return Table();
                if (c == '"' || c == '\'') return Str();
                if (c == '-' || c == '.' || (c >= '0' && c <= '9')) return Number();
                string word = Identifier();
                switch (word)
                {
                    case "true": return true;
                    case "false": return false;
                    case "nil": return null;
                }
                throw Error("unexpected word " + word);
            }

            LuaTable Table()
            {
                Expect('{');
                var t = new LuaTable();
                while (true)
                {
                    Skip();
                    if (i >= s.Length) throw Error("unclosed table");
                    if (s[i] == '}') { i++; return t; }
                    if (s[i] == '[')
                    {
                        i++;
                        object key = Value();
                        Skip(); Expect(']'); Skip(); Expect('=');
                        object v = Value();
                        if (key is double d && d == Math.Floor(d) && d >= 1 && d == t.Array.Count + 1 && !(v is null))
                            t.Array.Add(v);
                        else
                            t.Hash[Convert.ToString(key, CultureInfo.InvariantCulture)] = v;
                    }
                    else if (char.IsLetter((char)s[i]) || s[i] == '_')
                    {
                        int save = i;
                        string name = Identifier();
                        Skip();
                        if (i < s.Length && s[i] == '=') { i++; t.Hash[name] = Value(); }
                        else { i = save; t.Array.Add(Value()); }
                    }
                    else t.Array.Add(Value());
                    Skip();
                    if (i < s.Length && (s[i] == ',' || s[i] == ';')) i++;
                }
            }

            string Str()
            {
                byte quote = s[i++];
                var bytes = new List<byte>();
                while (true)
                {
                    if (i >= s.Length) throw Error("unclosed string");
                    byte c = s[i++];
                    if (c == quote) break;
                    if (c != '\\') { bytes.Add(c); continue; }
                    byte e = s[i++];
                    switch ((char)e)
                    {
                        case 'n': bytes.Add(10); break;
                        case 'r': bytes.Add(13); break;
                        case 't': bytes.Add(9); break;
                        case 'a': bytes.Add(7); break;
                        case 'b': bytes.Add(8); break;
                        case 'f': bytes.Add(12); break;
                        case 'v': bytes.Add(11); break;
                        case '\n': bytes.Add(10); break;
                        case '\r': bytes.Add(10); if (i < s.Length && s[i] == '\n') i++; break;
                        default:
                            if (e >= '0' && e <= '9')
                            {
                                int n = e - '0', k = 1;
                                while (k < 3 && i < s.Length && s[i] >= '0' && s[i] <= '9') { n = n * 10 + (s[i++] - '0'); k++; }
                                bytes.Add((byte)n);
                            }
                            else bytes.Add(e); // \\ \" \'
                            break;
                    }
                }
                return Encoding.UTF8.GetString(bytes.ToArray());
            }

            double Number()
            {
                int start = i;
                while (i < s.Length && "0123456789+-.eExXabcdefABCDEF".IndexOf((char)s[i]) >= 0) i++;
                string text = Encoding.ASCII.GetString(s, start, i - start);
                if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                    return Convert.ToInt64(text.Substring(2), 16);
                if (text == "inf") return double.PositiveInfinity;
                return double.Parse(text, NumberStyles.Float, CultureInfo.InvariantCulture);
            }
        }
    }
}
