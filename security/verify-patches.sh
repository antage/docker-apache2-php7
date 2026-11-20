#!/bin/sh
# Verify that every patch in security/series still applies to the tree the
# Dockerfile builds, with no fuzz, and that the fix is actually present.
#
# The tree is rebuilt exactly the way the Dockerfile builds it: the official
# buster source package 7.3.31-1~deb10u7 (orig + debian/patches/series), then
# our patches in security/series order.
#
#   security/verify-patches.sh              fetch to .work/verify and check
#   KEEP=1 security/verify-patches.sh       keep the patched tree afterwards
#   WORK=/tmp/tree security/verify-patches.sh
set -eu

POOL="http://archive.debian.org/debian-security/pool/updates/main/p/php7.3"
ORIG="php7.3_7.3.31.orig.tar.xz"
DEBIAN="php7.3_7.3.31-1~deb10u7.debian.tar.xz"
ORIG_SHA256="d1aa8f44595d01ac061ff340354d95e146d6152f70e799b44d6b8654fb45cbcc"
DEBIAN_SHA256="54a61d282eee61599400be8cf7eb8eff3474ad8be20e84ba22aa9d80fef3907a"

SEC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK="${WORK:-$SEC/../.work/verify}"
mkdir -p "$WORK"
WORK=$(CDPATH= cd -- "$WORK" && pwd)   # patch -d needs absolute paths
CACHE="$WORK/cache"
TREE="$WORK/php7.3-7.3.31"
PATCH_OPTS="-p1 -N -t -s --fuzz=0 --no-backup-if-mismatch"
fails=0
checked=0

fetch() {
	[ -s "$CACHE/$1" ] && return 0
	mkdir -p "$CACHE"
	echo "downloading $1"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$CACHE/$1" "$POOL/$1"
	else
		wget -O "$CACHE/$1" "$POOL/$1"
	fi
}

marker() { # marker <file> <string>
	checked=$((checked + 1))
	if ! grep -Fq -- "$2" "$TREE/$1"; then
		echo "MISSING marker in $1: $2"
		fails=$((fails + 1))
	fi
}

nomarker() { # nomarker <file> <string>  (the pre-patch code must be gone)
	checked=$((checked + 1))
	if grep -Fq -- "$2" "$TREE/$1"; then
		echo "STILL PRESENT in $1: $2"
		fails=$((fails + 1))
	fi
}

# ---------------------------------------------------------------- build tree
fetch "$ORIG"
fetch "$DEBIAN"
printf '%s  %s\n%s  %s\n' "$ORIG_SHA256" "$ORIG" "$DEBIAN_SHA256" "$DEBIAN" |
	(cd "$CACHE" && sha256sum -c -)

rm -rf "$TREE"
mkdir -p "$WORK"
tar xf "$CACHE/$ORIG" -C "$WORK"
mv "$WORK/php-7.3.31" "$TREE"
tar xf "$CACHE/$DEBIAN" -C "$TREE"

for p in $(grep -v '^#' "$TREE/debian/patches/series" | grep -v '^[[:space:]]*$'); do
	if ! patch $PATCH_OPTS -d "$TREE" -i "$TREE/debian/patches/$p"; then
		echo "FAIL: debian patch $p does not apply with fuzz 0"
		exit 1
	fi
done
echo "debian series: applied"

# Every patch that ships in this directory has to be listed in the series.
for f in "$SEC"/CVE-*.patch; do
	if ! grep -q "^$(basename "$f")$" "$SEC/series"; then
		echo "NOT IN SERIES: $(basename "$f")"
		fails=$((fails + 1))
	fi
done

# ------------------------------------------------------------ our own series
while read -r p; do
	case "$p" in '' | '#'*) continue ;; esac
	printf '%-42s ' "$p"
	if ! patch $PATCH_OPTS -d "$TREE" -i "$SEC/$p"; then
		echo "FAIL: does not apply with fuzz 0"
		fails=$((fails + 1))
		continue
	fi
	case "$p" in
	CVE-2026-109618-109619-*)
		marker Zend/zend_alloc.c 'void zend_mm_safe_error_ex(const char *format, ...)'
		marker main/php_variables.c 'array_init_singleton(&gpc_element);'
		;;
	CVE-2026-15353-*)
		marker ext/soap/php_encoding.c 'return i != 0 ? i : 1;'
		;;
	CVE-2026-115560-*)
		marker ext/session/session.c '#define SESSION_CHECK_UPLOAD_PROGRESS_STATE'
		marker ext/session/session.c 'ps_globals->rfc1867_enabled = 0;'
		marker ext/session/session.c 'SESSION_CHECK_UPLOAD_PROGRESS_STATE;'
		;;
	CVE-2026-126714-*)
		marker ext/session/mod_files.c 'ftruncate() failed'
		nomarker ext/session/mod_files.c 'Truncate file if the amount of new data'
		;;
	CVE-2026-128064-*)
		marker ext/standard/http_fopen_wrapper.c 'zend_string_equals_literal_ci(resource->scheme, "https")'
		marker ext/standard/ftp_fopen_wrapper.c 'zend_string_equals_literal_ci(resource->scheme, "ftps")'
		nomarker ext/standard/http_fopen_wrapper.c "ZSTR_VAL(resource->scheme)[4] == 's'"
		nomarker ext/standard/ftp_fopen_wrapper.c "ZSTR_VAL(resource->scheme)[3] == 's'"
		;;
	CVE-2026-128090-*)
		marker ext/phar/util.c 'openssl public key found, but the signature does not use openssl'
		;;
	CVE-2026-129289-*)
		marker main/fastcgi.c 'if (UNEXPECTED(req->in_len != 0)) {'
		nomarker main/SAPI.c '} else if (SG(server_context)) {'
		;;
	CVE-2026-129291-*)
		marker sapi/fpm/fpm/fpm_children.c 'fpm_event_del(&child->ev_stdout);'
		marker sapi/fpm/fpm/fpm_children.c 'child->fd_stderr = -1;'
		;;
	CVE-2026-129292-*)
		marker sapi/fpm/fpm/fpm_status.c 'fpm_status_escape(proc.auth_user, encode, encode_json'
		marker sapi/fpm/fpm/fpm_status.c 'encode_json = 1;'
		nomarker sapi/fpm/fpm/fpm_status.c '? proc.script_filename : "-"'
		;;
	CVE-2026-129496-*)
		marker main/main.c 'error_time, PG(modules_activated) TSRMLS_CC);'
		nomarker main/main.c '!php_during_module_startup()'
		;;
	CVE-2026-129506-*)
		marker ext/soap/php_xml.c 'XML_DTD_NODE'
		;;
	CVE-2026-129538-*)
		marker sapi/cgi/cgi_main.c '(env_path_info && pilen > slen)'
		;;
	*)
		echo "no markers defined for $p"
		fails=$((fails + 1))
		;;
	esac
	echo "applied"
done < "$SEC/series"

[ -z "${KEEP:-}" ] && rm -rf "$WORK"

n=$(grep -v '^[[:space:]]*#' "$SEC/series" | grep -c '[[:graph:]]')
echo "markers checked: $checked, failures: $fails"
[ "$fails" -eq 0 ] || exit 1
echo "PASS: $n patches apply with fuzz 0 and all markers are present"