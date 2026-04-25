module HDF5
  class Attribute
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def name : String
      size = LibHDF5.H5Aget_name(@id, 0, nil)
      raise Error.new("Failed to get attribute name size") if size < 0
      buf = Bytes.new(size + 1)
      LibHDF5.H5Aget_name(@id, LibC::SizeT.new(size + 1), buf.to_unsafe.as(UInt8*))
      String.new(buf[0, size])
    end

    def read(type : T.class) : T forall T
      {% if T == String %}
        read_string
      {% elsif T < Number %}
        buf = uninitialized T
        dtype = NativeType.for(T)
        ret = LibHDF5.H5Aread(@id, dtype, pointerof(buf).as(Void*))
        raise Error.new("Failed to read attribute") if ret < 0
        buf
      {% else %}
        {% raise "Unsupported attribute type: #{T}" %}
      {% end %}
    end

    def read_array(type : T.class) : Array(T) forall T
      space_id = LibHDF5.H5Aget_space(@id)
      raise Error.new("Failed to get attribute space") if space_id == LibHDF5::H5_INVALID_HID
      npoints = LibHDF5.H5Sget_simple_extent_npoints(space_id)
      LibHDF5.H5Sclose(space_id)
      raise Error.new("Invalid npoints") if npoints < 0
      buf = Array(T).new(npoints.to_i, T.zero)
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Aread(@id, dtype, buf.to_unsafe.as(Void*))
      raise Error.new("Failed to read attribute array") if ret < 0
      buf
    end

    def write(value : T) forall T
      {% if T == String %}
        write_string(value)
      {% elsif T < Number %}
        dtype = NativeType.for(T)
        ret = LibHDF5.H5Awrite(@id, dtype, pointerof(value).as(Void*))
        raise Error.new("Failed to write attribute") if ret < 0
      {% else %}
        {% raise "Unsupported attribute type: #{T}" %}
      {% end %}
    end

    def write_array(data : Array(T)) forall T
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Awrite(@id, dtype, data.to_unsafe.as(Void*))
      raise Error.new("Failed to write attribute array") if ret < 0
    end

    def close
      LibHDF5.H5Aclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    private def read_string : String
      type_id = LibHDF5.H5Aget_type(@id)
      raise Error.new("Failed to get attribute type") if type_id == LibHDF5::H5_INVALID_HID
      is_vlen = LibHDF5.H5Tis_variable_str(type_id)
      size = LibHDF5.H5Tget_size(type_id)
      if is_vlen > 0
        # For variable-length strings, read into a char** and wrap the pointed string
        ptr = Pointer(UInt8).null
        ret = LibHDF5.H5Aread(@id, type_id, pointerof(ptr).as(Void*))
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to read string attribute") if ret < 0
        ptr.null? ? "" : String.new(ptr)
      else
        buf = Bytes.new(size + 1)
        ret = LibHDF5.H5Aread(@id, type_id, buf.to_unsafe.as(Void*))
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to read string attribute") if ret < 0
        String.new(buf.to_unsafe)
      end
    end

    private def write_string(value : String)
      type_id = NativeType.variable_length_string
      ptr = value.to_unsafe
      ret = LibHDF5.H5Awrite(@id, type_id, pointerof(ptr).as(Void*))
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to write string attribute") if ret < 0
    end
  end
end
