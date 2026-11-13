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
import range_text;
import range_subset;
import range_outside;
import increment;

// MAX_NUMBER is the largest number that the package holds. It is the
// largest number that npm semver holds, 9007199254740991.
const MAX_NUMBER: i64 = 9007199254740991;

// MAX_LENGTH is the longest text that parse reads. npm refuses a longer
// text before it trims the text.
const MAX_LENGTH: i64 = 256;

// Version holds one version. The pre-release and the build metadata are
// slices into the string that the parse read, so they stay valid only as
// long as that string.
struct Version {
    major: i64,
    minor: i64,
    patch: i64,
    pre: const u8[:],
    build: const u8[:],
}


// RangeOpts holds the options of the range calls. The zero value gives
// the behaviour of npm without options.
struct RangeOpts {
    include_prerelease: bool,
}
// parse reads one version. It returns false when the text is not a
// version in the SemVer form. The pre-release and the build fields of the
// result refer to the input.
fn parse(s: const u8[:]) -> Version, bool {
    var v = Version { major: 0, minor: 0, patch: 0, pre: "", build: "" };
    if s.len > MAX_LENGTH { return v, false; }

    // The text may hold a leading v and space around it. npm reads both.
    var text = trim(s);
    if text.len > 0 && text[0] == 'v' { text = text[1..]; }

    // The build metadata starts at the first '+' and is not part of the
    // comparison.
    var core = text;
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
fn parse_num(s: const u8[:]) -> i64, bool {
    if s.len == 0 { return 0, false; }
    var n: i64 = 0;
    for c in s {
        if c < '0' || c > '9' { return 0, false; }
        if n > (MAX_NUMBER - (c - '0')) / 10 { return 0, false; }
        n = n * 10 + (c - '0');
    }
    return n, true;
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
    if a.major != b.major { return if a.major < b.major { -1 } else { 1 }; }
    if a.minor != b.minor { return if a.minor < b.minor { -1 } else { 1 }; }
    if a.patch != b.patch { return if a.patch < b.patch { -1 } else { 1 }; }
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
        // One rule for all parts: a number comes before a text, two
        // numbers compare by value, and two texts compare byte by byte.
        let order = compare_identifiers(ap, bp);
        if order != 0 { return order; }
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

// compare_text compares two version texts. It gives -1, 0 or 1. It gives
// 0 for a text that holds no version.
fn compare_text(a: const u8[:], b: const u8[:]) -> i64 {
    let va, oka = parse(a);
    let vb, okb = parse(b);
    if !oka || !okb { return 0; }
    return compare(va, vb);
}

// compare_bytes compares two parts byte by byte. The shorter one comes
// first when one is a prefix of the other.
fn compare_bytes(a: const u8[:], b: const u8[:]) -> i64 {
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
    var t = trim(s);
    while t.len > 0 && (t[0] == '=' || t[0] == 'v') { t = t[1..]; }
    return valid(out, t);
}

// valid gives the version text of npm into out. It gives false when the
// text holds no version.
fn valid(out: u8[>..]&, s: const u8[:]) -> bool {
    let v, ok = parse(s);
    if !ok { return false; }
    write_core(out, v);
    return true;
}

// major gives the major number of the text. It gives false when the text
// holds no version.
fn major(s: const u8[:]) -> i64, bool {
    let v, ok = parse(s);
    if !ok { return 0, false; }
    return v.major, true;
}

// minor gives the minor number of the text. It gives false when the text
// holds no version.
fn minor(s: const u8[:]) -> i64, bool {
    let v, ok = parse(s);
    if !ok { return 0, false; }
    return v.minor, true;
}

// patch gives the patch number of the text. It gives false when the text
// holds no version.
fn patch(s: const u8[:]) -> i64, bool {
    let v, ok = parse(s);
    if !ok { return 0, false; }
    return v.patch, true;
}

// major_text writes the major number of the text into out, as the Go
// Masterminds/semver Major text. It gives false, with out untouched, when
// the text holds no version.
fn major_text(out: u8[>..]&, s: const u8[:]) -> bool {
    let v, ok = parse(s);
    if !ok { return false; }
    format(out, v.major);
    return true;
}

// major_minor_text writes "major.minor" of the text into out, as the Go
// Masterminds/semver MajorMinor text. It gives false, with out untouched,
// when the text holds no version.
fn major_minor_text(out: u8[>..]&, s: const u8[:]) -> bool {
    let v, ok = parse(s);
    if !ok { return false; }
    format(out, v.major);
    out.push('.');
    format(out, v.minor);
    return true;
}

// prerelease writes the parts of the pre-release of the text into the
// list. It gives false when the text holds no version or no
// pre-release.
fn prerelease(parts: const u8[:][>..]&, s: const u8[:]) -> bool {
    let v, ok = parse(s);
    if !ok { return false; }
    if v.pre.len == 0 { return false; }
    let got = split(v.pre, '.');
    var i = 0;
    while i < got.len {
        parts.push(got[i]);
        i += 1;
    }
    return true;
}

// cmp compares two texts with the operator. It gives false for a bad
// text or an operator that npm refuses.
fn cmp(a: const u8[:], op: const u8[:], b: const u8[:]) -> bool {
    // The operators "===" and "!==" compare the text itself, as npm does.
    // npm reads them without a parse.
    if op == "===" { return a == b; }
    if op == "!==" { return a != b; }
    let va, oka = parse(a);
    let vb, okb = parse(b);
    if !oka || !okb { return false; }
    let c = compare(va, vb);
    if op == "" || op == "=" || op == "==" { return c == 0; }
    if op == "!=" { return c != 0; }
    if op == ">" { return c > 0; }
    if op == ">=" { return c >= 0; }
    if op == "<" { return c < 0; }
    if op == "<=" { return c <= 0; }
    return false;
}

// rcompare gives the reverse of the order of two texts. It gives -1, 0
// or 1.
fn rcompare(a: const u8[:], b: const u8[:]) -> i64 {
    return -compare_text(a, b);
}

// compare_identifiers compares two pre-release parts. It gives -1, 0
// or 1. A number comes before a text, and two numbers compare by
// value. A number of any length compares right.
fn compare_identifiers(a: const u8[:], b: const u8[:]) -> i64 {
    let an = is_numeric(a);
    let bn = is_numeric(b);
    if an && bn { return compare_numbers(a, b); }
    if an { return -1; }
    if bn { return 1; }
    return compare_bytes(a, b);
}

// rcompare_identifiers gives the reverse of the order of two pre-release
// parts. It gives -1, 0 or 1.
fn rcompare_identifiers(a: const u8[:], b: const u8[:]) -> i64 {
    return -compare_identifiers(a, b);
}

// compare_loose compares two texts as npm compareLoose does, with the
// strict parse. It gives -1, 0 or 1, and 0 for a text that parse
// refuses. See the limits.
fn compare_loose(a: const u8[:], b: const u8[:]) -> i64 {
    return compare_text(a, b);
}
