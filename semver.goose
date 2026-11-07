// semver - semantic versions for Goose.
//
// The package parses, compares, and formats versions in the SemVer 2.0.0
// form: MAJOR.MINOR.PATCH, then an optional pre-release, then optional
// build metadata.
//
// The repository is goose-semver. The package name is what a program
// imports it by, so the name is "semver".
//
// Every file in this package declares "namespace semver;". A user calls
// semver::parse. A user calls semver::compare.
namespace semver;

import std;
import range;

// Version holds one version. The pre-release and the build metadata are
// slices into the string that the parse read, so they stay valid only as
// long as that string.
struct Version {
    major: i32,
    minor: i32,
    patch: i32,
    pre: const u8[:],
    build: const u8[:],
}

// parse reads one version. It returns false when the text is not a
// version in the SemVer form. The pre-release and the build fields of the
// result refer to the input.
fn parse(s: const u8[:]) -> Version, bool {
    var v = Version { major: 0, minor: 0, patch: 0, pre: "", build: "" };

    // The build metadata starts at the first '+' and is not part of the
    // comparison.
    var core = s;
    let plus = find(core, "+");
    if plus >= 0 {
        v.build = core[plus + 1..];
        core = core[..plus];
    }
    // The pre-release starts at the first '-' after the core numbers.
    let dash = find(core, "-");
    if dash >= 0 {
        v.pre = core[dash + 1..];
        core = core[..dash];
    }

    // Three numbers separated by two dots.
    let first = find(core, ".");
    if first < 0 { return v, false; }
    let second = find(core[first + 1..], ".");
    if second < 0 { return v, false; }
    let mid = first + 1 + second;

    let ma, ok1 = parse_num(core[..first]);
    let mi, ok2 = parse_num(core[first + 1..mid]);
    let pa, ok3 = parse_num(core[mid + 1..]);
    if !ok1 || !ok2 || !ok3 { return v, false; }

    // A number has no leading zero, unless it is the number zero.
    if !num_form(core[..first]) || !num_form(core[first + 1..mid]) || !num_form(core[mid + 1..]) {
        return v, false;
    }

    if !pre_form(v.pre) { return v, false; }
    if !build_form(v.build) { return v, false; }

    v.major = ma;
    v.minor = mi;
    v.patch = pa;
    return v, true;
}

// parse_num reads the digits of one number. It returns false when the
// text is empty or holds something that is not a digit.
fn parse_num(s: const u8[:]) -> i32, bool {
    if s.len == 0 { return 0, false; }
    var n: i64 = 0;
    for c in s {
        if c < '0' || c > '9' { return 0, false; }
        n = n * 10 + (c - '0');
        if n > 0x7fffffff { return 0, false; }
    }
    return n as i32, true;
}

// num_form returns true when the number has the written form of the
// standard: digits, and no leading zero unless the number is "0".
fn num_form(s: const u8[:]) -> bool {
    if s.len == 0 { return false; }
    if s.len > 1 && s[0] == '0' { return false; }
    for c in s {
        if c < '0' || c > '9' { return false; }
    }
    return true;
}

// ident_form returns true when one part of a pre-release or of the build
// metadata holds only the characters that the standard allows.
fn ident_form(s: const u8[:], numbers_may_lead_zero: bool) -> bool {
    if s.len == 0 { return false; }
    var i = 0;
    while i < s.len {
        let c = s[i];
        let digit = c >= '0' && c <= '9';
        let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        if c == '-' || c == '.' {
            // A part boundary. An empty part is a fault.
            if i == 0 || i == s.len - 1 { return false; }
            if s[i - 1] == '.' || s[i + 1] == '.' { return false; }
            i += 1;
            continue;
        }
        if !digit && !alpha { return false; }
        i += 1;
    }
    // A numeric part of a pre-release has no leading zero. The build
    // metadata may hold leading zeros.
    if !numbers_may_lead_zero {
        var start = 0;
        while start <= s.len {
            let end = part_end(s, start);
            let part = s[start..end];
            if is_numeric(part) && !num_form(part) { return false; }
            start = end + 1;
        }
    }
    return true;
}

