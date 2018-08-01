# This file is sourced via BASH_ENV while running .cram.md files
# It can source other files, define functions, initialize variables, etc.,
# but should not produce any output, or the test(s) it's run for will fail
# Cram's environment variables (TESTDIR, TESTFILE, CRAMTMP) are all accessible.

hello-world() { echo "hey there, $TESTFILE"; }

# Cram variables are available at source time, as well as function-call time:
SOMEVAR=$TESTFILE