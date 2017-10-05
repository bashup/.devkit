#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; [[ "${BASHPACKR_LOADED-}" ]] || source "$(command -v bashpackr)"; eval "$(sed -ne '/^```shell$/,/^```$/{/^```/d; p}' "$BASH_SOURCE")"; return $? # -->

# dk - the devkit CLI

`dk` is a specialized version of [loco](https://github.com/bashup/loco), that uses a `.dkrc` file to designate the project directory, define commands, etc.  It extends loco to:

* provide skeleton implementations of [Scripts to Rule Them All](https://githubengineering.com/scripts-to-rule-them-all/) commands
* provide a self-installing, local [basher](https://github/basherpm/basher) instance for installing dependencies
* provide various convenience functions for detecting and fetching dependencies
* provide an `import:` shim that allows importing devkit modules even if [bashpackr](https://github.com/bashup/bashpackr) isn't available

## Scripts To Rule Them All

dk provides skeletons for all the "Scripts to Rule Them All" commands, which can be overridden in the project's `.dkrc` file.  The defaults all do nothing, or abort with an error message, but `import:` ing other devkit modules or redefining the functions can change that:

```shell
dk.bootstrap() { :; }
dk.setup()     { dk bootstrap; }
dk.update()    { dk bootstrap; }
dk.cibuild()   { dk test; }
dk.clean()     { [[ "$BASHER_PREFIX" == "$PWD/.deps" ]] && rm -rf "$BASHER_PREFIX"; hash -r; }

dk.server()  { undefined-command server; }
dk.test()    { undefined-command test; }
dk.console() { undefined-command console; }

undefined-command() {
    abort "This project does not have a $1 command defined." 69   # EX_UNAVAILABLE
}
abort()    { log "$1"; exit $2; }
log()      { echo "$1" >&2; }
```

## Dependency Management Functions

### basher

For use in `.dkrc` commands, we provide an auto-installing wrapper function for  `basher`, that installs it locally if needed.

```shell
basher() {
    require basher github basherpm/basher master bin/basher
    "$BASHER_INSTALL_BIN/basher" "$@"
}

```

### github

Not everything is installable with basher, of course, and basher itself needs to be installed via github.  So we have a `github` *user/repo [ref [bin1 bin2...]]* function, which clones the desired repo under `.deps` (if it's not already there) and links the named files to `.deps/bin`.  The *ref* can be a branch or tag; it defaults to `master` if unspecified.

```shell
github() {
    [[ -d "$BASHER_PACKAGES_PATH/$1/.git" ]] && return
    mkdir -p "$BASHER_PACKAGES_PATH/$1"
    git clone -q --depth=1 -b "${2:-master}" "https://github.com/$1" "$BASHER_PACKAGES_PATH/$1"
    local bin; for bin in "${@:3}"; do linkbin "$BASHER_PACKAGES_PATH/$1/$bin"; done
}
```

### linkbin and catbin

If you need to link something under a different name than the original, you can use `linkbin` *fullpath newname* instead of an extra argument to `github`.  But you have to provide the *full* path to the source, not just the path within a repository.  You can also use `catbin` *cmdname* *files...* to create an executable file in `.deps/bin`, either passing it files or piping it text via standard input.

```shell
linkbin() {
    mkdir -p "$BASHER_INSTALL_BIN"
    relative-symlink "$1" "$BASHER_INSTALL_BIN/${2:-${1##*/}}"
    unhash "${2:-${1##*/}}"
}

catbin() {
    cat "${@:2}" >"$BASHER_INSTALL_BIN/$1"
    chmod +x "$BASHER_INSTALL_BIN/$1"
    unhash "$1"
}

unhash() { hash -d "$@" || true; } 2>/dev/null

```

### have, require, have-any, require-any

To help decide whether dependencies are needed, we offer the `have`/`require`  and `have-any`/`require-any` functions.  The plain varieties check for a locally-installed version of the named command, while the `-any` versions check for a command anywhere on the `PATH`.  The `require` functions run their *cmd args...* tail if their first argument isn't available, or, if no *cmd args...* is given, default to an error message that aborts the script with the [EX_UNAVAILABLE](https://www.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3#DESCRIPTION) exit code.

```shell
have()     { [[ -x "$BASHER_INSTALL_BIN/$1" ]]; }
have-any() { unhash "$@"; command -v "$@"; } >/dev/null 2>&1

require() {
    have "$1" || __require "$1" "$1 must be installed to $BASHER_INSTALL_BIN/" "${@:2}"
}

require-any() {
    have-any "$1" || __require "$1" "Please install $1 to perform this operation" "${@:2}"
}

__require() {
    if (($#>2)); then "${@:3}"; unhash "$1"; else abort "$2" 69; fi
}

```
### Symlinks and Path Handling

```shell
relative-symlink() {
    # Used to create relative links in .deps/bin
    realpath.dirname "$2"; realpath.relative "$1" "$REPLY"; ln -sf "$REPLY" "$2"; return $?
}

# We've now defined all the functions we need to be able to fetch our own dependencies
# using the `github` and/or `basher` functions, so we can start importing them now:

import: realpaths

```

## `import:` shim

If `dk` is being used in packed form, then it's using a stub  `import:` that can't import anything dynamically.  To allow dynamic `import:` of `devkit` modules without installing bashpackr, we define a shim that tries to source `.devkit/modules/$module` first, before falling back to installing bashpackr and using that.

```shell
[[ ${__bpkr_packed-} ]] && import:() {
    is-imported: "$1" && return
    if [[ -f "$LOCO_ROOT/.devkit/modules/$1" ]]; then
        BASHPACKR_LOADED+="<$1>"
        source "$LOCO_ROOT/.devkit/modules/$1"
    else
        require bashpackr basher install bashup/bashpackr
        source "$BASHER_INSTALL_BIN/bashpackr"
        import: "$1"
    fi
}
```

## loco configuration

We override loco's configuration process in a few ways: first, our command name/function prefix is always `dk`, and we always use a `.dkrc` file as the project file.  When loading the project file, we source the adjacent `.envrc` first, and also make sure there's a `dk` in the project's auxiliary bin dir.

```shell
import: loco

loco_preconfig() {
    LOCO_SCRIPT=$BASH_SOURCE
    LOCO_COMMAND=dk
    LOCO_FILE=.dkrc
}

loco_loadproject() {
    cd "$LOCO_ROOT"
    [[ -f .envrc ]] && source .envrc

    [[ ! "${BASHER_INSTALL_BIN-}" || ${BASHER_INSTALL_BIN#$PWD} == "$BASHER_INSTALL_BIN" ]] &&
        abort "Your .envrc must define a *local* installation of basher!" 78 # EX_CONFIG

    have dk || {
        mkdir -p "$BASHER_INSTALL_BIN"
        relative-symlink .devkit/dk "$BASHER_INSTALL_BIN/dk"
    }

    $LOCO_LOAD "$1"
}


```

We also disable sitewide and user config files, because using them goes against devkit's goal of *self-containment*: it shouldn't be necessary for a user to change or install global things to work on your project.

```shell
loco_site_config() { :; }
loco_user_config() { :; }
```

Having configured everything we need, we can reuse loco's "main" function instead of defining our own.  (And because this is a shelldown file, we specify a sed command for bashpackr to pack our source with.)

```shell
main: loco_main "$@"
pack-with: sed -ne '/^```shell$/,/^```$/{/^```/d; p}' "$BASH_SOURCE"
```
