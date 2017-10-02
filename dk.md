#!/usr/bin/env bashpackr
: '
<!-- ex: set syntax=markdown : '; eval "$(sed -ne '/^```shell$/,/^```$/{/^```/d; p}' "$BASH_SOURCE")"; return $? # -->

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

dk.server()  { undefined-command server; }
dk.test()    { undefined-command test; }
dk.console() { undefined-command console; }

undefined-command() {
    abort "This project does not have a $1 command defined." 69   # EX_UNAVAILABLE
}
abort()    { log "$1"; exit $2; }
log()      { echo "$1" >&2; }
```

## Basher and Dependency Management

For use in `.dkrc` commands, we provide an auto-installing wrapper function for  `basher`, that installs it locally if needed.  (The [realpaths](realpaths) module is also imported and made available.)

```shell
import: realpaths

basher() {
    have basher || {
        mkdir -p "$BASHER_ROOT" "$BASHER_INSTALL_BIN"
        git clone -q --depth 1 https://github.com/basherpm/basher "$BASHER_ROOT"
        realpath.symlink "$BASHER_ROOT/bin/basher" "$BASHER_INSTALL_BIN/basher"
    }
    hash -d basher 2>/dev/null
    unset -f basher
    "$BASHER_INSTALL_BIN/basher" "$@"
}
```

To help decide whether dependencies are needed, we offer the `have`/`require`  and `have-any`/`require-any` functions.  The plain varieties check for a locally-installed version of the named command, while the `-any` versions check for a command anywhere on the `PATH`.  The `require` functions run their *cmd args...* tail if their first argument isn't available, or, if no *cmd args...* is given, default to an error message that aborts the script with the [EX_UNAVAILABLE](https://www.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3#DESCRIPTION) exit code.

```shell
have()     { [[ -x "$BASHER_INSTALL_BIN/$1" ]]; }
have-any() { hash -d "$@"; command -v "$@"; } >/dev/null 2>&1

require() {
    have "$1" || __require "$1" "$1 must be installed to $BASHER_INSTALL_BIN/" "${@:2}"
}

require-any() {
    have-any "$1" || __require "$1" "Please install $1 to perform this operation" "${@:2}"
}

__require() { if (($#>2)); then "${@:3}"; hash -d "$1" 2>/dev/null; else abort "$2" 69; fi }

```
## `import:` shim

If `dk` is being used in packed form, then it's using a stub  `import:` that can't import anything dynamically.  To allow dynamic `import:` of `devkit` modules without installing bashpackr, we define a shim that tries to source `.devkit/$module` first, before falling back to installing bashpackr and using that.

```shell
[[ ${__bpkr_packed-} ]] && import:() {
    is-imported: "$1" && return
    if [[ -f "$LOCO_ROOT/.devkit/$1" ]]; then
        BASHPACKR_LOADED+="<$1>"
        source "$LOCO_ROOT/.devkit/$1"
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

    [[ ! -v BASHER_INSTALL_BIN || ${BASHER_INSTALL_BIN#$PWD} == "$BASHER_INSTALL_BIN" ]] &&
        abort "Your .envrc must define a *local* installation of basher!" 78 # EX_CONFIG

    have dk || {
        mkdir -p "$BASHER_INSTALL_BIN"
        realpath.symlink "$BASH_SOURCE" "$BASHER_INSTALL_BIN/dk"
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
