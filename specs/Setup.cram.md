# .devkit/setup

Without .git:

    $ ln -s "$TESTDIR/.." .devkit
    $ .devkit/setup
    (Not using git?  Be sure to exclude .devkit and .deps from revision control)
    devkit setup is complete; you can now commit the changes


    $ ls -ap
    ./
    ../
    .devkit
    .dkrc
    .envrc
    script/

    $ ls -l script/
    total * (glob)
    * README.md (glob)
    * bootstrap (glob)
    * cibuild -> bootstrap (glob)
    * clean -> bootstrap (glob)
    * console -> bootstrap (glob)
    * server -> bootstrap (glob)
    * setup -> bootstrap (glob)
    * test -> bootstrap (glob)
    * update -> bootstrap (glob)


    $ diff script/bootstrap .devkit/script/bootstrap
    $ diff .envrc           .devkit/sample.envrc
    $ diff .dkrc            .devkit/sample.dkrc

With git (clean):

    $ rm -rf .envrc .dkrc script
    $ git init
    Initialized empty Git repository in */Setup.cram.md/.git/ (glob)
    $ .devkit/setup
    devkit setup is complete; you can now commit the changes
    $ git status --porcelain
    A  .dkrc
    A  .envrc
    A  .gitignore
    A  script/README.md
    A  script/bootstrap
    A  script/cibuild
    A  script/clean
    A  script/console
    A  script/server
    A  script/setup
    A  script/test
    A  script/update
    $ cat .gitignore
    .deps
    .devkit

With git (dirty):

    $ .devkit/setup
    Please commit or stash your changes before running setup
    [65]

    $ git commit -m "Added devkit"
    [master (root-commit) *] Added devkit (glob)
     12 files changed, 68 insertions(+)
     create mode 100644 .dkrc
     create mode 100644 .envrc
     create mode 100644 .gitignore
     create mode 100644 script/README.md
     create mode 100755 script/bootstrap
     create mode 120000 script/cibuild
     create mode 120000 script/clean
     create mode 120000 script/console
     create mode 120000 script/server
     create mode 120000 script/setup
     create mode 120000 script/test
     create mode 120000 script/update

With already existing files:

    $ .devkit/setup
    devkit setup is complete; you can now commit the changes


    $ cat .gitignore
    .deps
    .devkit

With changed .gitignore:

    $ echo ".devkit" >.gitignore
    $ .devkit/setup
    Please commit or stash your changes before running setup
    [65]


    $ git commit -m "Changed .gitignore" .gitignore
    [master *] Changed .gitignore (glob)
     1 file changed, 1 deletion(-)


    $ .devkit/setup
    devkit setup is complete; you can now commit the changes


    $ cat .gitignore
    .devkit
    .deps

With changed .dkrc and .envrc:

    $ echo >>.dkrc
    $ echo >>.envrc
    $ git commit -m "Changed .dkrc and .envrc" .dkrc .envrc
    [master *] Changed .dkrc and .envrc (glob)
     2 files changed, 2 insertions(+)
    $ .devkit/setup
    Please commit or stash your changes before running setup
    [65]


    $ git status --porcelain
    M  .gitignore
    $ git commit -m "Changed .gitignore" .gitignore
    [master *] Changed .gitignore (glob)
     1 file changed, 1 insertion(+)


    $ .devkit/setup
    .envrc already exists with different contents; please check against .devkit/sample.envrc
    .dkrc already exists with different contents; please check against .devkit/sample.dkrc
    devkit setup is complete; you can now commit the changes

With changed script/bootstrap:

    $ git status --porcelain
    $ echo >>script/bootstrap
    $ git commit -m "Tweaked bootstrap" script/bootstrap
    [master *] Tweaked bootstrap (glob)
     1 file changed, 1 insertion(+)


    $ .devkit/setup
    .envrc already exists with different contents; please check against .devkit/sample.envrc
    .dkrc already exists with different contents; please check against .devkit/sample.dkrc
    script/bootstrap already exists with different contents; please check against .devkit/script/bootstrap
    devkit setup is complete; you can now commit the changes
    $ git status --porcelain

With changed script/README.md (no warning, since README is optional):

    $ echo >>script/README.md
    $ git commit -m "Tweaked README.md" script/README.md
    [master *] Tweaked README.md (glob)
     1 file changed, 1 insertion(+)


    $ .devkit/setup
    .envrc already exists with different contents; please check against .devkit/sample.envrc
    .dkrc already exists with different contents; please check against .devkit/sample.dkrc
    script/bootstrap already exists with different contents; please check against .devkit/script/bootstrap
    devkit setup is complete; you can now commit the changes
    $ git status --porcelain

