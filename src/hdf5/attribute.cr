module HDF5
  class Attribute
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def datatype : Datatype
      ensure_open
      type_id = LibHDF5.H5Aget_type(@id)
      InternalChecks.ensure_hid(type_id, "Failed to get attribute datatype")
      Datatype.new(type_id)
    end

    def dataspace : Dataspace
      ensure_open
      space_id = LibHDF5.H5Aget_space(@id)
      InternalChecks.ensure_hid(space_id, "Failed to get attribute dataspace")
      Dataspace.new(space_id)
    end

    def shape : Array(UInt64)
      with_dataspace(&.dims)
    end

    def rank : Int32
      with_dataspace(&.ndims)
    end

    def size : UInt64
      npoints = with_dataspace(&.npoints)
      npoints < 0 ? 0_u64 : npoints.to_u64
    end

    def scalar? : Bool
      with_dataspace(&.type) == LibHDF5::SpaceClass::Scalar
    end

    def array? : Bool
      with_dataspace(&.type) == LibHDF5::SpaceClass::Simple
    end

    def name : String
      ensure_open
      size = LibHDF5.H5Aget_name(@id, 0, nil)
      raise Error.new("Failed to get attribute name size") if size < 0
      buf = Bytes.new(size + 1)
      LibHDF5.H5Aget_name(@id, LibC::SizeT.new(size + 1), buf.to_unsafe.as(UInt8*))
      String.new(buf[0, size])
    end

    def read(type : T.class) : T forall T
      {% if T == String %}
        read_string
      {% elsif T == HDF5::Reference %}
        read_reference
      {% elsif T < Number %}
        buf = uninitialized T
        dtype = NativeType.for(T)
        read_raw(dtype, pointerof(buf))
        buf
      {% else %}
        {% raise "Unsupported attribute type: #{T}" %}
      {% end %}
    end

    def read_array(type : T.class) : Array(T) forall T
      space_id = LibHDF5.H5Aget_space(@id)
      raise Error.new("Failed to get attribute space") if space_id == LibHDF5::H5_INVALID_HID
      npoints = LibHDF5.H5Sget_simple_extent_npoints(space_id)
      raise Error.new("Invalid npoints") if npoints < 0
      begin
        {% if T == HDF5::Reference %}
          refs = Array(LibHDF5::Reference).new(npoints.to_i) { LibHDF5::Reference.new }
          read_raw(NativeType.for(Reference), refs.to_unsafe)
          refs.map { |ref| Reference.new(ref) }
        {% elsif T < Array %}
          read_vlen_array(T, space_id, npoints.to_i)
        {% else %}
          buf = Array(T).new(npoints.to_i, T.zero)
          dtype = NativeType.for(T)
          read_raw(dtype, buf.to_unsafe)
          buf
        {% end %}
      ensure
        LibHDF5.H5Sclose(space_id)
      end
    end

    def write(value : T) forall T
      {% if T == String %}
        write_string(value)
      {% elsif T == HDF5::Reference %}
        write_reference(value)
      {% elsif T < Number %}
        dtype = NativeType.for(T)
        write_raw(dtype, pointerof(value))
      {% else %}
        {% raise "Unsupported attribute type: #{T}" %}
      {% end %}
    end

    def write_array(data : Array(T)) forall T
      dtype = NativeType.for(T)
      write_raw(dtype, data.to_unsafe)
    end

    def read_raw(type_id : LibHDF5::Hid, buf : Pointer(T)) : Nil forall T
      read_raw_impl(type_id, buf.as(Void*))
    end

    def read_raw(type_id : LibHDF5::Hid, buf : Void*) : Nil
      read_raw_impl(type_id, buf)
    end

    def write_raw(type_id : LibHDF5::Hid, buf : Pointer(T)) : Nil forall T
      write_raw_impl(type_id, buf.as(Void*))
    end

    def write_raw(type_id : LibHDF5::Hid, buf : Void*) : Nil
      write_raw_impl(type_id, buf)
    end

    private def read_raw_impl(type_id : LibHDF5::Hid, buf : Void*) : Nil
      ensure_open
      ret = LibHDF5.H5Aread(@id, type_id, buf)
      raise Error.new("Failed to read attribute") if ret < 0
    end

    private def write_raw_impl(type_id : LibHDF5::Hid, buf : Void*) : Nil
      ensure_open
      ret = LibHDF5.H5Awrite(@id, type_id, buf)
      raise Error.new("Failed to write attribute") if ret < 0
    end

    def close
      LibHDF5.H5Aclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise ClosedObjectError.new("Attribute is closed") if @id == LibHDF5::H5_INVALID_HID
    end

    private def read_string : String
      type_id = LibHDF5.H5Aget_type(@id)
      raise Error.new("Failed to get attribute type") if type_id == LibHDF5::H5_INVALID_HID
      is_vlen = LibHDF5.H5Tis_variable_str(type_id)
      if is_vlen < 0
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to inspect attribute string storage")
      end
      size = LibHDF5.H5Tget_size(type_id)
      if is_vlen > 0
        # For variable-length strings, read into a char** and wrap the pointed string
        space_id = LibHDF5.H5Aget_space(@id)
        if space_id == LibHDF5::H5_INVALID_HID
          LibHDF5.H5Tclose(type_id)
          raise Error.new("Failed to get attribute dataspace")
        end
        ptr = Pointer(UInt8).null
        begin
          read_raw(type_id, pointerof(ptr))
        rescue Error
          LibHDF5.H5Sclose(space_id)
          LibHDF5.H5Tclose(type_id)
          raise Error.new("Failed to read string attribute")
        end

        begin
          ptr.null? ? "" : String.new(ptr)
        ensure
          reclaim = LibHDF5.H5Dvlen_reclaim(type_id, space_id, LibHDF5::H5P_DEFAULT, pointerof(ptr).as(Void*))
          LibHDF5.H5Sclose(space_id)
          LibHDF5.H5Tclose(type_id)
          raise Error.new("Failed to reclaim variable-length attribute string memory") if reclaim < 0
        end
      else
        buf = Bytes.new(size + 1)
        read_raw(type_id, buf.to_unsafe)
        LibHDF5.H5Tclose(type_id)
        String.new(buf.to_unsafe)
      end
    end

    private def write_string(value : String)
      type_id = NativeType.variable_length_string
      ptr = value.to_unsafe
      write_raw(type_id, pointerof(ptr))
      LibHDF5.H5Tclose(type_id)
    end

    private def read_reference : Reference
      ref = uninitialized LibHDF5::Reference
      read_raw(NativeType.for(Reference), pointerof(ref))
      Reference.new(ref)
    end

    private def write_reference(value : Reference)
      ref = value.to_hdf5_reference
      write_raw(NativeType.for(Reference), pointerof(ref))
    end

    private def read_vlen_array(type : Array(T).class, space_id : LibHDF5::Hid, count : Int) : Array(Array(T)) forall T
      type_id = VLenType.for(T)
      vlens = Array(LibHDF5::VLen).new(count) { LibHDF5::VLen.new }
      begin
        read_raw(type_id, vlens.to_unsafe)
        VLenStorage.read(Array(T), type_id, space_id, count, vlens)
      ensure
        LibHDF5.H5Tclose(type_id)
      end
    end

    private def with_dataspace(& : Dataspace -> T) : T forall T
      space = dataspace
      begin
        yield space
      ensure
        space.close
      end
    end
  end
end