// pre_form returns true when the pre-release has the form of the standard.
fn pre_form(s: const u8[:]) -> bool {
    if s.len == 0 { return true; }
    return ident_form(s, false);
}

// build_form returns true when the build metadata has the form of the
// standard.
fn build_form(s: const u8[:]) -> bool {
    if s.len == 0 { return true; }
    return ident_form(s, true);
}

// compare puts a before b. It gives a negative number when a comes first,
// a positive one when b comes first, and zero when the versions hold the
// same precedence. The build metadata takes no part in the order.
fn compare(a: Version, b: Version) -> i64 {
    if a.major != b.major { return a.major - b.major; }
    if a.minor != b.minor { return a.minor - b.minor; }
    if a.patch != b.patch { return a.patch - b.patch; }
    // A version with a pre-release comes before one without.
    if a.pre.len == 0 && b.pre.len == 0 { return 0; }
    if a.pre.len == 0 { return 1; }
    if b.pre.len == 0 { return -1; }
    return compare_pre(a.pre, b.pre);
}

// compare_pre compares two pre-release strings, part by part.
fn compare_pre(a: const u8[:], b: const u8[:]) -> i64 {
    var ai = 0;
    var bi = 0;
    loop {
        let a_done = ai >= a.len;
        let b_done = bi >= b.len;
        if a_done && b_done { return 0; }
        // The shorter one comes first, when one is a prefix of the other.
        if a_done { return -1; }
        if b_done { return 1; }
        let a_end = part_end(a, ai);
        let b_end = part_end(b, bi);
        let ap = a[ai..a_end];
        let bp = b[bi..b_end];
        let a_num = is_numeric(ap);
        let b_num = is_numeric(bp);
        if a_num && b_num {
            let an, _ = parse_num(ap);
            let bn, _ = parse_num(bp);
            if an != bn { return an - bn; }
        } else if a_num {
            // Numbers come before letters.
            return -1;
        } else if b_num {
            return 1;
        } else {
            let order = compare_text(ap, bp);
            if order != 0 { return order; }
        }
        ai = a_end + 1;
        bi = b_end + 1;
    }
}

// part_end gives the index after the part that starts at start. A part
// ends before the next dot or at the end.
fn part_end(s: const u8[:], start: i64) -> i64 {
    var i = start;
    while i < s.len && s[i] != '.' { i += 1; }
    return i;
}

// compare_text compares two parts byte by byte. The shorter one comes
// first when one is a prefix of the other.
fn compare_text(a: const u8[:], b: const u8[:]) -> i64 {
    let n = if a.len < b.len { a.len } else { b.len };
    var i = 0;
    while i < n {
        if a[i] != b[i] {
            return if a[i] < b[i] { -1 } else { 1 };
        }
        i += 1;
    }
    if a.len == b.len { return 0; }
    return if a.len < b.len { -1 } else { 1 };
}

// is_numeric returns true when the part holds digits only.
fn is_numeric(s: const u8[:]) -> bool {
    if s.len == 0 { return false; }
    for c in s {
        if c < '0' || c > '9' { return false; }
    }
    return true;
}

// format writes the version into out. It holds the build metadata.
fn format(out: u8[>..]&, v: Version) {
    format(out, v.major);
    out.push('.');
    format(out, v.minor);
    out.push('.');
    format(out, v.patch);
    if v.pre.len > 0 {
        out.push('-');
        out.append(v.pre);
    }
    if v.build.len > 0 {
        out.push('+');
        out.append(v.build);
    }
}

// ---- accessors ----------------------------------------------------------
// The fields major, minor, patch, pre and build of Version are the plain
// accessors. These two split the dotted fields into their parts.

