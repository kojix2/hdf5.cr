module HDF5
  class DatasetCreateOptions
    property chunk : Array(UInt64) | Symbol?
    property compression : Compression?
    property? shuffle : Bool
    property? fletcher32 : Bool
    property max_shape : Array(UInt64)?

    def initialize(chunk : Indexable | Symbol? = nil,
                   @compression : Compression? = nil, @shuffle : Bool = false,
                   @fletcher32 : Bool = false, max_shape : Indexable? = nil)
      @chunk = chunk.is_a?(Indexable) ? Shapes.normalize(chunk) : chunk
      @max_shape = max_shape ? Shapes.maxima(max_shape) : nil
    end

    def validate(shape : Array(UInt64), dtype : Datatype) : Nil
      Shapes.count(shape)
      validate_max_shape(shape)
      if chunks = resolved_chunk(shape, dtype.size)
        validate_chunk(shape, chunks, dtype.size)
      end
      validate_filters(dtype)
    end

    private def validate_max_shape(shape : Array(UInt64)) : Nil
      if maximum = max_shape
        raise ShapeMismatchError.new("Maximum shape rank mismatch") unless maximum.size == shape.size
        shape.each_with_index do |dim, i|
          raise ShapeMismatchError.new("Maximum dimension smaller than shape") if maximum[i] < dim
        end
      end
    end

    private def validate_chunk(shape : Array(UInt64), chunks : Array(UInt64), itemsize : Int) : Nil
      raise ShapeMismatchError.new("Chunking requires a simple dataspace") if shape.empty?
      raise ShapeMismatchError.new("Chunk rank mismatch") unless chunks.size == shape.size
      raise ShapeMismatchError.new("Chunk dimensions must be positive") if chunks.any?(&.zero?)
      raise ShapeMismatchError.new("Chunk exceeds HDF5's 4 GiB limit") if Shapes.count(chunks) > ((1_u64 << 32) - 1) // itemsize
      maximum = max_shape || shape
      chunks.each_with_index do |dim, i|
        limit = maximum[i]
        raise ShapeMismatchError.new("Chunk exceeds maximum dimension") if limit > 0 && limit != UInt64::MAX && dim > limit
      end
    end

    private def validate_filters(dtype : Datatype) : Nil
      if dtype.variable_length_string? || dtype.vlen?
        raise TypeMismatchError.new("Fletcher32 cannot be used with variable-length storage") if fletcher32?
      end
      if comp = compression
        if comp.filter.g_zip?
          raise ArgumentError.new("Gzip level must be between 0 and 9") unless 0 <= comp.level <= 9
          check_filter(1)
        end
      end
      check_filter(2) if shuffle?
      check_filter(3) if fletcher32?
    end

    def resolved_chunk(shape : Array(UInt64), itemsize : Int) : Array(UInt64)?
      case value = chunk
      when Array(UInt64)
        value
      when Symbol
        raise ArgumentError.new("Unknown chunk policy: #{value}") unless value == :auto
        automatic_chunk(shape, itemsize)
      when Nil
        if (compression && !compression.try(&.none?)) || shuffle? || fletcher32? ||
           (max_shape && max_shape != shape)
          automatic_chunk(shape, itemsize)
        end
      end
    end

    def apply_to(dcpl_id : LibHDF5::Hid, shape : Array(UInt64), itemsize : Int = 8) : Nil
      if chunks = resolved_chunk(shape, itemsize)
        check(Native.h5pset_chunk(dcpl_id, chunks.size, chunks.to_unsafe), "chunking")
      end
      check(Native.h5pset_shuffle(dcpl_id), "shuffle") if shuffle?
      if comp = compression
        check(Native.h5pset_deflate(dcpl_id, comp.level.to_u32), "gzip") if comp.filter.g_zip?
      end
      check(Native.h5pset_fletcher32(dcpl_id), "Fletcher32") if fletcher32?
    end

    private def automatic_chunk(shape, itemsize) : Array(UInt64)
      Selection.block_shape(shape, Math.max(256 * 1024 // itemsize, 1))
    end

    private def check(status, name)
      InternalChecks.ensure_herr(status, "Failed to configure #{name}")
    end

    private def check_filter(filter : Int32)
      raise Error.new("HDF5 filter #{filter} is unavailable") unless InternalChecks.ensure_htri(Native.h5zfilter_avail(filter), "Failed to inspect filter")
      flags = 0_u32
      check(Native.h5zget_filter_info(filter, pointerof(flags)), "filter availability")
      raise Error.new("HDF5 filter #{filter} cannot encode data") if flags & 1 == 0
    end
  end
end
