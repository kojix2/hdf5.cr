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

    def datatype : Datatype
      type_id = LibHDF5.H5Dget_type(@id)
      raise Error.new("Failed to get dataset datatype") if type_id == LibHDF5::H5_INVALID_HID
      Datatype.new(type_id)
    end

    # Crystal-native shape API
    def shape : Array(UInt64)
      dataspace.dims
    end

    def rank : Int32
      dataspace.ndims
    end

    def size : UInt64
      n = dataspace.npoints
      n < 0 ? 0_u64 : n.to_u64
    end

    # HDF5-style aliases
    def dims : Array(UInt64)
      shape
    end

    def ndims : Int32
      rank
    end

    def npoints : Int64
      dataspace.npoints
    end

    def attrs : Attributes
      Attributes.new(@id)
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

    def read(type : T.class, selection : Selection) : Array(T) forall T
      file_space = dataspace
      selection.apply_to(file_space.id)
      n = LibHDF5.H5Sget_select_npoints(file_space.id)
      raise Error.new("Invalid selection") if n <= 0
      mem_space = Dataspace.simple([n.to_u64])
      buf = Array(T).new(n.to_i) { T.zero }
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dread(@id, dtype, mem_space.id, file_space.id,
        LibHDF5::H5P_DEFAULT, buf.to_unsafe.as(Void*))
      mem_space.close
      file_space.close
      raise Error.new("Failed to read dataset with selection") if ret < 0
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

    def write(data : Array(T), selection : Selection) forall T
      file_space = dataspace
      selection.apply_to(file_space.id)
      n = LibHDF5.H5Sget_select_npoints(file_space.id)
      raise ShapeMismatchError.new(
        "Selection covers #{n} points but data has #{data.size} elements"
      ) if data.size != n
      mem_space = Dataspace.simple([n.to_u64])
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dwrite(@id, dtype, mem_space.id, file_space.id,
        LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
      mem_space.close
      file_space.close
      raise Error.new("Failed to write dataset with selection") if ret < 0
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

    def resize(new_shape : Indexable) : Nil
      udims = new_shape.map(&.to_u64).to_a
      ret = LibHDF5.H5Dset_extent(@id, udims.to_unsafe)
      raise Error.new("Failed to resize dataset") if ret < 0
    end

    def storage_size : UInt64
      LibHDF5.H5Dget_storage_size(@id)
    end

    # Backward-compat attribute helpers (delegate to attrs proxy)
    def set_attribute(name : String, value : T) forall T
      attrs[name] = value
    end

    def get_attribute(name : String, type : T.class) : T forall T
      attrs.get(name, T)
    end

    def has_attribute?(name : String) : Bool
      attrs.has_key?(name)
    end

    def close
      LibHDF5.H5Dclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end
  end
end