// pre_parts gives the dot-separated parts of the pre-release. It gives an
// empty array when the version has no pre-release.
fn pre_parts(v: Version) -> const u8[:][>..] {
    var out: const u8[:][>..] = [];
    if v.pre.len > 0 { return split(v.pre, '.'); }
    return out;
}

// build_parts gives the dot-separated parts of the build metadata.
fn build_parts(v: Version) -> const u8[:][>..] {
    var out: const u8[:][>..] = [];
    if v.build.len > 0 { return split(v.build, '.'); }
    return out;
}

// ---- diff ---------------------------------------------------------------

// diff names the release type between two versions, as the npm diff does:
// major, premajor, minor, preminor, patch, prepatch or prerelease. It gives
// the empty text when the versions hold the same precedence.
fn diff(a: Version, b: Version) -> const u8[:] {
    let c = compare(a, b);
    if c == 0 { return ""; }
    let hi = if c > 0 { a } else { b };
    let lo = if c > 0 { b } else { a };
    let hi_pre = hi.pre.len > 0;
    let lo_pre = lo.pre.len > 0;
    if lo_pre && !hi_pre {
        // 1.0.0-1 to anything with the same major is a major step.
        if lo.minor == 0 && lo.patch == 0 { return "major"; }
        if lo.major == hi.major && lo.minor == hi.minor && lo.patch == hi.patch {
            if lo.minor != 0 && lo.patch == 0 { return "minor"; }
            return "patch";
        }
    }
    if a.major != b.major { return if hi_pre { "premajor" } else { "major" }; }
    if a.minor != b.minor { return if hi_pre { "preminor" } else { "minor" }; }
    if a.patch != b.patch { return if hi_pre { "prepatch" } else { "patch" }; }
    return "prerelease";
}

// ---- inc ----------------------------------------------------------------

// pre_bump writes the next pre-release into out, as the npm "pre" step
// does. base is 0 or 1 for the first number, or -1 for none. It returns
// false when the identifier already is the whole pre-release and base is -1.
fn pre_bump(out: u8[>..]&, pre: const u8[:], ident: const u8[:], base: i64) -> bool {
    let b: i64 = if base > 0 { 1 } else { 0 };
    var next: u8[>..] = [];
    if pre.len == 0 {
        format(next, b);
    } else {
        let parts = split(pre, '.');
        var last_num: i64 = -1;
        for part, i in parts { if is_numeric(part) { last_num = i; } }
        for part, i in parts {
            if i > 0 { next.push('.'); }
            if i == last_num {
                let n, _ = parse_num(part);
                format(next, n + 1);
            } else {
                next.append(part);
            }
        }
        if last_num < 0 {
            if base < 0 && ident == pre { return false; }
            next.push('.');
            format(next, b);
        }
    }
    if ident.len == 0 {
        out.append(next);
        return true;
    }
    // Keep the bumped number when the pre-release already starts with the
    // identifier and a number follows it.
    let ip = split(ident, '.');
    let cur = split(next, '.');
    var same = ip.len < cur.len;
    if same {
        for part, i in ip { if part != cur[i] { same = false; } }
    }
    if same && is_numeric(cur[ip.len]) {
        out.append(next);
    } else {
        out.append(ident);
        if base >= 0 {
            out.push('.');
            format(out, b);
        }
    }
    return true;
}

