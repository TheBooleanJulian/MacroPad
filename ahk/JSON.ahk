#Requires AutoHotkey v2.0

; Minimal JSON parser - just enough to read config.json's structure (nested
; objects, strings, numbers, booleans, null). Not a general-purpose JSON
; library; written specifically for this project so there's no dependency
; on a third-party AHK v2 JSON implementation whose exact API I can't verify
; from here. Objects become Map, arrays become Array.
class JSON
{
    static parse(text) {
        pos := 1
        val := JSON._ParseValue(text, &pos)
        return val
    }

    static _SkipWhitespace(text, &pos) {
        len := StrLen(text)
        while (pos <= len) {
            ch := SubStr(text, pos, 1)
            if (ch = " " || ch = "`t" || ch = "`r" || ch = "`n")
                pos++
            else
                break
        }
    }

    static _ParseValue(text, &pos) {
        JSON._SkipWhitespace(text, &pos)
        ch := SubStr(text, pos, 1)
        if (ch = "{")
            return JSON._ParseObject(text, &pos)
        else if (ch = "[")
            return JSON._ParseArray(text, &pos)
        else if (ch = "`"")
            return JSON._ParseString(text, &pos)
        else if (ch = "t" || ch = "f")
            return JSON._ParseBool(text, &pos)
        else if (ch = "n")
            return JSON._ParseNull(text, &pos)
        else
            return JSON._ParseNumber(text, &pos)
    }

    static _ParseObject(text, &pos) {
        obj := Map()
        pos++ ; skip {
        JSON._SkipWhitespace(text, &pos)
        if (SubStr(text, pos, 1) = "}") {
            pos++
            return obj
        }
        loop {
            JSON._SkipWhitespace(text, &pos)
            key := JSON._ParseString(text, &pos)
            JSON._SkipWhitespace(text, &pos)
            pos++ ; skip :
            val := JSON._ParseValue(text, &pos)
            obj[key] := val
            JSON._SkipWhitespace(text, &pos)
            ch := SubStr(text, pos, 1)
            pos++
            if (ch = "}")
                break
            ; else ch = "," - loop again
        }
        return obj
    }

    static _ParseArray(text, &pos) {
        arr := []
        pos++ ; skip [
        JSON._SkipWhitespace(text, &pos)
        if (SubStr(text, pos, 1) = "]") {
            pos++
            return arr
        }
        loop {
            val := JSON._ParseValue(text, &pos)
            arr.Push(val)
            JSON._SkipWhitespace(text, &pos)
            ch := SubStr(text, pos, 1)
            pos++
            if (ch = "]")
                break
            ; else ch = "," - loop again
        }
        return arr
    }

    static _ParseString(text, &pos) {
        pos++ ; skip opening quote
        out := ""
        len := StrLen(text)
        while (pos <= len) {
            ch := SubStr(text, pos, 1)
            if (ch = "`"") {
                pos++
                break
            }
            if (ch = "\") {
                pos++
                esc := SubStr(text, pos, 1)
                if (esc = "n")
                    out .= "`n"
                else if (esc = "t")
                    out .= "`t"
                else if (esc = "r")
                    out .= "`r"
                else if (esc = "`"")
                    out .= "`""
                else if (esc = "\")
                    out .= "\"
                else if (esc = "/")
                    out .= "/"
                else
                    out .= esc
                pos++
            } else {
                out .= ch
                pos++
            }
        }
        return out
    }

    static _ParseNumber(text, &pos) {
        start := pos
        len := StrLen(text)
        while (pos <= len) {
            ch := SubStr(text, pos, 1)
            if (InStr("0123456789+-.eE", ch))
                pos++
            else
                break
        }
        ; Returned as-is; AHK's loose typing treats this numeric string as a
        ; number wherever arithmetic is actually needed. This project only
        ; ever compares/looks up these as strings, so no explicit cast.
        return SubStr(text, start, pos - start)
    }

    static _ParseBool(text, &pos) {
        if (SubStr(text, pos, 4) = "true") {
            pos += 4
            return true
        } else {
            pos += 5 ; "false"
            return false
        }
    }

    static _ParseNull(text, &pos) {
        pos += 4 ; "null"
        return ""
    }
}
