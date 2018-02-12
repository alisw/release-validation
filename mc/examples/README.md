Examples
========

This directory contains JDLs for two general purpose Monte Carlos:

* `gpmc_LHC15n` (anchored to LHC15n)
* `gpmc_LHC17m` (anchored to LHC17m)

Every directory contains a JDL file (the original one running on the Grid, plus additional
information for local runs at the end), plus a `Custom.cfg` file for triggers, imported from AliEn.


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
that, the Final QA is run, and the filtered trees merging.

Filtered trees merging simply merges ROOT files called `FilterEvents_Trees.root` produced by every
MC job. Output is found under:

    SpacePointCalibrationMerge/001/spcm_archive.zip

which, in turn, contains the merged ROOT file. The `SpacePointCalibrationMerge` name is there for
historical reasons even if no space point calibration is performed in Monte Carlos.

The Final QA stage runs the merging for single jobs QA results, and also runs the plots generation.

Plots will be found under:

    QAplots_passMC/ITS/2016/LHC16h8a/passMC/000244411

that is,

    QAplots_passMC/<detector>/<year>/<period>/passMC/<run>