// inc writes the next version into out, as the npm inc does. release is
// major, minor, patch, premajor, preminor, prepatch, prerelease or release.
// The identifier names the pre-release line. base is 0 or 1 for the first
// pre-release number, or -1 for none. The result holds no build metadata.
// It returns false, with out untouched, for a bad release type, a bad
// identifier, or a release of a version with no pre-release.
fn inc(out: u8[>..]&, v: Version, release: const u8[:], ident: const u8[:] = "", base: i64 = 0) -> bool {
    var ma = v.major as i64;
    var mi = v.minor as i64;
    var pa = v.patch as i64;
    var pre_in = v.pre;
    var want_pre = false;
    if release == "major" {
        if v.minor != 0 || v.patch != 0 || v.pre.len == 0 { ma += 1; }
        mi = 0; pa = 0; pre_in = "";
    } else if release == "minor" {
        if v.patch != 0 || v.pre.len == 0 { mi += 1; }
        pa = 0; pre_in = "";
    } else if release == "patch" {
        if v.pre.len == 0 { pa += 1; }
        pre_in = "";
    } else if release == "premajor" {
        ma += 1; mi = 0; pa = 0; pre_in = ""; want_pre = true;
    } else if release == "preminor" {
        mi += 1; pa = 0; pre_in = ""; want_pre = true;
    } else if release == "prepatch" {
        pa += 1; pre_in = ""; want_pre = true;
    } else if release == "prerelease" {
        if v.pre.len == 0 { pa += 1; }
        want_pre = true;
    } else if release == "release" {
        if v.pre.len == 0 { return false; }
        pre_in = "";
    } else {
        return false;
    }
    var pre_out: u8[>..] = [];
    if want_pre {
        if ident.len == 0 && base < 0 { return false; }
        if ident.len > 0 && !pre_form(ident) { return false; }
        if !pre_bump(pre_out, pre_in, ident, base) { return false; }
    }
    format(out, ma);
    out.push('.');
    format(out, mi);
    out.push('.');
    format(out, pa);
    if pre_out.len > 0 {
        out.push('-');
        out.append(pre_out);
    }
    return true;
}

// ---- coerce and clean ---------------------------------------------------

// coerce finds the first run of digits in the text and reads up to three
// dot-separated numbers from it, as the npm coerce does. Missing parts are
// zero. "v2.3 x" gives 2.3.0. A run of more than 16 digits is skipped. It
// returns false when no number is found or a part has a leading zero.
fn coerce(s: const u8[:]) -> Version, bool {
    var v = Version { major: 0, minor: 0, patch: 0, pre: "", build: "" };
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c < '0' || c > '9' { i += 1; continue; }
        let end = digit_end(s, i);
        if end - i > 16 { i = end; continue; }
        // The first run is the major number.
        let major = s[i..end];
        var minor: const u8[:] = "0";
        var patch: const u8[:] = "0";
        if end < s.len && s[end] == '.' {
            let e2 = digit_end(s, end + 1);
            if e2 > end + 1 && e2 - (end + 1) <= 16 {
                minor = s[end + 1..e2];
                if e2 < s.len && s[e2] == '.' {
                    let e3 = digit_end(s, e2 + 1);
                    if e3 > e2 + 1 && e3 - (e2 + 1) <= 16 { patch = s[e2 + 1..e3]; }
                }
            }
        }
        if !num_form(major) || !num_form(minor) || !num_form(patch) { return v, false; }
        let ma, ok1 = parse_num(major);
        let mi, ok2 = parse_num(minor);
        let pa, ok3 = parse_num(patch);
        if !ok1 || !ok2 || !ok3 { return v, false; }
        v.major = ma;
        v.minor = mi;
        v.patch = pa;
        return v, true;
    }
    return v, false;
}

// digit_end gives the index after the digits that start at start.
fn digit_end(s: const u8[:], start: i64) -> i64 {
    var i = start;
    while i < s.len && s[i] >= '0' && s[i] <= '9' { i += 1; }
    return i;
}

// clean trims the text, strips leading '=' and 'v' marks, parses the rest
// and writes it into out without the build metadata, as the npm clean
// does. It returns false, with out untouched, when the text is no version.
fn clean(out: u8[>..]&, s: const u8[:]) -> bool {
    var t = s;
    while t.len > 0 && is_space(t[0]) { t = t[1..]; }
    while t.len > 0 && is_space(t[t.len - 1]) { t = t[..t.len - 1]; }
    while t.len > 0 && (t[0] == '=' || t[0] == 'v') { t = t[1..]; }
    let v, ok = parse(t);
    if !ok { return false; }
    write_core(out, v);
    return true;
}

