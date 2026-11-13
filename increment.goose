// The inc call of the semver package: bump a version, with a pre-release.
//
namespace semver;

import std;

// pre_bump writes the next pre-release into out, as the npm "pre" step
// does. base is 0 or 1 for the first number, or -1 for none. It returns
// false when the identifier already is the whole pre-release and base is -1.
// bump_number writes one added to a digit string into next. The digits
// come out in order, and a longer number stays exact.
fn pre_bump(out: u8[>..]&, pre: const u8[:], ident: const u8[:], base: i64) -> bool {
    let b: i64 = if base > 0 { 1 } else { 0 };
    var next: u8[>..] = [];
    if pre.len == 0 {
        format(next, b);
    } else {
        let parts = split(pre, '.');
        // npm bumps the last identifier that reads as a number below its
        // limit. A larger one stays a text, and the base number follows it.
        var last_num: i64 = -1;
        for part, i in parts {
            if is_numeric(part) {
                let n, ok = parse_num(part);
                if ok && n < MAX_NUMBER { last_num = i; }
            }
        }
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
    var ma = v.major;
    var mi = v.minor;
    var pa = v.patch;
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
