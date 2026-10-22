# PHP security patches

PHP core patches for the images in this repository. The one used by the `7.3`
branch is `CVE-2026-109618-109619-php73.patch`; it is pulled into the build by
the `Dockerfile` (the `builder` stage, appended as the last entry of
`debian/patches/series`).

## CVE-2026-109618 / CVE-2026-109619

php.net advisory (July 2026): two memory-error-handling vulnerabilities, both
leading to RCE when a PHP process handles a request (apache2 mod_php, fpm,
cli):

- **CVE-2026-109618** — RCE via OOM: exhausting memory during a request
  (including GPC/multipart input parsing) triggered `zend_bailout()` — a
  longjmp out of partially initialized request state; the shutdown path then
  ran over corrupted global state.
- **CVE-2026-109619** — RCE via stale global state: after request shutdown,
  dangling pointers remained in the executor/SAPI/ini layer
  (`EG(exception)`, user error/exception handlers, `SG(request_info)`,
  `PG(http_globals)`, etc.), usable by the next request or by shutdown code.

The php.net fix is a minimal source backport released only for the 7.4/8.0/8.1
branches (commit `712e60f9ed`, branch `PHP-7.4-CVE-2026-109618-109619`).
7.3 is EOL upstream and has no official backport — the patch below is a manual
port of the official 7.4 patch onto 7.3.31.

## File

`CVE-2026-109618-109619-php73.patch` — the 7.3 port (18 files), used by the
`Dockerfile` of the `7.3` branch. Ported from the official 7.4 backport
(php.net, commit `712e60f9ed`); the backport itself is not committed to this
repo.

## Source

Debian buster source package `php7.3 7.3.31-1~deb10u7`
(`archive.debian.org/debian-security/pool/updates/main/p/php7.3/`):

```
d1aa8f44595d01ac061ff340354d95e146d6152f70e799b44d6b8654fb45cbcc  php7.3_7.3.31.orig.tar.xz
54a61d282eee61599400be8cf7eb8eff3474ad8be20e84ba22aa9d80fef3907a  php7.3_7.3.31-1~deb10u7.debian.tar.xz
73980a331e35057b5325b3fb5f85d616286f603122ff5fce2a9dd8a8cd53fbe5  php7.3_7.3.31-1~deb10u7.dsc
```

The dsc carries an inline PGP signature; the uploader key is not present in a
fresh container, so `dpkg-source -x` refuses it. That is why the Dockerfile
unpacks the orig and debian tarballs manually.

## How it is applied (Dockerfile, builder stage)

1. `tar xJf php7.3_7.3.31.orig.tar.xz && mv php-7.3.31 php7.3-7.3.31`
   + `tar xJf ...debian.tar.xz -C php7.3-7.3.31` (manual unpack, see above)
2. `cp CVE-2026-109618-109619-php73.patch debian/patches/`
3. `echo "CVE-2026-109618-109619-php73.patch" >> debian/patches/series`
4. `dpkg-buildpackage -us -uc -b -d -j$(nproc)` (3.0 (quilt) applies the series
   itself; `-d` skips the test Build-Depends check (locales-all and friends))

The patch is in git format and applies with `git apply -p1` / `quilt push`
from the root of the `php7.3-7.3.31/` tree.

## What the patch changes (18 files)

- `Zend/zend_alloc.c/.h` — `zend_mm_panic`/`zend_out_of_memory` → `_Exit(1)`;
  new `zend_mm_safe_error_ex()` (prints `Fatal error: ... in <file> on line
  <n>` and immediately calls `_Exit(1)` without longjmp); all 5
  integer-overflow points in the allocator (mm_alloc_heap, mm_alloc_huge,
  estrdup/estrndup/strndup) routed through it.
- `Zend/zend_vm_execute.h`, `Zend/zend_vm_def.h` — integer-overflow guards at
  38 alloc/extend sites of the CONCAT family (17 handlers × 2 in
  zend_vm_execute.h, 2 handlers × 2 in zend_vm_def.h).
- `Zend/zend_string.h` — `ZSTR_MAX_LEN`/`ZSTR_MAX_OVERHEAD` macros (present in
  7.4 before the backport, absent in 7.3 — added).
