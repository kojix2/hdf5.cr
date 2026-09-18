require "spec"
require "../src/hdf5"

# Disable HDF5's automatic error printing to stderr
LibHDF5.H5open
LibHDF5.H5Eset_auto2(0, nil, nil)

TMP_FILE = File.join(Dir.tempdir, "hdf5_spec_#{Process.pid}.h5")
EXT_FILE = File.join(Dir.tempdir, "hdf5_ext_spec_#{Process.pid}.h5")

module SpecSupport
  def self.create_raw_dataset(file : HDF5::File, name : String, type_id : LibHDF5::Hid,
                              dims : Array(UInt64) = [1_u64]) : Nil
    space_id = LibHDF5.H5Screate_simple(dims.size, dims.to_unsafe, nil)
    raise "Failed to create dataspace for #{name}" if space_id == LibHDF5::H5_INVALID_HID

    dataset_id = LibHDF5.H5Dcreate2(file.id, name, type_id, space_id,
      LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
    raise "Failed to create dataset #{name}" if dataset_id == LibHDF5::H5_INVALID_HID
  ensure
    LibHDF5.H5Dclose(dataset_id) if dataset_id && dataset_id != LibHDF5::H5_INVALID_HID
    LibHDF5.H5Sclose(space_id) if space_id && space_id != LibHDF5::H5_INVALID_HID
  end
end
