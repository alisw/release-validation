Example: a full ALICE Monte Carlo simulation
============================================

This directory contains the following files:

* `example.jdl`: the JDL describing our Monte Carlo job derived from [an actual ALICE Monte Carlo
    production](https://alice.its.cern.ch/jira/browse/ALIROOT-6827)
* `Custom.cfg`: a Monte Carlo configuration file imported from AliEn (see the JDL)


Requirements
------------

To quickly run this example your machine must have access to CVMFS packages, and the CVMFS OCDB:

    /cvmfs/alice.cern.ch
    /cvmfs/alice-ocdb.cern.ch

It is also possible to run it without CVMFS and a local package set with some tuning. No AliEn
access is required at all!

Makeflow is needed too.


Run it
------

Clean the old output if you want:

    rm -rf /tmp/mc_test

Run and re-run it:

    jdl2makeflow --force example.jdl
    cd work/
    makeflow

Makeflow will attempt to run as many jobs in parallel as possible. In our case we have 16 jobs.

Have a look at `/tmp/mc_test` for the output.


Workflow
--------

Workflow is constituted by several ALICE MC jobs (doing everything up to the AOD filtering). After
that, the Final QA is run, and the merging of the Space Point Calibration.

Space point calibration merging simply merges ROOT files called `FilterEvents_Trees.root` produced
by every MC job. Output is found under:

    SpacePointCalibrationMerge/spcm_archive.zip

which, in turn, contains the merged ROOT file.

The Final QA stage runs the merging for single jobs QA results, and also runs the plots generation.

Plots will be found under:

    QAplots_passMC/ITS/2016/LHC16h8a/passMC/000244411

that is,

    QAplots_passMC/<detector>/<year>/<period>/passMC/<run>