// ---- ranges -------------------------------------------------------------

// Part holds one version of a range text, where an x, a star or a missing
// number is -1.
struct Part {
    mj: i64,
    mn: i64,
    pt: i64,
    pre: const u8[:],
}

// xpart reads one number of a range, or an x or star as -1.
fn xpart(s: const u8[:]) -> i64, bool {
    if s == "x" || s == "X" || s == "*" { return -1, true; }
    if !num_form(s) { return 0, false; }
    let n, ok = parse_num(s);
    return n, ok;
}

// parse_partial reads a version of a range: leading 'v' and '=' marks,
// one to three numbers or x marks, and a pre-release. Build metadata is
// dropped.
fn parse_partial(s: const u8[:]) -> Part, bool {
    var r = Part { mj: -1, mn: -1, pt: -1, pre: "" };
    var t = s;
    while t.len > 0 && (t[0] == 'v' || t[0] == '=') { t = t[1..]; }
    let plus = find(t, "+");
    if plus >= 0 {
        if !build_form(t[plus + 1..]) { return r, false; }
        t = t[..plus];
    }
    var has_pre = false;
    let dash = find(t, "-");
    if dash >= 0 {
        let pre = t[dash + 1..];
        if pre.len == 0 || !pre_form(pre) { return r, false; }
        r.pre = pre;
        has_pre = true;
        t = t[..dash];
    }
    let parts = split(t, '.');
    if parts.len > 3 { return r, false; }
    if has_pre && parts.len < 3 { return r, false; }
    let a, oka = xpart(parts[0]);
    if !oka { return r, false; }
    var b: i64 = -1;
    var c: i64 = -1;
    if parts.len > 1 {
        let b2, okb = xpart(parts[1]);
        if !okb { return r, false; }
        b = b2;
    }
    if parts.len > 2 {
        let c2, okc = xpart(parts[2]);
        if !okc { return r, false; }
        c = c2;
    }
    // 1.x.3 and x.2 hold a number after an x. That is a fault.
    if (a < 0 && b >= 0) || (b < 0 && c >= 0) { return r, false; }
    r.mj = a;
    r.mn = b;
    r.pt = c;
    // The pre-release counts only after a full version.
    if c < 0 { r.pre = ""; }
    return r, true;
}

// split_op reads the operator at the front of s. It gives the kind (0
// compare, 1 caret, 2 tilde) and the operator text.
fn split_op(s: const u8[:]) -> i32, const u8[:] {
    if starts_with(s, "^") { return 1, "^"; }
    if starts_with(s, "~>") { return 2, "~>"; }
    if starts_with(s, "~") { return 2, "~"; }
    if starts_with(s, "<=") { return 0, "<="; }
    if starts_with(s, ">=") { return 0, ">="; }
    if starts_with(s, "<") { return 0, "<"; }
    if starts_with(s, ">") { return 0, ">"; }
    if starts_with(s, "=") { return 0, "="; }
    return 0, "";
}

// add writes one comparator into seg. The null set "<0.0.0-0" sets the
// flag instead. ">=0.0.0" matches all, so it is dropped. z adds the "-0"
// pre-release, the lowest one.
fn add(seg: u8[>..]&, nullset: bool&, op: const u8[:], ma: i64, mi: i64, pa: i64, pre: const u8[:], z: bool) {
    if op == "<" && ma == 0 && mi == 0 && pa == 0 && z { nullset = true; return; }
    if op == ">=" && ma == 0 && mi == 0 && pa == 0 && pre.len == 0 && !z { return; }
    if seg.len > 0 { seg.push(' '); }
    seg.append(op);
    format(seg, ma);
    seg.push('.');
    format(seg, mi);
    seg.push('.');
    format(seg, pa);
    if pre.len > 0 {
        seg.push('-');
        seg.append(pre);
    } else if z {
        seg.append("-0");
    }
}

