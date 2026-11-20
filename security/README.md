# Security patches

Source patches for the PHP that the `builder` stage compiles, plus the
ImageMagick policy that the runtime stage ships.

## How the patches are applied

`security/series` lists the patch files in application order (comments start
with `#`). The Dockerfile copies this directory into the builder stage and
appends every entry of `security/series` to `debian/patches/series`. The source
package format is `3.0 (quilt)`, so `dpkg-buildpackage` runs
`dpkg-source --before-build`, which - in the words of `dpkg-source(1)` -
"will ensure that all patches listed in the series file are applied": it
applies the patches that are in the series but not in `.pc/applied-patches`,
after the 76 patches of the buster package `7.3.31-1~deb10u7`.

`quilt`/`patch` accept fuzz by default, so a patch that no longer matches the
7.3 tree can still apply silently in the wrong place. That is what
`security/verify-patches.sh` guards against.

## Verifying

    security/verify-patches.sh

The script rebuilds the tree the same way the Dockerfile does (it downloads the
same two tarballs, checks their sha256, applies the Debian series, then ours),
applies every patch in `security/series` with `--fuzz=0`, and after each patch
checks that its fix markers are present and the pre-patch code is gone. It also
fails if a `CVE-*.patch` file exists here but is not listed in the series.
Environment: `WORK=<dir>` (default `.work/verify`), `KEEP=1` keeps the tree.

Last run: `PASS: 12 patches apply with fuzz 0 and all markers are present`,
`markers checked: 24, failures: 0`.

Compile check of the whole batch (2026-11-20, host gcc 16.2): all 13
translation units the patches touch compile clean -
`main/main.c`, `main/SAPI.c`, `main/fastcgi.c`, `ext/session/session.c`,
`ext/session/mod_files.c`, `ext/standard/http_fopen_wrapper.c`,
`ext/standard/ftp_fopen_wrapper.c`, `ext/phar/util.c`, `ext/soap/php_xml.c`,
`ext/soap/php_encoding.c`, `sapi/cgi/cgi_main.c`,
`sapi/fpm/fpm/fpm_status.c`, `sapi/fpm/fpm/fpm_children.c` - no errors, no new
warnings. The full `make` on the host does not link: PHP 7.3 does not build
against a current glibc/libxml2 (`main/reentrancy.c` `readdir_r`, implicit
declarations in `ext/date/php_date.c` and `ext/standard/scanf.c`, libxml2 API
drift in `ext/libxml/libxml.c`). Those four files are not touched by any patch
here; the real build is the buster container.

## 2026-11-19 batch

php.net released a coordinated critical fix set on 2026-11-19 (8.2.36, 8.3.37,
8.4.28, 8.5.13, 17 advisories). 12 advisories cover the "before 8.2" line that
our 7.3.31 belongs to; 7.3 is EOL upstream, so each fix is a manual port of the
php-src commit that landed in 8.2.36. The upstream `.phpt` tests are not carried
over - they use `zend_test` and 8.x-only features.

| patch | CVE | sev | what it fixes |
|---|---|---|---|
| `CVE-2026-15353-php73.patch` | CVE-2026-15353 | medium | SOAP: out-of-bounds heap read on an empty/invalid `SOAP-ENC:arraySize` |
| `CVE-2026-115560-php73.patch` | CVE-2026-115560 | critical | session: `session.upload_progress` writes with one serializer and reads with another (RCE with a gadget chain) |
| `CVE-2026-126714-php73.patch` | CVE-2026-126714 | critical | session `files` handler: an interrupted write left two serialized sessions concatenated (RCE) |
| `CVE-2026-128064-php73.patch` | CVE-2026-128064 | high | `HTTPS://`/`FTPS://` with an uppercase `S` silently used the plain transport |
| `CVE-2026-128090-php73.patch` | CVE-2026-128090 | high | phar: switching the signature type to a keyless hash bypassed an OpenSSL signature |
| `CVE-2026-129289-php73.patch` | CVE-2026-129289 | critical | request smuggling: unread request body reinterpreted as the next FastCGI request |
| `CVE-2026-129291-php73.patch` | CVE-2026-129291 | high | FPM master: epoll event for a freed worker record when `catch_workers_output` is on (local root) |
| `CVE-2026-129292-php73.patch` | CVE-2026-129292 | medium | FPM `status` page: request method, Basic-auth user and script filename inserted unescaped |
| `CVE-2026-129496-php73.patch` | CVE-2026-129496 | critical | use-after-free of the date extension timezone cache when an error log line is written during startup |
| `CVE-2026-129506-php73.patch` | CVE-2026-129506 | medium | SOAP: DTD freed while attribute-value entity references still point into it |
| `CVE-2026-129538-php73.patch` | CVE-2026-129538 | medium | CGI: `PATH_INFO` underflow in `init_request_info()` with `cgi.fix_pathinfo=1` |