- `Zend/zend_hash.c/.h` — `zend_new_array_singleton()` + 4 overflow points.
- `Zend/zend_API.h` — `array_init_singleton()`.
- `Zend/zend_types.h` — `HT_HASH_RESET`: memset fallback for size < 64.
- `Zend/zend_llist.c` — `head`/`tail` set to NULL after destroy.
- `Zend/zend_multiply.h`, `Zend/zend_strtod.c` — overflow/OOM points routed
  through `zend_mm_safe_error_ex`.
- `Zend/zend_execute_API.c` — in `shutdown_executor`: reset `EG(exception)` /
  `EG(error_handling)`; in the fast_shutdown branch — objects_store restored
  to the pre-`init_executor` state, user error/exception handlers zeroed.
- `main/SAPI.c` — `SG(request_info)` set to NULL after efree.
- `main/main.c` — `PG(http_globals)` → `ZVAL_UNDEF` on dtor,
  `PG(modules_activated) = 0`.
- `main/php_variables.c` — `array_init_singleton` on the GPC path.
- `ext/session/session.c` — RFC1867 upload progress tracking disabled
  (`|| 1`), as in the official backport.
- `main/rfc1867.c` — multipart headers: only Content-Disposition/Content-Type
  are kept, duplicates ignored; `substring_conf` on `size_t`.

## Verified (2026-10-22, Arch sandbox, gcc 16 / gnu89)

- **Build**: `./configure --disable-all --enable-cli` + `make` — success
  (core + cli; all 18 changed files compiled).
- **A/B OOM test** (same configure for both binaries; script with
  `memory_limit=2M`, `str_repeat(3MB)` and a `register_shutdown_function`
  writing a marker):

  | | exit code | shutdown function |
  |---|---|---|
  | unpatched | 255 (longjmp bailout) | **ran** (the vulnerable path) |
  | patched | 1 (`_Exit(1)`) | **did not run** |

- **Regressions**: plain scripts, concatenation of two 16MB strings, uncaught
  exception (fatal without OOM) — behavior identical; shutdown on a regular
  fatal still works with the patch.
- **Full `dpkg-buildpackage` in a buster container** — not run in the sandbox
  (no docker); covered by the host `make` build. All 18 files compile in the
  sandbox; the remaining risk is packaging mechanics only (rules/debian files
  untouched).

## Behavior changes in the built PHP

- OOM / integer overflow in the allocator and in fast-path CONCAT allocs —
  immediate process termination via `_Exit(1)` with a
  `Fatal error: ... in <file> on line <n>` line. No longjmp, no shutdown
  (this is the RCE fix itself).
- Regular fatal errors (not OOM) work as before: longjmp + shutdown, exit 255.
- `session.upload_progress` (RFC1867 progress tracking) is effectively
  disabled.
- The multipart parser keeps only Content-Disposition/Content-Type.
- `zend_new_array_singleton`: GPC arrays start with a single slot (an 8.x
  micro-optimization, part of the backport).

## Deviations from the official 7.4 backport

- `ZSTR_MAX_LEN`/`ZSTR_MAX_OVERHEAD` added to `zend_string.h` (in 7.4 they
  predated the backport; 7.3 lacked them).
- In 7.3 `EG(user_error_handlers)`/`EG(user_exception_handlers)` are
  `zend_stack` (in 7.4 — `zend_long`/`HashTable*`): reset via `memset` to zero
  (the pre-`init_executor` state), plus the `EG(user_error_handler_error_reporting)`
  field, which does not exist in 7.4.
- `EG(prev_exception)` does not exist in 7.3 — only `EG(exception)` is reset
  (mirroring what the 7.4 fix does for its own state).
- Slow-path (tail) CONCAT allocs (9 sites in `zend_vm_execute.h` + 1 in
  `zend_vm_def.h`) are left unguarded — **exactly like the official 7.4
  backport**, which guards only the fast-path extend/alloc pairs; the tail
  allocs run after SAVE_OPLINE with a fully initialized executor.
- The 7.3 CONST_CONST FAST_CONCAT handler exists in both `zend_vm_execute.h`
  and `zend_vm_def.h` (COLD_CONSTCONST) — both are guarded (in 7.4 it exists
  only in zend_vm_def.h).
- The `max_multipart_body_parts` INI is already present in buster 7.3.31 (a
  Debian backport) — not added by this patch.
- `isspace(*value)` in rfc1867.c keeps the 7.3 form without a cast (the 7.4
  cast is a separate change, outside the backport scope).
