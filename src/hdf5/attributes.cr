module HDF5
  class Attributes
    include Enumerable({String, Attribute})

    NUMERIC_TYPES = {
      Int8,
      UInt8,
      Int16,
      UInt16,
      Int32,
      UInt32,
      Int64,
      UInt64,
      Float32,
      Float64,
    }

    def initialize(@loc_id : LibHDF5::Hid)
    end

    def [](name : String) : Attribute
      attr_id = LibHDF5.H5Aopen(@loc_id, name, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Attribute not found: '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      Attribute.new(attr_id)
    end

    def []=(name : String, value : String)
      LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
      write_string_attr(name, value)
    end

    def []=(name : String, value : Array(String))
      LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
      write_string_array_attr(name, value)
    end

    def []=(name : String, value : Reference)
      LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
      write_reference_attr(name, value)
    end

    def []=(name : String, value : Array(Reference))
      LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
      write_reference_array_attr(name, value)
    end

    {% for type in NUMERIC_TYPES %}
      def []=(name : String, value : {{ type }})
        LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
        write_scalar_attr(name, value)
      end

      def []=(name : String, value : Array({{ type }}))
        LibHDF5.H5Adelete(@loc_id, name) if has_key?(name)
        write_array_attr(name, value)
      end
    {% end %}

    def get(name : String, type : T.class) : T forall T
      attr = self[name]
      begin
        attr.read(T)
      ensure
        attr.close
      end
    end

    def get?(name : String, type : T.class) : T? forall T
      return unless has_key?(name)
      get(name, T)
    end

    def has_key?(name : String) : Bool
      LibHDF5.H5Aexists(@loc_id, name) > 0
    end

    def delete(name : String) : Nil
      ret = LibHDF5.H5Adelete(@loc_id, name)
      raise ObjectNotFoundError.new("Attribute not found: '#{name}'") if ret < 0
    end

    def keys : Array(String)
      info = uninitialized LibHDF5::ObjInfo
      ret = LibHDF5.H5Oget_info3(@loc_id, pointerof(info), LibHDF5::H5O_INFO_NUM_ATTRS)
      return [] of String if ret < 0
      n = info.num_attrs.to_i
      result = Array(String).new(n)
      n.times do |idx|
        attr_id = LibHDF5.H5Aopen_by_idx(@loc_id, ".", LibHDF5::IndexType::Name,
          LibHDF5::IterOrder::Inc, idx.to_u64,
          LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
        next if attr_id == LibHDF5::H5_INVALID_HID
        size = LibHDF5.H5Aget_name(attr_id, 0, nil)
        if size > 0
          buf = Bytes.new(size + 1)
          LibHDF5.H5Aget_name(attr_id, LibC::SizeT.new(size + 1), buf.to_unsafe.as(UInt8*))
          result << String.new(buf[0, size])
        end
        LibHDF5.H5Aclose(attr_id)
      end
      result
    end

    def each(& : {String, Attribute} ->) : Nil
      keys.each do |name|
        attr_id = LibHDF5.H5Aopen(@loc_id, name, LibHDF5::H5P_DEFAULT)
        next if attr_id == LibHDF5::H5_INVALID_HID
        attr = Attribute.new(attr_id)
        yield({name, attr})
        attr.close
      end
    end

    private def write_scalar_attr(name : String, value : T) forall T
      dtype = NativeType.for(T)
      space = Dataspace.scalar
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, dtype, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      raise Error.new("Failed to create attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      ret = LibHDF5.H5Awrite(attr_id, dtype, pointerof(value).as(Void*))
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write attribute '#{name}'") if ret < 0
    end

    private def write_string_attr(name : String, value : String)
      type_id = NativeType.variable_length_string
      space = Dataspace.scalar
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, type_id, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      if attr_id == LibHDF5::H5_INVALID_HID
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to create attribute '#{name}'")
      end
      write_type = NativeType.variable_length_string
      ptr = value.to_unsafe
      ret = LibHDF5.H5Awrite(attr_id, write_type, pointerof(ptr).as(Void*))
      LibHDF5.H5Tclose(write_type)
      LibHDF5.H5Tclose(type_id)
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write string attribute '#{name}'") if ret < 0
    end

    private def write_array_attr(name : String, data : Array(T)) forall T
      dtype = NativeType.for(T)
      space = Dataspace.simple([data.size.to_u64])
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, dtype, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      raise Error.new("Failed to create array attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      ret = LibHDF5.H5Awrite(attr_id, dtype, data.to_unsafe.as(Void*))
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write array attribute '#{name}'") if ret < 0
    end

    private def write_string_array_attr(name : String, data : Array(String))
      type_id = NativeType.variable_length_string
      space = Dataspace.simple([data.size.to_u64])
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, type_id, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      if attr_id == LibHDF5::H5_INVALID_HID
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to create attribute '#{name}'")
      end
      write_type = NativeType.variable_length_string
      ptrs = data.map(&.to_unsafe)
      ret = LibHDF5.H5Awrite(attr_id, write_type, ptrs.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(write_type)
      LibHDF5.H5Tclose(type_id)
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write string array attribute '#{name}'") if ret < 0
    end

    private def write_reference_attr(name : String, value : Reference)
      dtype = NativeType.for(Reference)
      space = Dataspace.scalar
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, dtype, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      raise Error.new("Failed to create attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      ref = value.to_hdf5_reference
      ret = LibHDF5.H5Awrite(attr_id, dtype, pointerof(ref).as(Void*))
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write object reference attribute '#{name}'") if ret < 0
    end

    private def write_reference_array_attr(name : String, data : Array(Reference))
      dtype = NativeType.for(Reference)
      space = Dataspace.simple([data.size.to_u64])
      attr_id = LibHDF5.H5Acreate2(@loc_id, name, dtype, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      raise Error.new("Failed to create array attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      refs = data.map(&.to_hdf5_reference)
      ret = LibHDF5.H5Awrite(attr_id, dtype, refs.to_unsafe.as(Void*))
      LibHDF5.H5Aclose(attr_id)
      raise Error.new("Failed to write object reference array attribute '#{name}'") if ret < 0
    end
  end
end