Upstream commits (php-src, all in the 8.2.36 tag): 59e46404a744, 3f70f6661158,
41c0941ae27d, cb68a63e8177, 7050cf338092, 28014fd092c7, 8c38b7914497,
1ecb92f2cdeb, f986c5ca37c0, 66db5cda7df3, 964cdcfa5adf.

### Not ported

- CVE-2026-127960 (folded HTTP response headers, quadratic concatenation) - the
  accumulation loop it fixes does not exist in 7.3: buster's
  `http_fopen_wrapper.c` still reads headers line by line into a fixed buffer
  and never rebuilds the value string. That old code is the behaviour
  CVE-2025-1217 addressed, a separate and older issue.
- CVE-2026-129481 (8.3+, session script-filename field; the advisory states 8.2
  is not affected), CVE-2026-129501 (`Dom\XMLDocument`, 8.4+), CVE-2026-129474
  and CVE-2026-129182 (engine, 8.5+), CVE-2026-129438 (`ext-uri`, 8.5+). None
  of that code exists in 7.3.

### Port notes

- 4 patches apply to 7.3 unchanged: CVE-2026-15353, CVE-2026-129289,
  CVE-2026-129291, CVE-2026-129538.
- CVE-2026-128090: 7.3 has one OpenSSL signature type, so the guard reads
  `sig_type != PHAR_SIG_OPENSSL`; the flag is a `zend_bool`.
  `php_stream_stat_path_ex()` is a macro in 7.3 and takes no `TSRMLS_CC`.
- CVE-2026-129496: 7.3 has a ZTS/NTS split at that spot instead of one call;
  the call keeps `TSRMLS_CC`, and local time is enabled by
  `PG(modules_activated)` alone - without the upstream `EG(active)` term, which
  would move request-shutdown log timestamps to GMT.
- CVE-2026-115560: the `SESSION_CHECK_UPLOAD_PROGRESS_STATE` guard is inserted
  in front of all 12 `SESSION_CHECK_ACTIVE_STATE` checks of the session INI
  setters (a superset of the upstream list), and
  `PHP_GINIT_FUNCTION(ps)` sets `rfc1867_enabled = 0`. The 2026-10 patch already
  disables the RFC1867 callback outright, so this is a second layer.
- CVE-2026-129292: 7.3 escaped only the query string and only for HTML/XML, the
  JSON output had no escaping at all. The patch adds `fpm_status_escape()` plus
  a JSON encoder and runs method, URI, query string, auth user and script
  filename through them.
- CVE-2026-128064: the `resource->scheme` NULL guard is kept in both wrappers.

## 2026-10-21 batch: CVE-2026-109618 / CVE-2026-109619

php.net advisory (July 2026): two memory-error-handling vulnerabilities, both
leading to RCE when a PHP process handles a request (apache2 mod_php, fpm,
cli):

- **CVE-2026-109618** - RCE via OOM: exhausting memory during a request
  (including GPC/multipart input parsing) triggered `zend_bailout()` - a
  longjmp out of partially initialized request state; the shutdown path then
  ran over corrupted global state.
