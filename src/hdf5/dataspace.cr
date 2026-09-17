module HDF5
  class Dataspace
    getter id : LibHDF5::Hid
    getter context : FileContext?

    def initialize(@id : LibHDF5::Hid, @context : FileContext? = nil)
      @context.try(&.register(@id, :dataspace))
    end

    def self.scalar : Dataspace
      Native.synchronize do
        id = Native.h5screate(LibHDF5::SpaceClass::Scalar)
        raise Error.new("Failed to create scalar dataspace") if id == LibHDF5::H5_INVALID_HID
        new(id)
      end
    end

    def self.null : Dataspace
      Native.synchronize do
        id = Native.h5screate(LibHDF5::SpaceClass::Null)
        raise Error.new("Failed to create null dataspace") if id == LibHDF5::H5_INVALID_HID
        new(id)
      end
    end

    def self.simple(dims : Array(UInt64), max_dims : Array(UInt64)? = nil) : Dataspace
      Native.synchronize do
        rank = dims.size
        Shapes.count(dims)
        raise ShapeMismatchError.new("Too many dimensions") if rank > 32
        raise ShapeMismatchError.new("Maximum shape rank mismatch") if max_dims && max_dims.size != rank
        if max_dims
          dims.each_with_index { |dim, i| raise ShapeMismatchError.new("Maximum shape is smaller than shape") if max_dims[i] < dim }
        end
        return scalar if rank == 0
        mdims = max_dims || dims
        id = Native.h5screate_simple(rank, dims.to_unsafe, mdims.to_unsafe)
        raise Error.new("Failed to create simple dataspace") if id == LibHDF5::H5_INVALID_HID
        new(id)
      end
    end

    def self.simple(*dims : Int) : Dataspace
      Native.synchronize do
        udims = Shapes.normalize(dims)
        simple(udims)
      end
    end

    def ndims : Int32
      Native.synchronize do
        ensure_open
        rank = Native.h5sget_simple_extent_ndims(@id)
        raise Error.new("Failed to get dataspace rank") if rank < 0
        rank
      end
    end

    def dims : Array(UInt64)
      Native.synchronize do
        n = ndims
        return [] of UInt64 if n <= 0
        dims_buf = Array(UInt64).new(n, 0u64)
        InternalChecks.ensure_herr(Native.h5sget_simple_extent_dims(@id, dims_buf.to_unsafe, nil), "Failed to get shape")
        dims_buf
      end
    end

    def npoints : Int64
      Native.synchronize do
        ensure_open
        n = Native.h5sget_simple_extent_npoints(@id)
        raise Error.new("Failed to get element count") if n < 0
        n
      end
    end

    def type : LibHDF5::SpaceClass
      Native.synchronize do
        ensure_open
        Native.h5sget_simple_extent_type(@id)
      end
    end

    def close
      Native.synchronize do
        if ctx = @context
          ctx.close(@id)
        elsif @id != LibHDF5::H5_INVALID_HID
          InternalChecks.ensure_herr(Native.h5sclose(@id), "Failed to close dataspace")
        end
        @id = LibHDF5::H5_INVALID_HID
      end
    end

    def finalize
      close
    rescue
    end

    private def ensure_open
      @context.try(&.ensure_open(@id))
      raise ClosedObjectError.new("Dataspace is closed") if @id == LibHDF5::H5_INVALID_HID
    end
  end
end
