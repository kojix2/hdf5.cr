module HDF5
  class Attribute
    getter id : LibHDF5::Hid
    getter context : FileContext?

    def initialize(@id : LibHDF5::Hid, @context : FileContext? = nil)
      @context.try(&.register(@id, :attribute))
    end

    def hid : LibHDF5::Hid
      ensure_open
      @id
    end

    def datatype : Datatype
      Native.synchronize do
        Datatype.new(InternalChecks.ensure_hid(Native.h5aget_type(hid), "Failed to get attribute type"), context)
      end
    end

    def dataspace : Dataspace
      Native.synchronize do
        Dataspace.new(InternalChecks.ensure_hid(Native.h5aget_space(hid), "Failed to get attribute space"), context)
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

    def scalar? : Bool
      space_class.scalar?
    end

    def array? : Bool
      space_class.simple?
    end

    def null? : Bool
      space_class.null?
    end

    def closed? : Bool
      @id == LibHDF5::H5_INVALID_HID || !!context.try(&.closed?)
    end

    def name : String
      Native.synchronize do
        length = Native.h5aget_name(hid, 0_u64, nil)
        raise Error.new("Failed to get attribute name") if length < 0
        bytes = Bytes.new(length + 1)
        InternalChecks.ensure_herr(Native.h5aget_name(hid, bytes.size.to_u64, bytes.to_unsafe).to_i32, "Failed to get attribute name")
        String.new(bytes[0, length])
      end
    end

    def read(type : T.class, *, casting : Casting = Casting::Unsafe) : T forall T
      Native.synchronize do
        raise ShapeMismatchError.new("Expected scalar attribute; use read_array or read_null") unless scalar?
        read_array(T, casting: casting).first
      end
    end

    def read_array(type : T.class, *, casting : Casting = Casting::Unsafe) : Array(T) forall T
      Native.synchronize do
        Cleanup.with(dataspace) do |space|
          raise ShapeMismatchError.new("Null attributes require read_null") if space.type.null?
          Cleanup.with(datatype) do |dtype|
            Codec.read(:attribute, hid, T, dtype, space.id, LibHDF5::H5S_ALL, Shapes.buffer_count(space.npoints), context, casting)
          end
        end
      end
    end

    def read_null(type : T.class) : Empty(T) forall T
      Native.synchronize do
        raise ShapeMismatchError.new("Expected Null attribute") unless null?
        Cleanup.with(datatype) do |dtype|
          Cleanup.with(TypeFactory.build(T)) { |expected| CastingChecks.check(dtype, expected, Casting::Safe) }
        end
        Empty(T).new
      end
    end

    def write(value : T, *, casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        raise ShapeMismatchError.new("Expected scalar attribute") unless scalar?
        Cleanup.with(datatype) do |dtype|
          CastingChecks.scalar(value, dtype, casting)
          write_array([value])
        end
      end
    end

    def write_array(data : Array(T) | Slice(T), *, casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        Cleanup.with(dataspace) do |space|
          raise ShapeMismatchError.new("Cannot modify Null attribute") if space.type.null?
          raise ShapeMismatchError.new("Attribute element count mismatch") unless data.size == space.npoints
          Cleanup.with(datatype) { |dtype| Codec.write(:attribute, hid, data, dtype, space.id, LibHDF5::H5S_ALL, casting) }
        end
      end
    end

    # Raw access is deliberately unsafe: the caller supplies the native layout
    # and enough capacity for the entire attribute.
    def read_raw(type_id : LibHDF5::Hid, buffer : Pointer(T)) : Nil forall T
      Native.synchronize { Codec.transfer(true, :attribute, hid, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, buffer.as(Void*)) }
    end

    def read_raw(type_id : LibHDF5::Hid, buffer : Void*) : Nil
      Native.synchronize { Codec.transfer(true, :attribute, hid, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, buffer) }
    end

    def write_raw(type_id : LibHDF5::Hid, buffer : Pointer(T)) : Nil forall T
      Native.synchronize { Codec.transfer(false, :attribute, hid, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, buffer.as(Void*)) }
    end

    def write_raw(type_id : LibHDF5::Hid, buffer : Void*) : Nil
      Native.synchronize { Codec.transfer(false, :attribute, hid, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, buffer) }
    end

    def close : Nil
      Native.synchronize do
        if ctx = context
          ctx.close(@id)
        elsif @id != LibHDF5::H5_INVALID_HID
          InternalChecks.ensure_herr(Native.h5aclose(@id), "Failed to close attribute")
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
      raise ClosedObjectError.new("Attribute is closed") if @id == LibHDF5::H5_INVALID_HID
    end
  end
end