- **CVE-2026-109619** - RCE via stale global state: after request shutdown,
  dangling pointers remained in the executor/SAPI/ini layer
  (`EG(exception)`, user error/exception handlers, `SG(request_info)`,
  `PG(http_globals)`, etc.), usable by the next request or by shutdown code.

The php.net fix is a minimal source backport released only for the 7.4/8.0/8.1
branches (commit `712e60f9ed`, branch `PHP-7.4-CVE-2026-109618-109619`); the
patch here is a manual port of it onto 7.3.31.

### What it changes (18 files)

- `Zend/zend_alloc.c/.h` - `zend_mm_panic`/`zend_out_of_memory` to `_Exit(1)`;
  new `zend_mm_safe_error_ex()` (prints `Fatal error: ... in <file> on line
  <n>` and exits without longjmp); all 5 integer-overflow points of the
  allocator routed through it.
- `Zend/zend_vm_execute.h`, `Zend/zend_vm_def.h` - integer-overflow guards at
  38 CONCAT alloc/extend sites.
- `Zend/zend_string.h` - `ZSTR_MAX_LEN`/`ZSTR_MAX_OVERHEAD` (in 7.4 before the
  backport, absent in 7.3).
- `Zend/zend_hash.c/.h`, `Zend/zend_API.h` - `zend_new_array_singleton()` /
  `array_init_singleton()` + 4 overflow points.
- `Zend/zend_types.h` - `HT_HASH_RESET` memset fallback for size < 64.
- `Zend/zend_llist.c` - `head`/`tail` set to NULL after destroy.
- `Zend/zend_multiply.h`, `Zend/zend_strtod.c` - overflow/OOM points routed
  through `zend_mm_safe_error_ex`.
- `Zend/zend_execute_API.c` - `shutdown_executor` resets `EG(exception)` and
  `EG(error_handling)`; in the fast_shutdown branch the objects store is
  restored and the user error/exception handlers are zeroed.
- `main/SAPI.c` - `SG(request_info)` set to NULL after efree.
- `main/main.c` - `PG(http_globals)` to `ZVAL_UNDEF` on dtor,
  `PG(modules_activated) = 0`.
- `main/php_variables.c` - `array_init_singleton` on the GPC path.
- `ext/session/session.c` - RFC1867 upload progress tracking disabled
  (`|| 1`), as in the official backport.
- `main/rfc1867.c` - multipart headers: only Content-Disposition/Content-Type
  are kept, duplicates ignored; `substring_conf` on `size_t`.

### Verified (2026-10-22, gcc 16 / gnu89)

- Build: `./configure --disable-all --enable-cli` + `make` - success, all 18
  changed files compiled.
- A/B OOM test (same configure, `memory_limit=2M`, `str_repeat(3MB)`, a
  `register_shutdown_function` writing a marker):

  | | exit code | shutdown function |
  |---|---|---|
  | unpatched | 255 (longjmp bailout) | **ran** (the vulnerable path) |
  | patched | 1 (`_Exit(1)`) | **did not run** |

- Regressions: plain scripts, concatenation of two 16MB strings, uncaught
  exception - identical behaviour; the shutdown handler still runs on a regular
  fatal.

### Deviations from the official 7.4 backport

- `ZSTR_MAX_LEN`/`ZSTR_MAX_OVERHEAD` added to `zend_string.h` (7.3 lacked them).
- `EG(user_error_handlers)`/`EG(user_exception_handlers)` are `zend_stack` in
  7.3 (`zend_long`/`HashTable*` in 7.4): reset with `memset` to the
  pre-`init_executor` state, plus the `EG(user_error_handler_error_reporting)`
  field that 7.4 does not have.
- `EG(prev_exception)` does not exist in 7.3 - only `EG(exception)` is reset.
- Slow-path (tail) CONCAT allocs are left unguarded, exactly as in the official
  7.4 backport: they run after `SAVE_OPLINE` with a fully initialized executor.
