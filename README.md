## .devkit: development automation & dependency management

If you're working on a project that:

* involves a lot of bash code, development-time dependencies, and/or specialized commands, and
* needs to be shared with people who may contribute to the project, but who
  * **don't** want to have to setup all those dependencies to work on it, and
  * **don't** want to learn project-specific ways to run tests, etc.

your choices are kind of limited.  You can use a Makefile, maybe, and what... git submodules?  Vendoring with git subtrees?  One of the many bash package managers that don't really get along with each other, and which your collaborators would have to install on their mahcines?

Sure, you can solve the standardization part of the problem with a [Scripts to Rule Them All](https://githubengineering.com/scripts-to-rule-them-all/)-style `script/` directory, but those are kind of a pain to make and not terribly reusable from one project to the next.

`.devkit` solves these problems by giving you an *extensible* automation and development-dependency management framework that you *don't* have to bundle in your project.

Instead, your project's  `script/` directory contains a short [`bootstrap`](script/bootstrap) that fetches `.devkit`, and all of the other `script/` files are just symlinks to `bootstrap`.

Your project then defines any custom commands and variables in a `.dkrc` file, and gets to use all the tools and modules available in `.devkit`, inlcuding a local version of `basher` for git-based dependency fetching.

 Dependencies are installed to a `.deps` directory, with executables in `.deps/bin` -- which is added to `PATH` while your commands run.  You can also add new `script/` types of your own, or just run the extra commands with `.devkit/dk commandname`.

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

You can activate any of them by adding "`dk use:` *modules...*" to your `.dkrc`, then defining any needed variable or function overrides.  (Typically, you override variables by defining them *before* the `dk use:` line(s), and functions by defining them *after*.)

Note that these modules are not specially privileged in any way: you are not *required* to use them to obtain the specified functionality.  They are simply defaults and examples.

So, for example, if you don't like how devkit's `entr-watch` module works, you can write your own functions in `.dkrc` or in a package that you load as a development dependency (e.g. with `require mycommand github mygithubaccount/mycommand mycommand; source "$(command -v mycommand)"`).

You can also place your own devkit modules under a  `.devkit-modules` directory in your project root, and `dk use:` will look for modules there before searching .devkit's bundled modules.  You can also access modules from your `.deps` subdirectories by adding symlinks to them from your project's `.devkit-modules`.  (Just make sure your `.dkrc` installs those dependencies *before* `dk use:`-ing them, if they're not there yet.)

### All-Purpose Modules

#### cram

The [cram](modules/cram) module defines a default `dk.test` function to provide a `script/test` command that automatically installs a local copy of the [cram functional testing tool](https://bitheap.org/cram/), and runs it on `specs/*.cram.md` files with 4-space indents, colorizing the diff results (if `pygmentize` is available) and piping the result through less.

To use this module (as .devkit itself does),  `use:` it in your `.dkrc`, like so:

```shell
dk use: cram
```

You can then override the module's defaults by defining new functions.

For example, if you wanted to change the files to be processed by cram, you can redefine the `cram.files` function, and to change the pager, redefine the `cram.pager` function.  To change the cram options, set the `CRAM` environment variable, or add a `.cramrc` file to your project.

#### entr-watch

The [entr-watch](modules/entr-watch) module defines a default `dk.watch` command to provide a `script/watch` command that watches for file changes (using [entr](http://entrproject.org/)) and reruns a command (`dk test` by default).  To enable it, `dk use: entr-watch` in your `.dkrc`, and then optionally define a `watch.files` function to output which files to watch.  (By default, it outputs the current directory contents and any `test.files`.)

The watch command requires the `entr` and `tput` commands be installed.  The former is used to watch files for changes, and the latter to compute how many lines of watched command output can be displayed without scrolling.  (The watched command's output is cut off using `head`, and the screen is cleared whenever the watched command is re-run.)

#### shell-console

The [shell-console](modules/shell-console) module implements a `dk.console` function to provide a `script/console` command that starts a bash subshell with the devkit API and all variables available -- a bit like dropping into a debugger for the `dk` command.  This is particularly handy if you don't have or use `direnv`, as it basically gives you an alternative to typing `script/foo` or `.devkit/dk foo`: within the subshell you can just `dk foo`.

To activate this in your project, add a `dk use: shell-console` line to your `.dkrc`, just like .devkit does.  Running `dk console` or `script/console` will then enter a subshell.

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

The [peridot](modules/peridot) module defines a default `dk.test` function to provide a `script/test` command that runs [peridot-php](http://peridot-php.github.io/) on `specs/*.spec.php` and piping the result through `less -FR`.

To change the files tested, redefine the  `peridot.files` function to emit a different list of files.  To change the pager, redefine `peridot.pager`.   To change the options, set `PERIDOT_OPTIONS` (after the `dk use: peridot`).

#### psysh-console

The [psysh-console](modules/psysh-console) module implements a `dk.console` function to provide a `script/console` command that starts a psysh shell.


