require "./hdf5/lib_hdf5"
require "./hdf5/error"
require "./hdf5/internal_checks"
require "./hdf5/datatype"
require "./hdf5/dataspace"
require "./hdf5/compression"
require "./hdf5/dataset_create_options"
require "./hdf5/selection"
require "./hdf5/attribute"
require "./hdf5/attributes"
require "./hdf5/dataset"
require "./hdf5/typed_dataset"
require "./hdf5/group"
require "./hdf5/file"

module HDF5
  VERSION = "0.1.0"

  def self.open(path : String, mode : Symbol = :r) : File
    File.open(path, mode)
  end

  def self.open(path : String, mode : Symbol = :r, &block : File ->) : Nil
    File.open(path, mode) { |file| block.call(file) }
  end

  def self.accessible?(path : String) : Bool
    File.accessible?(path)
  end

  def self.lib_version : String
    maj = uninitialized UInt32
    min = uninitialized UInt32
    rel = uninitialized UInt32
    LibHDF5.H5get_libversion(pointerof(maj), pointerof(min), pointerof(rel))
    "#{maj}.#{min}.#{rel}"
  end
end
