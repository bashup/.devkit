#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; eval "$(mdsh -E "$BASH_SOURCE")"; # -->

```shell mdsh
@module dk.md
@main loco_main   # use loco's main as our main

@require pjeby/license @comment    LICENSE
@require bashup/scale-dsl cat      "$BASHER_PACKAGES_PATH/bashup/scale-dsl/scale-dsl"
@require bashup/loco   mdsh-source "$BASHER_PACKAGES_PATH/bashup/loco/loco.md"
@require bashup/dotenv mdsh-embed  "$BASHER_PACKAGES_PATH/bashup/dotenv/dotenv"
@require bashup/events cat         "$BASHER_PACKAGES_PATH/bashup/events/bashup.events"
echo
```

# dk - the devkit CLI

`dk` is a specialized version of [loco](https://github.com/bashup/loco), that uses a `.dkrc` file to designate the project directory, define commands, etc.  It extends loco to provide:

* skeleton implementations of [Scripts to Rule Them All](https://githubengineering.com/scripts-to-rule-them-all/) commands, as `dk` subcommands
* an event-driven framework for fleshing out those skeletons
* a self-installing, local [basher](https://github/basherpm/basher) instance for installing dependencies
* various convenience functions for detecting and fetching dependencies
* a  `use:` command that loads .devkit modules (by sourcing them at most once)

### Contents

<!-- toc -->

- [Scripts To Rule Them All](#scripts-to-rule-them-all)
- [Dependency Management Functions](#dependency-management-functions)
  * [basher](#basher)
  * [github](#github)
  * [linkbin and catbin](#linkbin-and-catbin)
  * [have, require, have-any, require-any](#have-require-have-any-require-any)
  * [Relative Symlinks](#relative-symlinks)
- [`dk use:`](#dk-use)
- [loco configuration](#loco-configuration)

<!-- tocstop -->

## Subcommands and Events

dk subcommands like `setup`, `test`, `watch`, etc. are all run using the bashup/events library.  When a subcommand `X` is invoked, dk first emits a `before_X` event, then looks for:

* Listeners on an event named `X`
* A function named `dk.X`
* Listeners on an event named `default_X`

The found listeners or function are then invoked, followed by an `after_X` event (assuming the previous events or function returned success).  If no function or listeners were found, an `undefined-command` subcommand is run, whose default implementation is to abort with an error message.

If a command `X` is registered via `paged-command X`, it and its events will run in a subshell, piped through `DEVKIT_PAGER` (or `less -FRX`), assuming stdout is a TTY and the command isn't already being paged.  (By default, only the `test` command is paged.)

```shell
run() {
	if [[ ! ${DEVKIT_IS_PAGING-} ]] && event has "before_$1" paged-command; then
		dk use: tty
		with-pager run "$@"
		return
	elif event has "$1"; then
		event emit "before_$@"
		event emit "$@"
	elif fn_exists "dk.$1"; then
		event emit "before_$@"
		"dk.$@"
	elif event has "default_$1"; then
		event emit "before_$@"
		event emit "default_$@"
	else
		run "undefined-command" "$@"
		return
	fi
	event emit "after_$@"
}

dk.undefined-command() {
	abort "This project does not have a $1 command defined." 69   # EX_UNAVAILABLE
}

abort()    { log "$1"; exit "$2"; }
log()      { echo "$1" >&2; }

paged-command() { while (($#)); do before "$1" paged-command; shift; done; }

```

To make .dkrc files more compact, and clearer in intent, we also define some shorthand functions for registering or unregistering event handlers, and before/after events.  We also register an `EXIT` trap that fires an `EXIT` event, so that multiple exit handlers can safely be registered.

```shell
on() { if (($#==1)); then ::block event-dsl on "$1";  else event on "$@"; fi; }
off(){ if (($#==1)); then ::block event-dsl off "$1"; else event off "$@"; fi; }

before() { on "before_$@"; }
after()  { on "after_$@"; }

event-dsl() { [[ ! ${__blk__-} ]] || abort "Can't nest event blocks" 64; event "$@"; }
trap 'event emit "EXIT"' EXIT

```

## Scripts To Rule Them All

dk provides skeletons for all the "Scripts to Rule Them All" commands, which can be overridden in the project's `.dkrc` file.  The defaults mostly do nothing, or abort with an error message, but `dk use:` ing other devkit modules or redefining the functions can change that.  A few commands are given no-op default implementations, but most must have event listeners registered or functions defined in order to work.

```shell
# Commands that should have a bootstrap first:
for REPLY in setup update build cibuild dist server test console watch; do
    event once "before_$REPLY" dk bootstrap    # start everything but clean with bootstrap
done

# Commands that are ok as no-ops:
for REPLY in setup update bootstrap test_files; do
	on "default_$REPLY" :  # no-op
done

# Commands that should have tests run first:
for REPLY in build dist; do
	before "$REPLY" dk test
done

# Commands whose output should be paged
paged-command test

# Cleanup
clean-deps() { [[ "$BASHER_PREFIX" == "$PWD/.deps" ]] && rm -rf "$BASHER_PREFIX"; }

on    "clean" clean-deps
after "clean" hash -r
after "clean" linkbin .devkit/dk

```

## Dependency Management Functions

### Automatic Dependency Fetching

When `dk` starts, it fetches any github dependencies from `BUILD_DEPS` in `package.sh`, if applicable.  The entry must be in dotenv format (i.e., no quotes or escaping), and dependencies are `:`-separated `user/repo@ref` strings, where the `@ref` is optional.

```shell
dk-fetch-deps() {
	local BUILD_DEPS; .env -f "package.sh" export BUILD_DEPS
	IFS=: read -ra BUILD_DEPS <<<"${BUILD_DEPS-}"; set -- ${BUILD_DEPS[@]+"${BUILD_DEPS[@]}"}
	for REPLY; do github "$REPLY"; done
}
```



### basher

For use in `.dkrc` commands, we provide an auto-installing wrapper function for  `basher`, that installs it locally if needed.

```shell
basher() {
    require basher github basherpm/basher master bin/basher
    "$BASHER_INSTALL_BIN/basher" "$@"
}

```

### github

Not everything is installable with basher, of course, and basher itself needs to be installed via github.  So we have a `github` *user/repo[@ref]\[ref [bin1 bin2...]]* function, which clones the desired repo under `.deps` (if it's not already there) and links the named files to `.deps/bin`.  The *ref* can be a branch or tag; it defaults to the repository's default branch if unspecified.  Any binaries specified will be linked in *addition* to those specified by the repo's `package.sh`, if it exists.

```shell
github() {
	[[ $1 != *@* ]] || set -- "${1%%@*}" "${1#*@}" "${@:2}"
	[[ -d "$BASHER_PACKAGES_PATH/$1/.git" ]] && return
	mkdir -p "$BASHER_PACKAGES_PATH/$1"
	git clone -q --depth=1 ${2:+-b "$2"} "https://github.com/$1" "$BASHER_PACKAGES_PATH/$1"
	local BINS; .env -f "$BASHER_PACKAGES_PATH/$1/package.sh" export BINS
	IFS=: read -ra BINS <<<"${BINS-}"; set -- "$1" "${2-}" ${BINS[@]+"${BINS[@]}"} "${@:3}"
	for REPLY in "${@:3}"; do ${REPLY:+linkbin "$BASHER_PACKAGES_PATH/$1/$REPLY"}; done
}
```

### go

Some utilities need to be built using `go get`, but go itself may not be present on the target system.  We provide a wrapper that requests its installation, for use in commands like `require tool go get github.com/something/tool`.

```shell
go() { require-any go; unset -f go; command go "$@"; }
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
### Relative Symlinks

```shell
relative-symlink() {
    # Used to create relative links in .deps/bin
    realpath.dirname "$2"; realpath.relative "$1" "$REPLY"; ln -sf "$REPLY" "$2"; return $?
}
```

## `dk use:`

devkit modules are loaded using the `dk use:` command, which loads modules a maximum of once.

A module name of the form `+` *org* `/` *repo [*`@` *ref ] [* `:`*module ]* is loaded from the specified github repository (and possible reference), using the `github` function.  (i.e., it is cached as a dependency in `.deps`, and not refetched unless a `clean` is run).

If the *module* part is given, it is searched for in that repo's `.devkit-modules/`, `bin/`, and root directories; otherwise the module is exected to be named `.devkit-modules/default `, or `.devkit-module` in the repo's root.

Module names *not* beginning with `+` are searched for in the project's own `.devkit-modules` directory, then in `.devkit/modules`.

```shell
__dk_find_file() {
	for REPLY in "${@:3}"; do REPLY=$1/$REPLY${2:+/$2}; [[ -f $REPLY ]] || continue; return; done
	false
}

__find_dk_module() {
	case $1 in
		+?*/?*:*) set -- "${1%:*}" "${1#*:}" .devkit-modules bin . ;;
		+?*/?*)   set -- "$1"      ""        .devkit-modules/default .devkit-module ;;
		*)
			__dk_find_file "$LOCO_ROOT" "$1" .devkit-modules .devkit/modules
			return
	esac
	github "${1#+}"; __dk_find_file "$BASHER_PACKAGES_PATH/${1#+}" "${@:2}"
}

dk.use:() {
    while (($#)); do local m=$1; shift
        if [[ ${DEVKIT_MODULES-} == *"<$m>"* ]]; then
            : # already loaded
        elif __find_dk_module "$m"; then
            DEVKIT_MODULES+="<$m>"; source "$REPLY"
        else
            abort "Unknown module '$m'; maybe you need to update .devkit or install a dependency?" 69
        fi
    done
}
```

## loco configuration

We override loco's configuration process in a few ways: first, our command name/function prefix is always `dk`, and we always use a `.dkrc` file as the project file.  When loading the project file, we source the adjacent `.envrc` first, and also make sure there's a `dk` in the project's auxiliary bin dir.  We also verify whether the executing copy of dk is the *project's* local copy, and exec that instead of ourselves if not.

```shell
loco_preconfig() {
    LOCO_SCRIPT=${BASH_SOURCE[0]}
    LOCO_COMMAND=dk
    LOCO_FILE=(.dkrc)
}

loco_findroot() {
    local proj_dk this_dk
    _loco_findroot "$@"
    export DEVKIT_ROOT=$LOCO_ROOT DEVKIT_HOME=$LOCO_ROOT/.devkit
    realpath.canonical "$DEVKIT_HOME/dk"; proj_dk=$REPLY
    realpath.canonical "${BASH_SOURCE[0]}"; this_dk=$REPLY
    [[ "$proj_dk" == "$this_dk" || ! -x "$proj_dk" ]] || exec "$proj_dk" "$@";
}

loco_loadproject() {
    cd "$LOCO_ROOT"
    [[ -f .envrc ]] && source .envrc

    [[ ! "${BASHER_INSTALL_BIN-}" || ${BASHER_INSTALL_BIN#$PWD} == "$BASHER_INSTALL_BIN" ]] &&
        abort "Your .envrc must define a *local* installation of basher!" 78 # EX_CONFIG

    require dk linkbin "$DEVKIT_HOME/dk"   # make sure there's a local dk
    dk-fetch-deps      # fetch BUILD_DEPS specified by package.sh
    source "$1"
    event fire "boot"  # Run boot event as soon as soon as we're finished loading
}

```

We also disable sitewide and user config files, because using them goes against devkit's goal of *self-containment*: it shouldn't be necessary for a user to change or install global things to work on your project.  Last, but not least, we override loco's command dispatcher to use our `run` function, as long as there's at least one argument on the command line, and it's not empty.

```shell
loco_site_config() { :; }
loco_user_config() { :; }

loco_do() {
	if [[ "${1-}" ]]; then
		run "$@"  # try to run the event or function, plus before+after events
	else
		_loco_do "$@"  # empty subcommand, let loco abort w/error message
	fi
}
```
