module HDF5
  class Dataset
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def dataspace : Dataspace
      ensure_open
      space_id = LibHDF5.H5Dget_space(@id)
      InternalChecks.ensure_hid(space_id, "Failed to get dataset dataspace")
      Dataspace.new(space_id)
    end

    def datatype : Datatype
      ensure_open
      type_id = LibHDF5.H5Dget_type(@id)
      InternalChecks.ensure_hid(type_id, "Failed to get dataset datatype")
      Datatype.new(type_id)
    end

    # Crystal-native shape API
    def shape : Array(UInt64)
      space = dataspace
      begin
        space.dims
      ensure
        space.close
      end
    end

    def rank : Int32
      space = dataspace
      begin
        space.ndims
      ensure
        space.close
      end
    end

    def size : UInt64
      space = dataspace
      begin
        n = space.npoints
        n < 0 ? 0_u64 : n.to_u64
      ensure
        space.close
      end
    end

    def attrs : Attributes
      ensure_open
      Attributes.new(@id)
    end

    def read(type : T.class) : Array(T) forall T
      space = dataspace
      n = space.npoints
      space.close
      raise Error.new("Invalid dataspace") if n < 0
      {% if T == HDF5::ObjectReference %}
        refs = Array(LibHDF5::Reference).new(n.to_i) { LibHDF5::Reference.new }
        dtype = NativeType.for(ObjectReference)
        ret = LibHDF5.H5Dread(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, refs.to_unsafe.as(Void*))
        raise Error.new("Failed to read object reference dataset") if ret < 0
        refs.map { |ref| ObjectReference.new(ref) }
      {% else %}
        buf = Array(T).new(n.to_i) { T.zero }
        dtype = NativeType.for(T)
        ret = LibHDF5.H5Dread(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, buf.to_unsafe.as(Void*))
        raise Error.new("Failed to read dataset") if ret < 0
        buf
      {% end %}
    end

    def read(type : T.class, selection : Selection) : Array(T) forall T
      file_space = dataspace
      begin
        selection.apply_to(file_space.id)
        n = LibHDF5.H5Sget_select_npoints(file_space.id)
        raise Error.new("Invalid selection") if n <= 0
        mem_space = Dataspace.simple([n.to_u64])
        {% if T == HDF5::ObjectReference %}
          refs = Array(LibHDF5::Reference).new(n.to_i) { LibHDF5::Reference.new }
          dtype = NativeType.for(ObjectReference)
          ret = LibHDF5.H5Dread(@id, dtype, mem_space.id, file_space.id,
            LibHDF5::H5P_DEFAULT, refs.to_unsafe.as(Void*))
          mem_space.close
          raise Error.new("Failed to read dataset with selection") if ret < 0
          refs.map { |ref| ObjectReference.new(ref) }
        {% else %}
          buf = Array(T).new(n.to_i) { T.zero }
          dtype = NativeType.for(T)
          ret = LibHDF5.H5Dread(@id, dtype, mem_space.id, file_space.id,
            LibHDF5::H5P_DEFAULT, buf.to_unsafe.as(Void*))
          mem_space.close
          raise Error.new("Failed to read dataset with selection") if ret < 0
          buf
        {% end %}
      ensure
        file_space.close
      end
    end

    def read_to(buf : Pointer(T), type : T.class) forall T
      ensure_open
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dread(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, buf.as(Void*))
      raise Error.new("Failed to read dataset") if ret < 0
    end

    def write(data : Array(T)) forall T
      ensure_open
      {% if T == HDF5::ObjectReference %}
        dtype = NativeType.for(ObjectReference)
        refs = data.map(&.ref)
        ret = LibHDF5.H5Dwrite(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, refs.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset") if ret < 0
      {% else %}
        dtype = NativeType.for(T)
        ret = LibHDF5.H5Dwrite(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset") if ret < 0
      {% end %}
    end

    def write(data : Slice(T)) forall T
      ensure_open
      dtype = NativeType.for(T)
      ret = LibHDF5.H5Dwrite(@id, dtype, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
      raise Error.new("Failed to write dataset") if ret < 0
    end

    def write(data : Array(T), selection : Selection) forall T
      file_space = dataspace
      begin
        selection.apply_to(file_space.id)
        n = LibHDF5.H5Sget_select_npoints(file_space.id)
        raise ShapeMismatchError.new(
          "Selection covers #{n} points but data has #{data.size} elements"
        ) if data.size != n
        mem_space = Dataspace.simple([n.to_u64])
        {% if T == HDF5::ObjectReference %}
          dtype = NativeType.for(ObjectReference)
          refs = data.map(&.ref)
          ret = LibHDF5.H5Dwrite(@id, dtype, mem_space.id, file_space.id,
            LibHDF5::H5P_DEFAULT, refs.to_unsafe.as(Void*))
          mem_space.close
          raise Error.new("Failed to write dataset with selection") if ret < 0
        {% else %}
          dtype = NativeType.for(T)
          ret = LibHDF5.H5Dwrite(@id, dtype, mem_space.id, file_space.id,
            LibHDF5::H5P_DEFAULT, data.to_unsafe.as(Void*))
          mem_space.close
          raise Error.new("Failed to write dataset with selection") if ret < 0
        {% end %}
      ensure
        file_space.close
      end
    end

    def write_strings(data : Array(String))
      file_type = datatype
      raise Error.new("Dataset is not string type") unless file_type.string?

      if file_type.variable_length_string?
        write_type = StringType.variable(encoding: file_type.string_encoding,
          padding: file_type.string_padding).to_hdf5_type_id
        ptrs = data.map(&.to_unsafe)
        ret = LibHDF5.H5Dwrite(@id, write_type, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, ptrs.to_unsafe.as(Void*))
        LibHDF5.H5Tclose(write_type)
        file_type.close
        raise Error.new("Failed to write string dataset") if ret < 0
        return
      end

      unless file_type.fixed_length_string?
        file_type.close
        raise Error.new("Unsupported string dataset storage")
      end

      element_size = file_type.size
      write_type = StringType.fixed(element_size,
        encoding: file_type.string_encoding,
        padding: file_type.string_padding).to_hdf5_type_id

      fixed = fixed_length_buffer(data, element_size, file_type.string_padding)
      ret = LibHDF5.H5Dwrite(@id, write_type, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, fixed.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(write_type)
      file_type.close
      raise Error.new("Failed to write fixed-length string dataset") if ret < 0
    end

    def read_strings : Array(String)
      file_type = datatype
      raise Error.new("Dataset is not string type") unless file_type.string?

      if file_type.variable_length_string?
        type_id = StringType.variable(encoding: file_type.string_encoding,
          padding: file_type.string_padding).to_hdf5_type_id
        space = dataspace
        n = space.npoints
        if n < 0
          space.close
          LibHDF5.H5Tclose(type_id)
          file_type.close
          raise Error.new("Invalid dataspace")
        end
        ptrs = Array(Pointer(UInt8)).new(n.to_i, Pointer(UInt8).null)
        ret = LibHDF5.H5Dread(@id, type_id, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
          LibHDF5::H5P_DEFAULT, ptrs.to_unsafe.as(Void*))
        if ret < 0
          space.close
          LibHDF5.H5Tclose(type_id)
          file_type.close
          raise Error.new("Failed to read string dataset")
        end

        begin
          return ptrs.map { |ptr| ptr.null? ? "" : String.new(ptr) }
        ensure
          reclaim = LibHDF5.H5Dvlen_reclaim(type_id, space.id, LibHDF5::H5P_DEFAULT, ptrs.to_unsafe.as(Void*))
          space.close
          LibHDF5.H5Tclose(type_id)
          file_type.close
          raise Error.new("Failed to reclaim variable-length string memory") if reclaim < 0
        end
      end

      unless file_type.fixed_length_string?
        file_type.close
        raise Error.new("Unsupported string dataset storage")
      end

      space = dataspace
      n = space.npoints
      if n < 0
        space.close
        file_type.close
        raise Error.new("Invalid dataspace")
      end

      element_size = file_type.size
      read_type = StringType.fixed(element_size,
        encoding: file_type.string_encoding,
        padding: file_type.string_padding).to_hdf5_type_id
      buf = Bytes.new(n.to_i * element_size, 0_u8)
      ret = LibHDF5.H5Dread(@id, read_type, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL,
        LibHDF5::H5P_DEFAULT, buf.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(read_type)
      space.close
      file_type.close
      raise Error.new("Failed to read fixed-length string dataset") if ret < 0
      decode_fixed_length_strings(buf, n.to_i, element_size)
    end

    def resize(new_shape : Indexable) : Nil
      ensure_open
      udims = new_shape.map(&.to_u64).to_a
      ret = LibHDF5.H5Dset_extent(@id, udims.to_unsafe)
      raise Error.new("Failed to resize dataset") if ret < 0
    end

    def storage_size : UInt64
      ensure_open
      LibHDF5.H5Dget_storage_size(@id)
    end

    def close
      LibHDF5.H5Dclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise ClosedObjectError.new("Dataset is closed") if @id == LibHDF5::H5_INVALID_HID
    end

    private def fixed_length_buffer(data : Array(String), element_size : Int32,
                                    padding : StringPadding) : Bytes
      fill = padding == StringPadding::SpacePad ? ' '.ord.to_u8 : 0_u8
      buf = Bytes.new(data.size * element_size, fill)
      data.each_with_index do |value, index|
        max_len = padding == StringPadding::NullTerm ? element_size - 1 : element_size
        next if max_len <= 0
        bytes = value.to_slice
        copy_len = bytes.size < max_len ? bytes.size : max_len
        start = index * element_size
        copy_len.times do |offset|
          buf[start + offset] = bytes[offset]
        end
      end
      buf
    end

    private def decode_fixed_length_strings(buf : Bytes, count : Int32, element_size : Int32) : Array(String)
      Array(String).new(count) do |index|
        start = index * element_size
        slice = buf[start, element_size]
        String.new(trim_fixed_string_slice(slice))
      end
    end

    private def trim_fixed_string_slice(slice : Bytes) : Bytes
      terminator = slice.index(0_u8)
      if terminator
        return slice[0, terminator]
      end

      last = slice.size - 1
      while last >= 0 && (slice[last] == 0_u8 || slice[last] == ' '.ord.to_u8)
        last -= 1
      end
      return Bytes.new(0) if last < 0
      slice[0, last + 1]
    end
  end
end
