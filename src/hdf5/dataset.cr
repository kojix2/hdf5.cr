module HDF5
  class Dataset
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def dataspace : Dataspace
      space_id = LibHDF5.H5Dget_space(@id)
      raise Error.new("Failed to get dataset dataspace") if space_id == LibHDF5::H5_INVALID_HID
      Dataspace.new(space_id)
    end

    def dims : Array(UInt64)
      dataspace.dims
    end

    def ndims : Int32
      dataspace.ndims
    end

    def npoints : Int64
      dataspace.npoints
    end

    def read(type : T.class) : Array(T) forall T
      space = dataspace
      n = space.npoints
      space.close
      raise Error.new("Invalid dataspace") if n < 0
      buf = Array(T).new(n.to_i) { T.zero }
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dread(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, buf.to_unsafe.as(Void*))
      raise Error.new("Failed to read dataset") if ret < 0
      buf
    end

    def read_to(buf : Pointer(T), type : T.class) forall T
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dread(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, buf.as(Void*))
      raise Error.new("Failed to read dataset") if ret < 0
    end

    def write(data : Array(T)) forall T
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dwrite(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
      raise Error.new("Failed to write dataset") if ret < 0
    end

    def write(data : Slice(T)) forall T
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dwrite(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
      raise Error.new("Failed to write dataset") if ret < 0
    end

    def write_strings(data : Array(String))
      type_id = NativeType.variable_length_string
      ptrs = data.map(&.to_unsafe)
      ret = LibHDF5.H5Dwrite(@id, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, ptrs.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to write string dataset") if ret < 0
    end

    def read_strings : Array(String)
      type_id = NativeType.variable_length_string
      space = dataspace
      n = space.npoints
      space.close
      raise Error.new("Invalid dataspace") if n < 0
      ptrs = Array(Pointer(UInt8)).new(n.to_i, Pointer(UInt8).null)
      ret = LibHDF5.H5Dread(@id, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, ptrs.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to read string dataset") if ret < 0
      ptrs.map { |ptr| ptr.null? ? "" : String.new(ptr) }
    end

    def set_attribute(name : String, value : T) forall T
      {% if T < Number %}
        dtype = NativeType.for(T)
        space = Dataspace.scalar
        attr_id = LibHDF5.H5Acreate2(@id, name, dtype, space.id,
          LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
        space.close
        raise Error.new("Failed to create attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
        attr = Attribute.new(attr_id)
        attr.write(value)
        attr.close
      {% elsif T == String %}
        set_string_attribute(name, value)
      {% else %}
        {% raise "Unsupported attribute type: #{T}" %}
      {% end %}
    end

    def get_attribute(name : String, type : T.class) : T forall T
      attr_id = LibHDF5.H5Aopen(@id, name, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to open attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      attr = Attribute.new(attr_id)
      result = attr.read(T)
      attr.close
      result
    end

    def has_attribute?(name : String) : Bool
      LibHDF5.H5Aexists(@id, name) > 0
    end

    def storage_size : UInt64
      LibHDF5.H5Dget_storage_size(@id)
    end

    def close
      LibHDF5.H5Dclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    private def set_string_attribute(name : String, value : String)
      type_id = NativeType.variable_length_string
      space = Dataspace.scalar
      attr_id = LibHDF5.H5Acreate2(@id, name, type_id, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to create string attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      write_type = NativeType.variable_length_string
      ptr = value.to_unsafe
      ret = LibHDF5.H5Awrite(attr_id, write_type, pointerof(ptr).as(Void*))
      LibHDF5.H5Tclose(write_type)
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write string attribute '#{name}'") if ret < 0
    end
  end
end
