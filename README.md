## .devkit: development automation & dependency management

If you're working on a project that:

* involves a lot of bash code, development-time dependencies, and/or specialized commands, OR
* uses tools built in multiple languages (e.g. node, go, Python, etc.), AND
* needs to be shared with people who may contribute to the project, but who
  * **don't** want to have to setup all those dependencies to work on it, and
  * **don't** want to learn project-specific ways to run tests, etc.

your choices are kind of limited.  You can use a Makefile, maybe, and what... git submodules?  Vendoring with git subtrees?  One of the many bash package managers that don't really get along with each other, and which your collaborators would have to install on their mahcines?  An entire Vagrant VM or collection of docker images?

Sure, you can solve the standardization part of the problem with a [Scripts to Rule Them All](https://githubengineering.com/scripts-to-rule-them-all/)-style `script/` directory, but those are kind of a pain to make and not terribly reusable from one project to the next.

`.devkit` solves these problems by giving you an *extensible* automation and development-dependency management framework that you *don't* have to bundle in your project.

Instead, your project's  `script/` directory contains a short [`bootstrap`](script/bootstrap) that fetches `.devkit`, and all of the other `script/` files are just symlinks to `bootstrap`.

Your project then defines any custom commands and variables in a `.dkrc` file, and gets to use all the tools and modules available in `.devkit`, inlcuding a local version of `basher` for git-based dependency fetching.

Dependencies are installed to a `.deps` directory, with executables in `.deps/bin` -- which is added to `PATH` while your commands run.  You can also add new `script/` types of your own, or just run the extra commands with `.devkit/dk commandname`.

**Contents**

<!-- toc -->

- [Project Status](#project-status)
- [Installation](#installation)
- [Configuration and Extension](#configuration-and-extension)
  * [Automatic Dependency Fetching](#automatic-dependency-fetching)
- [.devkit Modules](#devkit-modules)
  * [External Modules](#external-modules)
- [All-Purpose Modules](#all-purpose-modules)
  * [cram](#cram)
  * [shell-console](#shell-console)
- [Watch Modules](#watch-modules)
  * [entr-watch](#entr-watch)
  * [modd-watch](#modd-watch)
  * [reflex-watch](#reflex-watch)
- [Modules for Golang-Using Projects](#modules-for-golang-using-projects)
  * [golang](#golang)
- [Modules for Python-Using Projects](#modules-for-python-using-projects)
  * [virtualenv](#virtualenv)
- [Modules for PHP-Using Projects](#modules-for-php-using-projects)
  * [composer](#composer)
  * [peridot](#peridot)
  * [psysh-console](#psysh-console)
- [Modules for Projects Using bash](#modules-for-projects-using-bash)
  * [bash-kit](#bash-kit)

<!-- tocstop -->

### Project Status

At this moment, devkit is still very much in its infancy, and should be considered alpha stability (i.e., expect rapid and likely-breaking changes).  This is also all the documentation there is so far, and there are many modules planned but yet to be added.  For right now, you'll also need to read the [dk source](dk.md) and [loco docs](https://github.com/bashup/loco) to see the full API available to you (beyond what's listed here).

### Installation

To use this in your project, just do the following in your project root:

```sh
$ git clone -q https://github.com/bashup/.devkit
$ .devkit/setup
devkit setup is complete; you can now commit the changes
$ git commit -m "Added devkit"
```

The `.devkit/setup` command will create and `git add` a `script/` directory for you, with unchanging bootstrap code.  It also adds `.deps` and `.devkit` to your `.gitignore`, and creates a default `.envrc` and `.dkrc` if you don't already have them.

In addition to installing the project tools locally, you can install a global copy of the [`dk` binary](dk) as a way to run commands that don't have `script/` counterparts, without needing to explicitly type `.devkit/dk` to run the local copy.   (A global `dk` will `exec` the local copy of `dk` if one is present and not the same file as the global `dk`.)  If you use [basher](https://github.com/basherpm/basher), you can `basher install bashup/.devkit` to do the global install.

### Configuration and Extension

The `.envrc` is a bash file that configures `PATH`, `MANPATH`, and various basher-specific variables to install dependencies under `.deps`, with commands and manpages directed to `.deps/bin` and `.deps/man`.  (It also adds any project-local composer or node.js local tools to the `PATH`.)  It's automatically sourced when running `script/` commands or a `.devkit/dk` subcommand.

(As a convenience feature, if you or your users have [direnv](https://direnv.net/) installed and running, you or they can `direnv allow` the `.envrc` so that it's automatically sourced whenever you enter the project directory, and reset when you leave, giving you easy access to all your locally installed tools.  Alternately, you or they can manually source it in a subshell.)

The `.dkrc` file, on the other hand, is a bash file where you can define your own commands or override existing ones, as well as activating any `.devkit` modules you want to use.  For example, this `.dkrc` defines a `test` command that uses `bats`:

```shell
dk.test() {
    # check if we have `bats` command, if not, install it locally
    require bats basher install sstephenson/bats
    # Run tests
    bats tests/*.bats
}
```

When somebody checks out the project and runs `script/test` the first time, the following things will happen:

* A copy of `.devkit` is cloned if it doesn't exist
* `basher` is cloned to `.deps/basherpm/basher`, with a command symlink of  `.deps/bin/basher`
* `bats` is cloned to `.deps/sstephenson/bats`, with a command symlink of `.deps/bin/bats`
* `bats tests/*.bats` is run

On subsequent runs of `script/test` (or `.devkit/dk test`), none of the cloning takes place, since the needed things are already installed.

(Note: you can, if you wish, vendor `.devkit` within your project or use a submodule so your users don't end up cloning their own copy, but if you're trying to pin a specific version it's probably easier to just edit your `script/bootstrap` to fetch the exact `.devkit` version you want from github.)

#### Automatic Dependency Fetching

.devkit extends the `package.sh` format with support for fetching development dependencies from github.  If you create a package.sh containing a `BUILD_DEPS` variable, e.g.:

~~~sh
BUILD_DEPS=some/package@some-tag-or-branch:other/package
~~~

Then when any `script/` commands (or the `dk` command) are run, the github packages `some/package` (at `some-tag-or-branch` and `other/package` (at `master`) are cloned to `.deps/some/package` and `.deps/other/package` if those directories don't yet exist.  If the cloned packages have `BINS` listed in *their* `package.sh`, then those files are symliked into `.deps/bin`.

Note: for dependency fetching to work correctly, both the project's `BUILD_DEPS` and its dependencies `BINS` variables in their respective `package.sh` files  must be written without *any* quote marks, escapes, environment variables, etc., as .devkit reads them exactly as written; e.g. `BINS="foo:bar"` will be read as two executables named `"foo` and `bar"` (i.e., with the quotes included).

### .devkit Modules

Currently, .devkit provides the following modules you can `dk use:` in your `.dkrc`:

For any project:

* `entr-watch` -- implement a `watch` command using [entr](http://entrproject.org/)


* `cram` -- implement a  `test` command using [cram](https://bitheap.org/cram/)
* `shell-console` -- implement a `console` command as a bash subshell

For projects using Python:

* `virtualenv` -- functions to create or check for a Python virtualenv

For projects using PHP:

* `composer` -- functions to check for (and optionally possibly require) [composer](https://getcomposer.org)-installed tools
* `peridot` -- implement a `test` command using [peridot-php](http://peridot-php.github.io/)
* `psysh-console` -- implement a `console` command using PHP's [psysh](http://psysh.org/) REPL

For projects using bash 3.2

* `bash32` -- add a `dk bash32` command that can run other devkit commands in [a docker container with bash 3.2](https://github.com/bashup/bash-3.2).

You can activate any of them by adding "`dk use:` *modules...*" to your `.dkrc`, then defining any needed variable or function overrides.  (Typically, you override variables by defining them *before* the `dk use:` line(s), and functions by defining them *after*.)

Note that these modules are not specially privileged in any way: you are not *required* to use them to obtain the specified functionality.  They are simply defaults and examples.  You can write your own modules and put them in a `.devkit-modules` subdirectory of your project root, and `dk use:` will look for modules there before searching .devkit's bundled modules.

#### External Modules

You can also load basically any file from github as a .devkit module, by specifying a module name of the form:

 `+` *org* `/` *repo [* `@`*ref ] [* `:`*module-path ]*

That is, doing e.g. `dk use: +foo/bar@baz:spam` will check out the `baz` branch or tag of `foo/bar` from github into your `.deps` directory (if there's not already a repo there), and then search for one of these files:

* `.deps/foo/bar/.devkit-modules/spam`
* `.deps/foo/bar/bin/spam/`
* `.deps/foo/bar/spam/`

Both the `@`*ref* and `:`*module-path* parts are optional, defaulting to `master` and `.devkit-module` respectively, with `dk use: +foo/bar` checking out the master branch of `foo/bar` and searching for one of these files:

* `.deps/foo/bar/.devkit-modules/default`
* `.deps/foo/bar/.devkit-module`

This means that projects that want to provide .devkit support can include a `.devkit-modules/default` or `.devkit-module` file, allowing others to use it with `dk use: +some/project`, automatically including the repo at build time, and adding its executables to `.deps/bin`.  A project can also be created to just publish a bunch of `.devkit-modules`, or you can just literally source any file you like from any project on github by using an explicit *module-path* in the module name.

### All-Purpose Modules

#### cram

The [cram](modules/cram) module defines a default `dk.test` function to provide a `script/test` command that automatically installs a local copy of the [cram functional testing tool](https://bitheap.org/cram/), and runs it on `specs/*.cram.md` files with 4-space indents, colorizing the diff results (if `pygmentize` is available) and piping the result through less.

To use this module (as .devkit itself does),  `use:` it in your `.dkrc`, like so:

```shell
dk use: cram
```

You can then override the module's defaults by defining new functions.

For example, if you wanted to change the files to be processed by cram, you can redefine the `cram.files` function, and to change the pager, redefine the `cram.pager` function.  To change the cram options, set the `CRAM` environment variable, or add a `.cramrc` file to your project.

As long as you run cram via `script/test`, `dk test`, or `dk cram`, you can place files named `cram-setup.sh` in your test directories, and they will be silently sourced at the start of each test file.  Any functions or variables you define will then be available for your tests, and the setup file can access any cram environment variables (e.g. `$TESTDIR` and `$TESTFILE`).  Setup files should not produce any output, or they will break the corresponding tests.

Setup files can source other shell files, including other directories' `cram-setup.sh` files if you need to share setup between directories (e.g. `source "$TESTDIR/../cram-setup.sh"` to source and extend a parent directory's setup).  You can also just symlink from one cram-setup.sh to another.

#### shell-console

The [shell-console](modules/shell-console) module implements a `dk.console` function to provide a `script/console` command that starts a bash subshell with the devkit API and all variables available -- a bit like dropping into a debugger for the `dk` command.  This is particularly handy if you don't have or use `direnv`, as it basically gives you an alternative to typing `script/foo` or `.devkit/dk foo`: within the subshell you can just `dk foo`.

To activate this in your project, add a `dk use: shell-console` line to your `.dkrc`, just like .devkit does.  Running `dk console` or `script/console` will then enter a subshell.

### Watch Modules

It's a common task to want to watch files and run commands when they change.  devkit currently supports three file watching tools:

* [entr](http://entrproject.org/), via the [entr-watch](#entr-watch) module
* [modd](https://github.com/cortesi/modd), via the [modd-watch](#modd-watch) module, and
* [reflex](https://github.com/cespare/reflex), via the [reflex-watch](#reflex-watch) module

Each of these tools has different strengths and weaknesses.  entr only runs a single command, and has to be piped a list of files (but can detect when the list needs to be refreshed).  modd and reflex can run multiple commands based on matching rules, but have their own behavioral quirks.

reflex can handle regular expressions and can detect directories being created during a watch, but scans *all* files by default, which means you must explicitly add exclusions for anything your project builds, or it will cause infinite build loops.  Its built-in globs do not support recursion or brace expansion, so devkit tries to emulate these features using bash brace expansion and converting globs to regular expressions.

modd, on the other hand, *only* processes globs, but has brace expansion and recursion built in.  It doesn't detect new directories being created, but only matches explicitly-given patterns, so you're less likely to create an infinite loop by rerunning a build as the result of running a build.

#### entr-watch

The [entr-watch](modules/entr-watch) module defines a default `dk.watch` command to provide a `script/watch` command that watches for file changes (using [entr](http://entrproject.org/)) and reruns a command (`dk test` by default).  To enable it, `dk use: entr-watch` in your `.dkrc`, and then optionally define a `watch.files` function to output which files to watch.  (By default, it outputs the current directory contents and any `test.files`.)

The watch command requires the `entr` and `tput` commands be installed.  The former is used to watch files for changes, and the latter to compute how many lines of watched command output can be displayed without scrolling.  (The watched command's output is cut off using `head`, and the screen is cleared whenever the watched command is re-run.)

#### modd-watch

The [modd-watch](modules/modd-watch) module lets you define "watch rules": file patterns to watch for, combined with commands to run those when files change.  Running `dk watch` (or `script/watch` if you create a link for it) will run [modd](https://github.com/cortesi/modd) to watch the files and run commands.  (If modd isn't installed, the `watch` command will try to install it to the project `.deps` directory using `go get`.)

The way you add rules is by calling the `watch` or `watch+` functions from your `.dkrc`.  Each of these functions accepts zero or more glob patterns (optionally negated with a leading `!`), followed by `--` and a command to run.  If no globs are specified, the command will run once, at the beginning of the watch.  (You can also add global exclusion globs with `unwatch`.)  Some examples:

```sh
# When a .cram.md file under specs/ is changed, rerun tests; also run them at start of watch:
watch+ 'specs/**/*.cram.md' -- dk test

# The `watch+` command above is shorthand for these two commands:
watch -- dk test
watch 'specs/**/*.cram.md' -- dk test

# But in some cases, you will want the initial and on-change commands
# to be different.  For example, the below will run a full tree sync
# at start of watch, but sync only individual files when they change:
#
watch -- wp postmark tree posts/
watch 'posts/**/*.md' -- wp postmark sync @mods   # just sync modified files

# Exclude specified pattern(s) from ALL watches, past and future.
unwatch 'build/**' '**/.~*.md'  # ignore files under build/ and editor temp files

# Brace expansion can be used
watch '**/*{.sass,.scss}' -- dk build
```

Notice that glob patterns must be quoted to prevent the shell from interpreting them, rather than passing the wildcards to the watch command.

The difference between `watch` and `watch+` is that `watch+` runs the command immediately upon running `dk watch`, in addition to when files change.  (This avoids the need to save something just to force the command to run.)

If you need the initially-run command to be different, you should separate your commands into `watch --` *init-command...* and `watch` *[glob...]* `--` *change-command...*, to run *init-command* when the watch begins, and *change-command* when changes occur.

Finally, note that if your `.dkrc` file is changed during a watch run, the `dk watch` command will re-execute itself to reload the changed watch configuration.  If you have other files that should trigger such a configuration reload, you can use `watch-reload` *glob...* to add them to the list.

#### reflex-watch

The [reflex-watch](modules/reflex-watch) module is almost identical to modd-watch in function, but using [reflex](https://github.com/cespare/reflex) to watch files and run commands.  (If reflex isn't installed, the `watch` command will try to install it to the project `.deps` directory using `go get`.)

The key differences are:

* reflex does not support brace expansion, so if you need it, you have to use bash's brace expansion in your .dkrc instead, e.g.:

  ```sh
  # Brace expansion can be used, but it has to be outside quotes (so bash will do it)
  watch '**/*'{.sass,.scss} -- dk build
  ```

* Instead of `watch -- ` *initcommand* to define an initial command, you have to use `before watch ` *initcommand*.  e.g.:

  ```sh
  # The reflex equivalent to `watch+ 'specs/**/*.cram.md' -- dk test` is:
  before "watch" dk test
  watch 'specs/**/*.cram.md' -- dk test
  ```

* reflex uses `{}` to indicate file arguments instead of `@mods` (and has no equivalent to `@dirmods`), e.g.:

  ```sh
  # run a full tree sync at start of watch, but sync only individual files when they change:
  before "watch" wp postmark tree posts/
  watch 'posts/**/*.md' '!**/.~*.md' -- wp postmark sync {}
  ```

* You can specify any of reflex's watch-specific options before the `--` in a `watch` or `watch+` command, including using `-r` and `-R` to specify regular expressions to include or exclude, e.g.:

  ```sh
  watch -r '.*\.md' -- echo "A markdown file in any directory changed:" {}
  watch -R '.*\.md' -- echo "A NON-markdown file in any directory changed:" {}
  ```

  Note: this applies only to `watch` and `watch+`; the `watch-reload` and `unwatch` commands only accept globs, and `unwatch-re` only accepts regexes.

* Because reflex queues the changes it observes, and defaults to watching **everything** that isn't one of its common exclusion patterns, you can end up with infinitely looping rebuilds unless your build targets or test outputs are excluded from the watch rules that run them.  You can use `unwatch` or `unwatch-re` to define global exclusion globs and/or regexes that will not trigger any `watch` rules (including `watch+` and `watch-reload` rules).

### Modules for Golang-Using Projects

#### golang

The [golang module](modules/golang) makes it easy to fetch dependencies built with go (e.g. dnscontrol, modd, reflex, etc.), even on machines that don't have the right go version installed.  In the simplest case, you would add lines like these to your .dkrc:

```sh
dk use: golang
golang 1.11.x   # use latest-available golang 1.11
```

And then use `go get` or other go commands as needed.  Binaries will be built in `.deps/bin`, and the default `GOROOT` is `.deps/go` (unless you override these settings in `.envrc`).

The  `dk use: golang` command gives your `.dkrc` access to the following functions:

* `golang` *version* -- select a go version using [gimme](https://github.com/travis-ci/gimme).  The *version* can be anything accepted by gimme, such as `stable`, `master`, `1.10.x`, etc.  Whatever version is selected, the resulting environment is saved to `.deps/.gimme-env` for future use by `.envrc`.  The current process environment will also be updated to point to the specified version.
* `go` *command...* -- the `go` function wraps the `go` command such that if no `go` binary is available, one will be fetched using gimme.  The version fetched will be `$GIMME_GO_VERSION`, or `stable` by default.  The given go command is then run.
* `gimme` *options...* -- this function runs the gimme command, after first fetching it from github if necessary.  See the gimme documentation for how to use it; note that running this function does *not* update the shell environment unless you `eval` its output, as per the gimme docs.  So, unless your project requires *multiple* versions of go, you should just use the `golang` function in your `.dkrc`.

Notice that if you are using direnv, simply going to your project directory will set up your environment such that the `go` on the `PATH` will be the version most recently requested via `golang`.

Also note that, by default, `gimme` installs requested go versions in a directory under **the current user's home directory**.  You can change this behavior using the `GIMME_VERSION_PREFIX` and `GIMME_ENV_PREFIX` variables, which default to `~/.gimme/versions` and `~/.gimme/envs`, respectively.  (For example, setting them to paths under `.deps/.gimme/` would force the use of 100% project-local installs, at the cost of extra disk space and bootstrapping time.)

In addition to the above functions, the golang module also adds a `dk golang` subcommand, which:

* When run with an option as the first argument (e.g. `-h`, `-k`, `--list`, etc.), it runs `gimme` with the given arguments (installing it in the project deps if needed)
* When run with a non-option first argument (e.g. `stable`, `1.12.x`, etc.), it runs the `golang` function to select a specific go version and save it to `.deps/gimme-env`.  If you're using direnv, your current environment will also be updated.
* When run with no arguments, the current `go version` for the project will be displayed (after first installing `go` and `gimme` if needed.)

### Modules for Python-Using Projects

#### virtualenv

The [virtualenv](modules/virtualenv) module makes it easy to use a Python virtual environment as part of your project, giving you a `.deps/bin/python`.  Just `dk use: virtualenv` and you can access the `have-virtualenv` and `create-virtualenv` functions.

`have-virtualenv` returns success if you have an active virtualenv in `.deps`, while `create-virtualenv` creates a virtual environment with the specified options, as long as a virtualenv doesn't already exist.  So, you might do this in your `.dkrc` to create a Python 3 virtualenv:

```shell
dk use: virtualenv
create-virtualenv -p python3
```

`create-virtualenv` passes along its arguments to `virtualenv.py`, automatically adding the `.deps` dir as the last argument, and activating the new virtualenv afterward.  So you only need to specify any non-default options.  The virtualenv will not be created if a virtualenv already exists; you'll have to delete the old one first (e.g. via `script/clean`) if you want to change the settings.

(Note: the default `.envrc` will always activate the virtualenv if it exists, so you do not need to do anything special to ensure that it will be used by subsequent runs of `dk` commands.)

### Modules for PHP-Using Projects

#### composer

The [composer](modules/composer) module provides `have-composer` and `require-composer` functions, to check for or install composer-based command-line tools.  `have-composer sometool` returns true if and only if `vendor/bin/sometool` exists under your project root, and `require-composer sometool foo/bar` will `composer require --dev foo/bar` if `vendor/bin/sometool` does not exist and a `composer install` doesn't create it.  (Every argument to `require-composer` after the tool name is passed to `composer require --dev`, so you can specify any other composer options you like.)

#### peridot

The [peridot](modules/peridot) module defines a `dk peridot` subcommand that is registered to run during `dk test` or `script/test`.  The command runs [peridot-php](http://peridot-php.github.io/) on the `specs` directory and pages the output if it doesn't fit on one screen.  (You can set `PERIDOT_SPECS` to a different directory if your tests aren't under `specs/`, and you can set `PERIDOT_OPTIONS` to pass extra options to peridot.)

The peridot module integrates with the entr-watch module by adding `$PERIDOT_SPECS/**/*.spec.php` to the watch files list.  (If you're using a different grep pattern, you'll want to redefine the `peridot.files` function accordingly.)

To use this module, just `dk use: peridot` in your `.dkrc`.

#### psysh-console

The [psysh-console](modules/psysh-console) module implements a `dk.console` function to provide a `script/console` command that starts a psysh shell.

### Modules for Projects Using bash

#### bash-kit

The [bash-kit](modules/bash-kit) module adds a `with-bash` command you can use to run other commands in a docker container with a specified version of bash.  Bashup projects use this to test compatibility with various bash versions.  You must enable the module by including `bash-kit` in your `.dkrc`'s `dk use:`, and the command will only work if you have access to docker with local volume support (to map the project directory into the container).

Running `dk with-bash VERSION command ...`  runs `dk command ...` inside a docker container using the specified version of bash, so if you have the relevant devkit modules enabled, you can run `test`,`watch`, and even `console`, inside the container.

The following variables control the operation of the container:

* `$BASHKIT_IMAGE` -- Image to run: defaults to [bashup/bash-kit](https://github.com/bashup/bash-kit); if it is not changed from the default, the bash version can be [any official bash tag](https://hub.docker.com/_/bash?tab=tags), and the needed image will be pulled or built if necessary.
* `$BASHKIT_DOCKER_OPTS` -- An array of additional options to run the container with; defaults to `-it` for an interactive run.  (`--rm`, `-e TERM`, volume mappings and the command line are automatically generated, so you do not need to include them here.)  If you need multiple options or values, set them as an array, e.g. `BASHKIT_DOCKER_OPTS=(--foo "bar baz")`, or `BASHKIT_DOCKER_OPTS=()` to remove the default options.

Inside the docker container, a `run-bash VERSION command...`  command is run first, allowing you to do any docker-specific setup (e.g. installing additional dependencies) by either overriding the command or defining a `before` handler for the  `run-bash` event.

Note: the docker container will use `.deps/.bash-VERSION` as its `/workdir/.deps`, so that its installed dependencies can be platform-specific.  Running `clean` inside a container will clean only the dependencies for that bash version, while running `clean` outside the container will wipe dependencies for both the base project and all bash versions used to that point.