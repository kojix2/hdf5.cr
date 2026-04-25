require "spec"
require "../src/hdf5"

# Disable HDF5's automatic error printing to stderr
LibHDF5.H5open
LibHDF5.H5Eset_auto2(0, nil, nil)
