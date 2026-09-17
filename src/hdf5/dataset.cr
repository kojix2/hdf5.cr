module HDF5
  class Dataset
    getter id : LibHDF5::Hid
    getter context : FileContext?

    def initialize(@id : LibHDF5::Hid, @context : FileContext? = nil)
      @context.try(&.register(@id, :dataset))
    end

    def hid : LibHDF5::Hid
      ensure_open
      @id
    end

    def closed? : Bool
      @id == LibHDF5::H5_INVALID_HID || !!@context.try(&.closed?)
    end

    def dataspace : Dataspace
      Native.synchronize do
        ensure_open
        Dataspace.new(InternalChecks.ensure_hid(Native.h5dget_space(@id), "Failed to get dataspace"), context)
      end
    end

    def datatype : Datatype
      Native.synchronize do
        ensure_open
        Datatype.new(InternalChecks.ensure_hid(Native.h5dget_type(@id), "Failed to get datatype"), context)
      end
    end

    def shape : Array(UInt64)
      Cleanup.with(dataspace, &.dims)
    end

    def rank : Int32
      Cleanup.with(dataspace, &.ndims)
    end

    def size : UInt64
      Cleanup.with(dataspace, &.npoints.to_u64)
    end

    def space_class : LibHDF5::SpaceClass
      Cleanup.with(dataspace, &.type)
    end

    def null? : Bool
      space_class.null?
    end

    def scalar? : Bool
      space_class.scalar?
    end

    def attrs : Attributes
      ensure_open
      Attributes.new(@id, context)
    end

    def read(type : T.class, selection : Selection? = nil, *,
             casting : Casting = Casting::Unsafe) : Array(T) forall T
      Native.synchronize do
        with_selection(selection) do |file, memory, count|
          Cleanup.with(datatype) do |dtype|
            Codec.read(:dataset, @id, T, dtype, memory.id, file.id, count, context, casting)
          end
        end
      end
    end

    def read_scalar(type : T.class, selection : Selection? = nil, *,
                    casting : Casting = Casting::Unsafe) : T forall T
      Native.synchronize do
        scalar = selection ? selection.result_shape(shape).empty? : scalar?
        raise ShapeMismatchError.new("Expected a scalar dataspace or selection") unless scalar
        read(T, selection, casting: casting).first
      end
    end

    def read_null(type : T.class) : Empty(T) forall T
      raise ShapeMismatchError.new("Expected Null dataspace") unless null?
      Cleanup.with(datatype) do |dtype|
        Cleanup.with(TypeFactory.build(T)) do |expected|
          CastingChecks.check(dtype, expected, Casting::Safe)
        end
      end
      Empty(T).new
    end

    def read_into(buffer : Slice(T), selection : Selection? = nil, *,
                  casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        with_selection(selection) do |file, memory, count|
          raise ShapeMismatchError.new("Buffer length does not match selection") unless buffer.size == count
          {% if T == String || T == Reference || T < Array || T == Bool || T == Complex || T == Complex32 %}
            values = read(T, selection, casting: casting)
            values.each_with_index { |value, i| buffer[i] = value }
          {% else %}
            Cleanup.with(datatype) do |stored|
              Cleanup.with(TypeFactory.build(T)) do |dtype|
                CastingChecks.check(stored, dtype, casting)
                Codec.transfer(true, :dataset, @id, dtype.id, memory.id, file.id, buffer.to_unsafe.as(Void*)) unless count == 0
              end
            end
          {% end %}
        end
      end
    end

    # Compatibility name for the checked buffer API.
    def read_to(buffer : Slice(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil forall T
      read_into(buffer, selection, casting: casting)
    end

    # Low-level API: the caller owns capacity and native representation checks.
    def read_to(buffer : Pointer(T), type : T.class) : Nil forall T
      Native.synchronize do
        ensure_open
        raise ShapeMismatchError.new("Cannot read a Null dataset into a buffer") if null?
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          Codec.transfer(true, :dataset, @id, dtype.id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, buffer.as(Void*))
        end
      end
    end

    def write(data : Slice(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil forall T
      write_buffer(data, selection, casting)
    end

    def append(data : Slice(T), *, shape : Indexable? = nil, axis : Int = 0, casting : Casting = Casting::Unsafe) : Nil forall T
      append(data.to_a, shape: shape, axis: axis, casting: casting)
    end

    def write(data : Array(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil forall T
      write_buffer(data, selection, casting)
    end

    private def write_buffer(data : Array(T) | Slice(T), selection : Selection?, casting : Casting) : Nil forall T
      Native.synchronize do
        with_selection(selection) do |file, memory, count|
          raise ShapeMismatchError.new("Data has #{data.size} elements; selection has #{count}") unless data.size == count
          Cleanup.with(datatype) do |dtype|
            Codec.write(:dataset, @id, data, dtype, memory.id, file.id, casting)
          end
        end
      end
    end

    def write(value : T, selection : Selection? = nil, *,
              casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        ensure_open
        raise ShapeMismatchError.new("Cannot write to a Null dataset") if null?
        Cleanup.with(datatype) do |dtype|
          CastingChecks.scalar(value, dtype, casting)
          {% if T == String %}
            Codec.validate_strings([value], dtype.string_encoding)
          {% end %}
          target = selection || HDF5.s[]
          bytes = {% if T == String %} Math.max(value.bytesize + sizeof(Pointer(UInt8)), 1) {% else %} sizeof(T) {% end %}
          dimensions = shape
          total = Shapes.count(target.result_shape(dimensions))
          return if total == 0
          budget = Math.max(256 * 1024 // bytes, 1)
          length = Math.min(total, budget.to_u64).to_i
          buffer = Slice(T).new(length, value)
          target.each_tile(dimensions, budget) do |tile|
            count = Shapes.count(tile.result_shape(dimensions)).to_i
            write(buffer[0, count], tile)
          end
        end
      end
    end

    def write(value : Empty(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil forall T
      ensure_open
      raise ShapeMismatchError.new("Empty values are only supported when creating a Null dataset")
    end

    def write_strings(data : Array(String)) : Nil
      write(data)
    end

    def read_strings : Array(String)
      read(String)
    end

    def chunk : Array(UInt64)?
      Native.synchronize do
        with_creation_properties do |properties|
          layout = Native.h5pget_layout(properties)
          raise Error.new("Failed to get storage layout") if layout < 0
          if layout == 2
            dims = Array(UInt64).new(rank, 0_u64)
            InternalChecks.ensure_herr(Native.h5pget_chunk(properties, dims.size, dims.to_unsafe), "Failed to get chunks")
            dims
          end
        end
      end
    end

    def max_shape : Array(UInt64?)
      Native.synchronize do
        Cleanup.with(dataspace) do |space|
          dims = Array(UInt64).new(space.ndims, 0_u64)
          maximum = Array(UInt64).new(space.ndims, 0_u64)
          InternalChecks.ensure_herr(Native.h5sget_simple_extent_dims(space.id, dims.to_unsafe, maximum.to_unsafe), "Failed to get maximum shape")
          maximum.map { |dim| dim == UInt64::MAX ? nil : dim }
        end
      end
    end

    def fill_value(type : T.class, *, casting : Casting = Casting::Unsafe) : T forall T
      Native.synchronize do
        with_creation_properties do |properties|
          Cleanup.with(datatype) do |dtype|
            Cleanup.with(Dataspace.scalar) do |memory|
              Codec.read(:fill, properties, T, dtype, memory.id, LibHDF5::H5S_ALL, 1, casting: casting).first
            end
          end
        end
      end
    end

    def resize(new_shape : Indexable) : Nil
      Native.synchronize do
        ensure_open
        raise ShapeMismatchError.new("Only simple datasets can be resized") unless space_class.simple?
        dims = Shapes.normalize(new_shape)
        raise ShapeMismatchError.new("Resize rank mismatch") unless dims.size == rank
        Shapes.count(dims)
        max_shape.each_with_index do |limit, i|
          raise ShapeMismatchError.new("Resize exceeds maximum dimension") if limit && dims[i] > limit
        end
        raise ShapeMismatchError.new("Resize requires chunked storage") unless chunk
        InternalChecks.ensure_herr(Native.h5dset_extent(@id, dims.to_unsafe), "Failed to resize dataset")
      end
    end

    def append(data : Array(T), *, shape : Indexable? = nil, axis : Int = 0,
               casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        raise ShapeMismatchError.new("Append requires a simple dataspace") unless space_class.simple?
        original = self.shape
        raise IndexError.new("Append axis out of bounds") unless 0 <= axis < original.size
        incoming = if shape
                     Shapes.normalize(shape)
                   elsif original.size == 1
                     [data.size.to_u64]
                   else
                     raise ShapeMismatchError.new("Multidimensional append requires shape")
                   end
        raise ShapeMismatchError.new("Append rank mismatch") unless incoming.size == original.size
        incoming.each_with_index do |dim, i|
          raise ShapeMismatchError.new("Append dimensions must match outside axis") if i != axis && dim != original[i]
        end
        Shapes.validate_count(incoming, data.size)
        Cleanup.with(datatype) do |dtype|
          Cleanup.with(TypeFactory.build(T)) { |source| CastingChecks.check(source, dtype, casting) }
          {% if T == String %}
            Codec.validate_strings(data, dtype, casting)
          {% end %}
        end
        return if incoming[axis] == 0
        extended = original.dup
        extended[axis] += incoming[axis]
        resize(extended)
        start = Array(UInt64).new(original.size, 0_u64)
        start[axis] = original[axis]
        begin
          write(data, Selection.hyperslab(start, incoming), casting: casting)
        rescue exception
          begin
            resize(original)
          rescue error
            raise Error.new("Append write failed and extent rollback failed: #{error.message}", cause: exception)
          end
          raise exception
        end
      end
    end

    def each_block(type : T.class, *, max_bytes : Int, casting : Casting = Casting::Unsafe,
                   &block : Selection, Array(T) ->) : Nil forall T
      ensure_open
      raise ShapeMismatchError.new("Cannot iterate a Null dataset") if null?
      callback = block
      {% if T < Array %}
        raise TypeMismatchError.new("Cannot bound variable-length data in bytes")
      {% else %}
        {% if T == String %}
          bytes = Cleanup.with(datatype) do |dtype|
            raise TypeMismatchError.new("Cannot bound variable-length strings in bytes") unless dtype.fixed_length_string?
            dtype.size
          end
        {% else %}
          bytes = sizeof(T)
        {% end %}
        raise ArgumentError.new("Byte budget is smaller than one element") if max_bytes < bytes
        dimensions = shape
        blocks = Selection.block_shape(dimensions, Math.min(max_bytes // bytes, Int32::MAX).to_i)
        Selection.each_region(dimensions, blocks) do |selection|
          callback.call(selection, read(T, selection, casting: casting))
        end
      {% end %}
    end

    def each_chunk(type : T.class, *, casting : Casting = Casting::Unsafe,
                   &block : Selection, Array(T) ->) : Nil forall T
      dimensions = shape
      chunks = chunk || raise ShapeMismatchError.new("Chunk iteration requires chunked storage")
      Selection.each_region(dimensions, chunks) do |selection|
        block.call(selection, read(T, selection, casting: casting))
      end
    end

    def storage_size : UInt64
      Native.synchronize do
        ensure_open
        Native.h5dget_storage_size(@id)
      end
    end

    def close : Nil
      Native.synchronize do
        if ctx = context
          ctx.close(@id)
        elsif @id != LibHDF5::H5_INVALID_HID
          InternalChecks.ensure_herr(Native.h5dclose(@id), "Failed to close dataset")
        end
        @id = LibHDF5::H5_INVALID_HID
      end
    end

    def finalize
      close
    rescue
    end

    private def ensure_open : Nil
      context.try(&.ensure_open(@id))
      raise ClosedObjectError.new("Dataset is closed") if @id == LibHDF5::H5_INVALID_HID
    end

    private def with_selection(selection : Selection?, &)
      Cleanup.with(dataspace) do |file|
        raise ShapeMismatchError.new("Null datasets require read_null") if file.type.null?
        count = selection ? selection.npoints(file.id) : file.npoints
        memory = file.type.scalar? ? Dataspace.scalar : Dataspace.simple([count.to_u64])
        Cleanup.with(memory) { |space| yield file, space, Shapes.buffer_count(count) }
      end
    end

    private def with_creation_properties(&)
      ensure_open
      properties = InternalChecks.ensure_hid(Native.h5dget_create_plist(@id), "Failed to get creation properties")
      begin
        yield properties
      ensure
        Native.h5pclose(properties)
      end
    end
  end
end
