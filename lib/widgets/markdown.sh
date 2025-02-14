# This requires the 'cmark' or 'cmark-gfm' command, which is most
# likely available as a package for your Linux distro.
#
if type -P cmark-gfm >/dev/null 2>&1; then
    cmark () {
        cmark-gfm -e tasklist      \
                  -e tagfilter     \
                  -e strikethrough \
                  "$@"
        # See https://github.github.com/gfm/ for details on the extensions enabled.
    }
fi

markdown () { # <markdown-text>
    local html; html=$(
        cmark --hardbreaks --to html <<<"$*"
    ) || err-return
    print "${html//$'\n'/\&#10;}"
}