// norm_token turns one range token into comparators in seg. pfx holds an
// operator that stood apart from the token ("> 1.2.3"), or is empty.
fn norm_token(seg: u8[>..]&, nullset: bool&, pfx: const u8[:], tok: const u8[:]) -> bool {
    var rest = tok;
    var kind: i32 = 0;
    var op: const u8[:] = "";
    if pfx.len > 0 {
        let k, o = split_op(pfx);
        kind = k;
        op = o;
    } else {
        let k, o = split_op(tok);
        kind = k;
        op = o;
        rest = tok[o.len..];
    }
    if op == "=" { op = ""; }
    let p, ok = parse_partial(rest);
    if !ok { return false; }
    let x_major = p.mj < 0;
    let x_minor = p.mn < 0;
    let x_patch = p.pt < 0;
    if x_major {
        // * matches all. > * and < * match nothing.
        if kind == 0 && (op == ">" || op == "<") { nullset = true; }
        return true;
    }
    if kind == 2 {
        // Tilde: the same minor, or the same major when no minor is given.
        if x_minor {
            add(seg, nullset, ">=", p.mj, 0, 0, "", false);
            add(seg, nullset, "<", p.mj + 1, 0, 0, "", true);
        } else if x_patch {
            add(seg, nullset, ">=", p.mj, p.mn, 0, "", false);
            add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true);
        } else {
            add(seg, nullset, ">=", p.mj, p.mn, p.pt, p.pre, false);
            add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true);
        }
        return true;
    }
    if kind == 1 {
        // Caret: nothing left of the first non-zero number may change.
        if x_minor {
            add(seg, nullset, ">=", p.mj, 0, 0, "", false);
            add(seg, nullset, "<", p.mj + 1, 0, 0, "", true);
        } else if x_patch {
            add(seg, nullset, ">=", p.mj, p.mn, 0, "", false);
            if p.mj == 0 {
                add(seg, nullset, "<", 0, p.mn + 1, 0, "", true);
            } else {
                add(seg, nullset, "<", p.mj + 1, 0, 0, "", true);
            }
        } else {
            add(seg, nullset, ">=", p.mj, p.mn, p.pt, p.pre, false);
            if p.mj > 0 {
                add(seg, nullset, "<", p.mj + 1, 0, 0, "", true);
            } else if p.mn > 0 {
                add(seg, nullset, "<", 0, p.mn + 1, 0, "", true);
            } else {
                add(seg, nullset, "<", 0, 0, p.pt + 1, "", true);
            }
        }
        return true;
    }
    // A plain comparator or an x-range.
    if op.len > 0 && x_patch {
        var o = op;
        var ma = p.mj;
        var mi: i64 = if x_minor { 0 } else { p.mn };
        if op == ">" {
            o = ">=";
            if x_minor { ma += 1; mi = 0; } else { mi += 1; }
        } else if op == "<=" {
            o = "<";
            if x_minor { ma += 1; } else { mi += 1; }
        }
        add(seg, nullset, o, ma, mi, 0, "", o == "<");
    } else if x_minor {
        add(seg, nullset, ">=", p.mj, 0, 0, "", false);
        add(seg, nullset, "<", p.mj + 1, 0, 0, "", true);
    } else if x_patch {
        add(seg, nullset, ">=", p.mj, p.mn, 0, "", false);
        add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true);
    } else {
        add(seg, nullset, op, p.mj, p.mn, p.pt, p.pre, false);
    }
    return true;
}

