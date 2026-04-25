require "./hdf5/lib_hdf5"
require "./hdf5/error"
require "./hdf5/datatype"
require "./hdf5/dataspace"
require "./hdf5/attribute"
require "./hdf5/dataset"
require "./hdf5/group"
require "./hdf5/file"

module HDF5
  VERSION = "0.1.0"

  def self.lib_version : String
    maj = uninitialized UInt32
    min = uninitialized UInt32
    rel = uninitialized UInt32
    LibHDF5.H5get_libversion(pointerof(maj), pointerof(min), pointerof(rel))
    "#{maj}.#{min}.#{rel}"
  end
end
