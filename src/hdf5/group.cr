module HDF5
  module GroupMethods
    def create_group(name : String) : Group
      lcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_link_create_id_g)
      if lcpl_id != LibHDF5::H5_INVALID_HID
        LibHDF5.H5Pset_create_intermediate_group(lcpl_id, 1)
      end
      gid = LibHDF5.H5Gcreate2(hid, name, lcpl_id, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      LibHDF5.H5Pclose(lcpl_id) if lcpl_id != LibHDF5::H5_INVALID_HID
      raise Error.new("Failed to create group '#{name}'") if gid == LibHDF5::H5_INVALID_HID
      Group.new(gid)
    end

    def open_group(name : String) : Group
      gid = LibHDF5.H5Gopen2(hid, name, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to open group '#{name}'") if gid == LibHDF5::H5_INVALID_HID
      Group.new(gid)
    end

    def group(name : String) : Group
      if link_exists?(name)
        open_group(name)
      else
        create_group(name)
      end
    end

    def create_dataset(name : String, type : T.class, dims : Array(UInt64),
                       max_dims : Array(UInt64)? = nil,
                       chunk_dims : Array(UInt64)? = nil,
                       compress : Int32 = 0) : Dataset forall T
      dtype = NativeType.for(T)
      space = Dataspace.simple(dims, max_dims)
      dcpl_id = LibHDF5::H5P_DEFAULT
      if chunk_dims || compress > 0
        dcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_dataset_create_id_g)
        chunks = chunk_dims || dims
        LibHDF5.H5Pset_chunk(dcpl_id, dims.size, chunks.to_unsafe)
        LibHDF5.H5Pset_deflate(dcpl_id, compress.to_u32) if compress > 0
      end
      did = LibHDF5.H5Dcreate2(hid, name, dtype, space.id,
        LibHDF5::H5P_DEFAULT, dcpl_id, LibHDF5::H5P_DEFAULT)
      LibHDF5.H5Pclose(dcpl_id) if dcpl_id != LibHDF5::H5P_DEFAULT
      space.close
      raise Error.new("Failed to create dataset '#{name}'") if did == LibHDF5::H5_INVALID_HID
      Dataset.new(did)
    end

    def create_dataset(name : String, type : T.class, *dims : Int,
                       compress : Int32 = 0) : Dataset forall T
      create_dataset(name, T, dims.map(&.to_u64).to_a, compress: compress)
    end

    def open_dataset(name : String) : Dataset
      did = LibHDF5.H5Dopen2(hid, name, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to open dataset '#{name}'") if did == LibHDF5::H5_INVALID_HID
      Dataset.new(did)
    end

    def write_dataset(name : String, data : Array(T)) forall T
      dims = [data.size.to_u64]
      ds = create_dataset(name, T, dims)
      ds.write(data)
      ds.close
    end

    def write_dataset(name : String, data : Array(T), *shape : Int) forall T
      dims = shape.map(&.to_u64).to_a
      ds = create_dataset(name, T, dims)
      ds.write(data)
      ds.close
    end

    def read_dataset(name : String, type : T.class) : Array(T) forall T
      ds = open_dataset(name)
      result = ds.read(T)
      ds.close
      result
    end

    def write_string_dataset(name : String, data : Array(String))
      dims = [data.size.to_u64]
      type_id = NativeType.variable_length_string
      space = Dataspace.simple(dims)
      did = LibHDF5.H5Dcreate2(hid, name, type_id, space.id,
        LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      space.close
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to create string dataset '#{name}'") if did == LibHDF5::H5_INVALID_HID
      ds = Dataset.new(did)
      ds.write_strings(data)
      ds.close
    end

    def read_string_dataset(name : String) : Array(String)
      ds = open_dataset(name)
      result = ds.read_strings
      ds.close
      result
    end

    def link_exists?(name : String) : Bool
      LibHDF5.H5Lexists(hid, name, LibHDF5::H5P_DEFAULT) > 0
    end

    def delete_link(name : String)
      ret = LibHDF5.H5Ldelete(hid, name, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to delete link '#{name}'") if ret < 0
    end

    def keys : Array(String)
      info = LibHDF5::GroupInfo.new
      ret = LibHDF5.H5Gget_info(hid, pointerof(info))
      raise Error.new("Failed to get group info") if ret < 0
      result = Array(String).new(info.nlinks.to_i)
      info.nlinks.times do |idx|
        size = LibHDF5.H5Lget_name_by_idx(hid, ".", LibHDF5::IndexType::Name,
          LibHDF5::IterOrder::Inc, idx.to_u64, nil, 0,
          LibHDF5::H5P_DEFAULT)
        next if size <= 0
        buf = Bytes.new(size + 1)
        LibHDF5.H5Lget_name_by_idx(hid, ".", LibHDF5::IndexType::Name,
          LibHDF5::IterOrder::Inc, idx.to_u64,
          buf.to_unsafe.as(UInt8*), LibC::SizeT.new(size + 1),
          LibHDF5::H5P_DEFAULT)
        result << String.new(buf[0, size])
      end
      result
    end

    def nlinks : UInt64
      info = LibHDF5::GroupInfo.new
      ret = LibHDF5.H5Gget_info(hid, pointerof(info))
      raise Error.new("Failed to get group info") if ret < 0
      info.nlinks
    end

    def set_attribute(name : String, value : T) forall T
      {% if T < Number %}
        dtype = NativeType.for(T)
        space = Dataspace.scalar
        attr_id = LibHDF5.H5Acreate2(hid, name, dtype, space.id,
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
      attr_id = LibHDF5.H5Aopen(hid, name, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to open attribute '#{name}'") if attr_id == LibHDF5::H5_INVALID_HID
      attr = Attribute.new(attr_id)
      result = attr.read(T)
      attr.close
      result
    end

    def has_attribute?(name : String) : Bool
      LibHDF5.H5Aexists(hid, name) > 0
    end

    private def set_string_attribute(name : String, value : String)
      type_id = NativeType.variable_length_string
      space = Dataspace.scalar
      attr_id = LibHDF5.H5Acreate2(hid, name, type_id, space.id,
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

  class Group
    include GroupMethods

    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def hid : LibHDF5::Hid
      @id
    end

    def close
      LibHDF5.H5Gclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end
  end
end
