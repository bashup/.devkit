## .devkit: development automation & dependency management for bash

If you're working on a project that:

* involves a lot of bash code, development dependencies, and/or specialized commands, and
* needs to be shared with people who may contribute to the project, but who
  * **don't** want to have to setup all those dependencies to work on it, and
  * **don't** want to learn project-specific ways to run tests, etc.

your choices are kind of limited.  You can use a Makefile, maybe, and what... git submodules?  Vendoring with git subtrees?  One of the many bash package managers that don't really get along with each other, and which your collaborators would have to install on their mahcines?

Sure, you can solve the standardization part of the problem with a [Scripts to Rule Them All](https://githubengineering.com/scripts-to-rule-them-all/)-style `script/` directory, but those are kind of a pain to make and not terribly reusable from one project to the next.

`.devkit` solves these problems by giving you an *extensible* automation and development-dependency management framework that you *don't* have to bundle in your project.  Instead, your project's  `script/` directory contains a short [`bootstrap`](script/bootstrap) that fetches `.devkit`, and all of the other `script/` files are just symlinks to `bootstrap`.

Your project then defines any custom commands and variables in a `.dkrc` file, and gets to use all the tools and modules available in `.devkit`, inlcuding a local version of `basher` for git-based dependency fetching.  Dependencies are installed to a `.deps` directory, with executables in `.deps/bin` -- which is added to `PATH` while your commands run.  You can also add new `script/` types of your own, or just run the extra commands with `.devkit/dk commandname`.

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

The `.envrc` is a bash file that configures `PATH`, `MANPATH`, and various basher-specific variables to install dependencies under `.deps`, with commands and manpages directed to `.deps/bin` and `.deps/man`.  It's automatically sourced when running `script/` commands or a `.devkit/dk` subcommand.

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

Currently, .devkit provides only one module: [cram](cram).  It defines a default `dk.test` function to provide a `script/test` command that:

* runs the [cram functional testing tool](https://bitheap.org/cram/) on `specs/*.cram.md` files with 4-space indents
* colorizes the diff results (if `pygmentize` is available) and runs them through less

 .devkit itself uses this module in its own `.dkrc` by `import:`-ing it, like so:

```shell
import: cram
```

You can do the same in your own `.dkrc`, and the same goes for any future .devkit modules.  You can then override a module's defaults by defining new functions.  For example, if you wanted to change the files to be processed by cram, you can redefine the `cram.files` function, and to change the pager, redefine the `cram.pager` function.

### Project Status

At this moment, devkit is still very much in its infancy, and should be considered alpha stability (i.e., expect rapid and likely-breaking changes).  This is also all the documentation there is so far, and there are many modules planned but yet to be added.  For right now, you'll also need to read the [dk source](dk.md) and [loco docs](https://github.com/bashup/loco) to see the full API available to you.