// norm_set turns one "||" alternative into comparators in seg.
fn norm_set(set: const u8[:], seg: u8[>..]&, nullset: bool&) -> bool {
    let toks = words(set);
    if toks.len == 3 && toks[1] == "-" {
        // A hyphen range: both ends are x-range versions.
        let a, oka = parse_partial(toks[0]);
        let b, okb = parse_partial(toks[2]);
        if !oka || !okb { return false; }
        if a.mj < 0 {
        } else if a.mn < 0 {
            add(seg, nullset, ">=", a.mj, 0, 0, "", false);
        } else if a.pt < 0 {
            add(seg, nullset, ">=", a.mj, a.mn, 0, "", false);
        } else {
            add(seg, nullset, ">=", a.mj, a.mn, a.pt, a.pre, false);
        }
        if b.mj < 0 {
        } else if b.mn < 0 {
            add(seg, nullset, "<", b.mj + 1, 0, 0, "", true);
        } else if b.pt < 0 {
            add(seg, nullset, "<", b.mj, b.mn + 1, 0, "", true);
        } else {
            add(seg, nullset, "<=", b.mj, b.mn, b.pt, b.pre, false);
        }
        return true;
    }
    var i = 0;
    while i < toks.len {
        let t = toks[i];
        let _, o = split_op(t);
        if o.len > 0 && o.len == t.len {
            // An operator that stands alone binds to the next token.
            if i + 1 >= toks.len { return false; }
            if !norm_token(seg, nullset, t, toks[i + 1]) { return false; }
            i += 2;
        } else {
            if !norm_token(seg, nullset, "", t) { return false; }
            i += 1;
        }
    }
    return true;
}

// normalize writes the range as strict comparators: sets joined by "||",
// comparators joined by a space. A range that matches every release gives
// the empty text. It returns false when the range is not valid.
fn normalize(out: u8[>..]&, range: const u8[:]) -> bool {
    let sets = split(range, "||");
    var all = false;
    var norm: u8[>..] = [];
    for set, i in sets {
        var seg: u8[>..] = [];
        var nullset = false;
        if !norm_set(set, seg, nullset) { return false; }
        if i > 0 { norm.append("||"); }
        if nullset {
            norm.append("<0.0.0-0");
        } else {
            norm.append(seg);
            if seg.len == 0 { all = true; }
        }
    }
    if all && sets.len > 1 { return true; }
    out.append(norm);
    return true;
}

// valid_range writes the strict form of the range into out, as the npm
// validRange does: "^1.2.3" gives ">=1.2.3 <2.0.0-0". A range that matches
// every release gives "*". It returns false when the range is not valid.
fn valid_range(out: u8[>..]&, range: const u8[:]) -> bool {
    var norm: u8[>..] = [];
    if !normalize(norm, range) { return false; }
    if norm.len == 0 { out.push('*'); } else { out.append(norm); }
    return true;
}

// satisfies returns true when the version matches the range. The range
// takes the npm forms: >, >=, <, <=, =, ^, ~, x-ranges, "a - b" and "||".
// A version with a pre-release matches only when a comparator of the same
// major, minor and patch carries a pre-release. A bad range matches
// nothing.
fn satisfies(v: Version, range: const u8[:]) -> bool {
    var norm: u8[>..] = [];
    if !normalize(norm, range) { return false; }
    let sets = split(norm, "||");
    for set in sets {
        if set_matches(v, set) { return true; }
    }
    return false;
}

// set_matches tests one set of strict comparators.
fn set_matches(v: Version, set: const u8[:]) -> bool {
    let comps = words(set);
    var pre_ok = false;
    for comp in comps {
        let _, op = split_op(comp);
        let cv, ok = parse(comp[op.len..]);
        if !ok { return false; }
        let c = compare(v, cv);
        var hit = false;
        if op == "" { hit = c == 0; }
        else if op == ">" { hit = c > 0; }
        else if op == ">=" { hit = c >= 0; }
        else if op == "<" { hit = c < 0; }
        else if op == "<=" { hit = c <= 0; }
        if !hit { return false; }
        if cv.pre.len > 0 && cv.major == v.major && cv.minor == v.minor && cv.patch == v.patch {
            pre_ok = true;
        }
    }
    // A pre-release version needs a comparator of its own major, minor and
    // patch that names a pre-release.
    if v.pre.len > 0 { return pre_ok; }
    return true;
}
