Building and publishing
=======================

Update the tag in `setup.py`, then build a source distribution:

    rm -rf build/ dist/ alien_jdl2makeflow.egg-info/
    python setup.py build sdist

Publish it on PyPi:

    twine upload dist/*
