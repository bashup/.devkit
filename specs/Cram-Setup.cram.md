## Support for cram-setup.sh

The .devkit `cram` module supports sourcing test setup code that's run before every test in a given directory, by creating a `cram-setup.sh` in that directory.

In this case the [cram-setup.sh](cram-setup.sh) just contains a `hello-world` function, which we'll run now to prove that it has already been sourced, and knows what file it was run for:

~~~shell
    $ hello-world
    hey there, Cram-Setup.cram.md
~~~

The cram-setup.sh can also access cram's environment variables (mainly `$TESTDIR` and `$TESTFILE`), and set variables that are exposed to the shell.  For this test, cram-setup.sh exposes `$SOMEVAR` to prove it knows our `$TESTFILE`:

~~~shell
    $ echo $SOMEVAR
    Cram-Setup.cram.md
~~~

