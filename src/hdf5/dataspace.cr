module HDF5
  class Dataspace
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def self.scalar : Dataspace
      id = LibHDF5.H5Screate(LibHDF5::SpaceClass::Scalar)
      raise Error.new("Failed to create scalar dataspace") if id == LibHDF5::H5_INVALID_HID
      new(id)
    end

    def self.null : Dataspace
      id = LibHDF5.H5Screate(LibHDF5::SpaceClass::Null)
      raise Error.new("Failed to create null dataspace") if id == LibHDF5::H5_INVALID_HID
      new(id)
    end

    def self.simple(dims : Array(UInt64), max_dims : Array(UInt64)? = nil) : Dataspace
      rank = dims.size
      mdims = max_dims || dims
      id = LibHDF5.H5Screate_simple(rank, dims.to_unsafe, mdims.to_unsafe)
      raise Error.new("Failed to create simple dataspace") if id == LibHDF5::H5_INVALID_HID
      new(id)
    end

    def self.simple(*dims : Int) : Dataspace
      udims = dims.map(&.to_u64).to_a
      simple(udims)
    end

    def ndims : Int32
      LibHDF5.H5Sget_simple_extent_ndims(@id)
    end

    def dims : Array(UInt64)
      n = ndims
      return [] of UInt64 if n <= 0
      dims_buf = Array(UInt64).new(n, 0u64)
      LibHDF5.H5Sget_simple_extent_dims(@id, dims_buf.to_unsafe, nil)
      dims_buf
    end

    def npoints : Int64
      LibHDF5.H5Sget_simple_extent_npoints(@id)
    end

    def type : LibHDF5::SpaceClass
      LibHDF5.H5Sget_simple_extent_type(@id)
    end

    def close
      LibHDF5.H5Sclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end
  end
end
