module HDF5
  class DatasetCreateOptions
    property chunk : Array(UInt64)?
    property compression : Compression?
    property? shuffle : Bool
    property? fletcher32 : Bool
    property max_shape : Array(UInt64)?

    def initialize(
      @chunk : Array(UInt64)? = nil,
      @compression : Compression? = nil,
      @shuffle : Bool = false,
      @fletcher32 : Bool = false,
      @max_shape : Array(UInt64)? = nil,
    )
    end

    def apply_to(dcpl_id : LibHDF5::Hid, shape : Array(UInt64)) : Nil
      chunks = @chunk || shape
      LibHDF5.H5Pset_chunk(dcpl_id, chunks.size, chunks.to_unsafe)
      if (comp = @compression) && !comp.none?
        case comp.filter
        in Compression::Filter::GZip
          LibHDF5.H5Pset_shuffle(dcpl_id) if @shuffle
          LibHDF5.H5Pset_deflate(dcpl_id, comp.level.to_u32)
        in Compression::Filter::None
          # nothing
        end
      elsif @shuffle
        LibHDF5.H5Pset_shuffle(dcpl_id)
      end
      LibHDF5.H5Pset_fletcher32(dcpl_id) if @fletcher32
    end
  end
end