- The 7.3 CONST_CONST FAST_CONCAT handler exists in both `zend_vm_execute.h`
  and `zend_vm_def.h` (COLD_CONSTCONST) - both are guarded.
- The `max_multipart_body_parts` INI is already in buster 7.3.31 (a Debian
  backport), so it is not added here.

### Behaviour changes in the built PHP

- OOM and integer overflow in the allocator and in the fast-path CONCAT allocs
  terminate the process with `_Exit(1)` and one
  `Fatal error: ... in <file> on line <n>` line: no longjmp, no shutdown. That
  is the fix.
- Regular fatal errors keep working (longjmp + shutdown, exit 255).
- `session.upload_progress` is disabled; multipart parsing keeps only
  Content-Disposition/Content-Type.
- `ps_files_write()` truncates the session file before every write and gives up
  with a warning if `ftruncate()` fails, instead of writing over the old
  contents (2026-11 batch).

## ImageMagick policy

`imagemagick-policy.xml` replaces `/etc/ImageMagick-6/policy.xml` in the
runtime stage. The image installs `imagemagick`, `libmagickcore-6.q16-6-extra`
and `ghostscript`, and PHP talks to the same library through `php-imagick`, so
the vector/delegate formats are reachable from application code. The file is
buster's own policy plus these rules:

```xml
<policy domain="coder" rights="none" pattern="{MSL,MVG,MSVG,SVG,DOT,GV,PCL}" />
<policy domain="delegate" rights="none" pattern="{SVG,MSVG,svg,msvg,svg:decode}" />
<policy domain="delegate" rights="none" pattern="{PS,PS2,PS3,EPS,PDF,XPS,PCL}" />
<policy domain="delegate" rights="none" pattern="{ps,ps2,ps3,eps,pdf,xps,pcl}" />
<policy domain="delegate" rights="none" pattern="{gs,gxps,pcl6,rsvg-convert,inkscape,uniconvertor,dot}" />
```

buster already denies the PS/PS2/PS3/EPS/PDF/XPS coders, the URL/HTTP/HTTPS
delegates and the `@*` path. The additions close the rest of the ImageTragick
class of issues (CERT/CC VU#580079): the script/vector coders (`MSL` can write
and delete files, `MVG`/`MSVG` render through the internal parser) and the
external programs those formats delegate to - `ghostscript` is installed and
buster's `delegates.xml` routes `svg` to `rsvg-convert` and `svg:decode` to
`inkscape`.

Why the patterns look like that (checked in the buster 6.9.10-23 sources):

- `IsRightsAuthorized()` (`magick/policy.c`) matches with
  `GlobExpression(pattern, p->pattern, MagickFalse)` - case-sensitive, last
  match wins, no match means allowed. Brace sets are handled by
  `GlobExpression()` itself (`magick/token.c`).
- The expression is the canonical format name, which is always uppercase
  (`SVG`, `PS`); a user-typed `SvG:`/`x.SvG` is folded to uppercase before the
  check, so mixed case cannot slip through.
- A delegate is checked twice: by the decode/encode token in `InvokeDelegate()`
  (uppercase for format-level calls such as `read_info->magick`, lowercase
  tokens such as `svg:decode` inside coders) and by the executable name in
  `ExternalDelegateCommand()` - the latter is the only check that catches the
  SVG path, because `coders/svg.c` calls `ExternalDelegateCommand()` directly.

Smoke test of the semantics (host ImageMagick 7.1.2, not the buster build):
`png -> jpg` passes, `svg`, `SvG` and `ps` are refused with `not authorized by
the security policy`.

Behaviour change: applications in this image can no longer read SVG, MVG, MSL,
PCL or DOT/GV, and cannot delegate to gs/rsvg-convert/inkscape. Raster formats
(PNG/JPEG/GIF/WebP/TIFF) are unaffected. If an application really needs SVG,
drop the `{SVG,MSVG}` entries from the coder rule and the `rsvg-convert` /
`inkscape` names from the delegate rule.