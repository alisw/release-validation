jdl2makeflow
============

[![PyPI version](https://badge.fury.io/py/alien-jdl2makeflow.svg)](https://badge.fury.io/py/alien-jdl2makeflow)

Run [AliEn](http://alien.web.cern.ch) JDLs on multiple platforms using
[Makeflow](http://ccl.cse.nd.edu/software/makeflow).


Requirements
------------
[Makeflow](http://ccl.cse.nd.edu/software/makeflow) needs to be installed on
your system. Makeflow is part of the Cooperative Computing tools (cctools). To
install it, [download the latest
version of cctools](http://ccl.cse.nd.edu/software/downloadfiles.php) then
unpack, compile and install it (we are assuming 6.1.1 is the latest, check the
download page first):

    cd /tmp
    curl -L http://ccl.cse.nd.edu/software/files/cctools-6.1.1-source.tar.gz | tar xzf -
    cd cctools-*-source/
    ./configure && make -j10
    sudo make install

Run the last command (`make install`) *as root* to install it system-wide.
Adjust `-j10` to the number of parallel cores you want to use during the build.
If you do not have root privileges:

    cd /tmp
    curl -L http://ccl.cse.nd.edu/software/files/cctools-6.1.1-source.tar.gz | tar xzf -
    cd cctools-*-source/
    ./configure --prefix=$HOME/cctools && make -j10 && make install
    echo 'export PATH=$HOME/cctools/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=$HOME/cctools/bin:$LD_LIBRARY_PATH' >> ~/.bashrc

We are installing under `~/cctools` but you can use the directory you want.
Also, we are assuming your shell configuration file is `~/.bashrc`, adjust it
according to your shell.


Get jdl2makeflow
----------------

As easy as:

    sudo pip install alien-jdl2makeflow

If you cannot install it as root, you will probably have to export some Python
variables to make it work. If you have a user installation of some Python
distribution like [Anaconda](https://www.continuum.io/downloads) this is
probably already done for you.


Basic usage
-----------

Get and configure the JDL used to run a Monte Carlo on AliEn, and all the
required files. Normally you would only require the `Custom.cfg` file. The JDL
can contain variable overrides in a way that AliEn will ignore them and they
will only be considered by the Makeflow workflow: this allows you to keep a
single JDL that works both locally and on the Grid.

Run:

    jdl2makeflow /path/to/job.jdl

By default, it will print a summary and create all necessary files under a
working directory called `work` (override with `-w`). You then need to move to
the working directory and run:

    cd work
    makeflow


Relevant JDL variables
----------------------

Not all JDL variables are used for local use, and some of them are interpreted
in a different way.

* `Executable`: the AliEn path of the executable to run. For local use, we will
  only consider the program name and strip the path, and search for it in the
  following directories in order:
    1. full path first
    2. basename (must be in `$PATH`)
    3. `$ALIDPG_ROOT/bin`
    4. current working directory
* `SplitArguments`: arguments to pass to the executable.
* `InputFile`: list of files that need to be made available in the job's working
  directory for the job to run. Only the basename of the file will be considered
  and it will be searched for in the current directory. No AliEn access will be
  performed.
* `Output`: a list telling what of the files produced by the job need to be
  copied to the destination. Files can also be placed in zip archives. See
  the example JDL for more information.
* `OutputDir`: the output directory for each job. This is normally an AliEn
  path, but locally we can either specify a XRootD path (`root://...`) or a
  local path. Note that XRootD paths might require authentication information to
  be available to the job.
* `Packages`: packages to be loaded in the Grid environment. They are expected
  from CVMFS, and CVMFS must be available locally. You can also use local
  installations for testing, see `EnvironmentCommand` above.
* `JDLVariables`: list of arbitrary variables from the JDL that will be exported
  in the job's environment. The variable name will be altered. If, for instance,
  you want to export the JDL variable `ArbitraryVar`, this will be available to
  your jobs as `ALIEN_JDL_ARBITRARYVAR`. The same convention is used by AliEn
  for Grid jobs.
* `Split`: determine how many jobs have to be run of the kind specified by the
  JDL. The syntax `production:123-456` tells the script to run jobs with a
  different ID from 123 to 456 included (that's 334 jobs). You will probably
  want to change it for local use as the range is very large on the Grid. The
  job index is made available to some other variables through the
  `#alien_counter#` variable, see below.

Since the same JDL will be used for running many jobs, it is in some cases
useful to distinguish between output directories, and to tell the job what is
its index. You can use in variable values:

* `#alien_counter#`: will be replaced with the job index
* `#alien_counter_05i#`: will be replaced with the job index zero-padded to 5
  digits (any format supported by `printf` can be specified of course)

See the examples for more information.


Extra JDL variables
-------------------

The following JDL variables are interpreted only by `jdl2makeflow` and will be
ignored by AliEn.

* `EnvironmentCommand`: command to run in order to set the packages environment.
  If defined, it will be automatically ran before each job (_i.e._ no need to
  load the environment separately before running Makeflow), and `Packages` will
  be ignored. This is useful for local development when one wants to test
  changes with a local AliRoot build. If `EnvironmentCommand` is specified,
  we can run without CVMFS.
* `ExtraVariables`: same as `JDLVariables`, but the variables listed (which must
  be defined in the JDL) will be exported in the job environment as-is, with
  their name not manipulated. So, the variable `ArbitraryVar` will be exported
  as `ArbitraryVar`.
* `NextStages`: the toplevel JDL runs several jobs of the same kind, but other
  tiers of processing will follow (merging stages mostly). This list tells
  the local workflow what are the next stages (order does not matter). For the
  moment, only the values `FinalQA` and `SpacePointCalibration` are supported.
  This variable allows you to run those stages without supplying their
  respective JDLs (parameters will be deduced from the current one and modified
  accordingly).
* `QADetectorInclude`: string with a list of space-separated detector names to
  be included when generating the QA plots. Leave empty for including all
  detectors. In order to expose it to the job you must add it to `JDLVariables`.
* `QADetectorExclude`: exclude detectors from QA plots. Same format as
  `QADetectorInclude`. Has to be added to `JDLVariables` too.
* `DontArchive`: set it to `1` to store output files, as specified in `Output`,
  as they are, without compressing them. Useful for debug.
* `SaveAll`: set it to `1` to save all files produced by jobs, ignoring `Output`
  completely. Files will not be compressed in zip files. Useful for debug.


Overriding JDL variables
------------------------

AliEn JDL files have variables of type "string" and "list":

    StringVar = "this is a string";
    ListVar = { "this", "is", "a", "list" };

In the most common case you need to override some variables for the local use.
For instance, the variable `OutputDir` represents the AliEn output directory and
does not have any sense locally. You can override every variable by defining a
new variable with the same name and `_override` appended:

    OutputDir = "/alien/path/not/making/sense/locally";
    OutputDir_override = "/home/myuser/joboutput";

The latter will be considered by Makeflow. You can also append to strings and
lists. For instance, the `SplitArguments` variable is a string representing the
arguments to pass to the executable, but in the local scenario you might want to
pass more arguments. Appends work the same as overrides, but you will use the
`_append` name at the end:

    SplitArguments = "--run 244411 --mode full --uid #alien_counter# --nevents 200 --generator Pythia8_Monash2013 --trigger Custom.cfg";
    SplitArguments_append = " --ocdb $OCDB_PATH";

or, you need to provide the input directory with credential informations:

    InputFile = { "LF:/alice/cern.ch/user/a/aliprod/LHC16h8a/Custom.cfg" };
    InputFile_append = { "my-proxy" };

In case you need to change parte of a JDL string variable, you can use `_replace` too like the
following:

    SplitArguments = "--mode full --nevents 400 --generator Pythia8_Monash2013";
    SplitArguments_replace = { "--nevents\\s[0-9]+",
                               "--nevents 1 --ocdb $OCDB_PATH" };

The `_replace` variable is an array with two string elements. The first element is the regular
expression to match, whereas the second is the string replacing the match. First and second args
behave exactly like the _pattern_ and _repl_ arguments of Python's
[`re.sub`](https://docs.python.org/3/library/re.html#re.sub).


Bugs and issues
---------------

This project was originally conceived to run ALICE Monte Carlos locally, or
on local batch farms (including
[Mesos](https://github.com/alisw/mesos-workqueue)!) with Makeflow, using the
exact same JDL files one would use on the AliEn Grid.

Its support is therefore very limited to the ALICE Monte Carlo use cases, but
we are extending it to support more use cases more flexibly.

In case of problems please [open an
issue](https://github.com/alisw/release-validation/issues).
