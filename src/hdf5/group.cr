module HDF5
  module Container
    # ── Group operations ──────────────────────────────────────────────────────

    def create_group(path : String) : Group
      lcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_link_create_id_g)
      if lcpl_id != LibHDF5::H5_INVALID_HID
        LibHDF5.H5Pset_create_intermediate_group(lcpl_id, 1)
      end
      gid = LibHDF5.H5Gcreate2(hid, path, lcpl_id, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      LibHDF5.H5Pclose(lcpl_id) if lcpl_id != LibHDF5::H5_INVALID_HID
      raise AlreadyExistsError.new("Group already exists: '#{path}'") if gid == LibHDF5::H5_INVALID_HID
      Group.new(gid)
    end

    def create_group(path : String, &block : Group ->) : Nil
      g = create_group(path)
      begin
        block.call(g)
      ensure
        g.close
      end
    end

    def open_group(path : String) : Group
      gid = LibHDF5.H5Gopen2(hid, path, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Group not found: '#{path}'") if gid == LibHDF5::H5_INVALID_HID
      Group.new(gid)
    end

    def open_group(path : String, &block : Group ->) : Nil
      g = open_group(path)
      begin
        block.call(g)
      ensure
        g.close
      end
    end

    def require_group(path : String) : Group
      if exists?(path)
        open_group(path)
      else
        create_group(path)
      end
    end

    def require_group(path : String, &block : Group ->) : Nil
      g = require_group(path)
      begin
        block.call(g)
      ensure
        g.close
      end
    end

    # ── Dataset creation ──────────────────────────────────────────────────────

    # Create from data (infer type and shape from array)
    def create_dataset(path : String, data : Array(T)) : TypedDataset(T) forall T
      {% if T == String %}
        ds = build_string_dataset(path, data.size.to_u64, string_type: StringType.variable)
        ds.write_strings(data)
        TypedDataset(String).new(ds)
      {% else %}
        dims = [data.size.to_u64]
        ds = build_numeric_dataset(path, T, dims)
        ds.write(data)
        TypedDataset(T).new(ds)
      {% end %}
    end

    def create_dataset(path : String, data : Array(String),
                       *,
                       string_type : StringType = StringType.variable,
                       encoding : (Symbol | StringEncoding)? = nil) : TypedDataset(String)
      resolved_type = encoding ? string_type.with_encoding(encoding) : string_type
      ds = build_string_dataset(path, data.size.to_u64, string_type: resolved_type)
      ds.write_strings(data)
      TypedDataset(String).new(ds)
    end

    def create_dataset(path : String, data : Array(T), &block : TypedDataset(T) ->) : Nil forall T
      tds = create_dataset(path, data)
      begin
        block.call(tds)
      ensure
        tds.close
      end
    end

    def create_dataset(
      path : String,
      data : Array(String),
      *,
      string_type : StringType = StringType.variable,
      encoding : (Symbol | StringEncoding)? = nil,
      &block
    ) : Nil
      tds = create_dataset(path, data, string_type: string_type, encoding: encoding)
      begin
        block.call(tds)
      ensure
        tds.close
      end
    end

    # Create from type + explicit shape (named params)
    def create_dataset(
      path : String,
      type : T.class,
      *,
      shape : Indexable,
      max_shape : Indexable? = nil,
      chunk : Indexable? = nil,
      compression : Compression | Symbol? = nil,
      compression_level : Int32 = 6,
      shuffle : Bool = false,
      fletcher32 : Bool = false,
      options : DatasetCreateOptions? = nil,
    ) : TypedDataset(T) forall T
      dims = shape.map(&.to_u64).to_a
      resolved_opts = options || build_options(chunk, compression, compression_level,
        shuffle, fletcher32, max_shape)
      {% if T == String %}
        ds = build_string_dataset(path, dims, resolved_opts, string_type: StringType.variable)
        TypedDataset(String).new(ds)
      {% else %}
        ds = build_numeric_dataset(path, T, dims, resolved_opts)
        TypedDataset(T).new(ds)
      {% end %}
    end

    def create_dataset(
      path : String,
      type : String.class,
      *,
      shape : Indexable,
      max_shape : Indexable? = nil,
      chunk : Indexable? = nil,
      compression : Compression | Symbol? = nil,
      compression_level : Int32 = 6,
      shuffle : Bool = false,
      fletcher32 : Bool = false,
      options : DatasetCreateOptions? = nil,
      string_type : StringType = StringType.variable,
      encoding : (Symbol | StringEncoding)? = nil,
    ) : TypedDataset(String)
      dims = shape.map(&.to_u64).to_a
      resolved_opts = options || build_options(chunk, compression, compression_level,
        shuffle, fletcher32, max_shape)
      resolved_type = encoding ? string_type.with_encoding(encoding) : string_type
      ds = build_string_dataset(path, dims, resolved_opts, string_type: resolved_type)
      TypedDataset(String).new(ds)
    end

    def create_dataset(
      path : String,
      type : T.class,
      *,
      shape : Indexable,
      max_shape : Indexable? = nil,
      chunk : Indexable? = nil,
      compression : Compression | Symbol? = nil,
      compression_level : Int32 = 6,
      shuffle : Bool = false,
      fletcher32 : Bool = false,
      options : DatasetCreateOptions? = nil,
      &block : TypedDataset(T) ->
    ) : Nil forall T
      tds = create_dataset(path, T, shape: shape, max_shape: max_shape, chunk: chunk,
        compression: compression, compression_level: compression_level,
        shuffle: shuffle, fletcher32: fletcher32, options: options)
      begin
        block.call(tds)
      ensure
        tds.close
      end
    end

    def create_dataset(
      path : String,
      type : String.class,
      *,
      shape : Indexable,
      max_shape : Indexable? = nil,
      chunk : Indexable? = nil,
      compression : Compression | Symbol? = nil,
      compression_level : Int32 = 6,
      shuffle : Bool = false,
      fletcher32 : Bool = false,
      options : DatasetCreateOptions? = nil,
      string_type : StringType = StringType.variable,
      encoding : (Symbol | StringEncoding)? = nil,
      &block : TypedDataset(String) ->
    ) : Nil
      tds = create_dataset(path, String, shape: shape, max_shape: max_shape, chunk: chunk,
        compression: compression, compression_level: compression_level,
        shuffle: shuffle, fletcher32: fletcher32, options: options,
        string_type: string_type, encoding: encoding)
      begin
        block.call(tds)
      ensure
        tds.close
      end
    end

    # ── Dataset open / access ─────────────────────────────────────────────────

    def open_dataset(path : String) : Dataset
      did = LibHDF5.H5Dopen2(hid, path, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Dataset not found: '#{path}'") if did == LibHDF5::H5_INVALID_HID
      Dataset.new(did)
    end

    def dataset(path : String, type : T.class) : TypedDataset(T) forall T
      TypedDataset(T).new(open_dataset(path))
    end

    def dataset(path : String, type : T.class, &block : TypedDataset(T) ->) : Nil forall T
      tds = dataset(path, T)
      begin
        block.call(tds)
      ensure
        tds.close
      end
    end

    def open_object(path : String) : Group | Dataset
      self[path]
    end

    def open_object(path : String, &block : (Group | Dataset) ->) : Nil
      obj = open_object(path)
      begin
        block.call(obj)
      ensure
        obj.close
      end
    end

    # ── [] / []= convenience ──────────────────────────────────────────────────

    def [](path : String) : Group | Dataset
      oid = LibHDF5.H5Oopen(hid, path, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Object not found: '#{path}'") if oid == LibHDF5::H5_INVALID_HID
      obj_type = LibHDF5.H5Iget_type(oid)
      LibHDF5.H5Oclose(oid)
      case obj_type
      when LibHDF5::H5I_GROUP
        open_group(path)
      when LibHDF5::H5I_DATASET
        open_dataset(path)
      else
        raise Error.new("Unknown object type at '#{path}'")
      end
    end

    def []=(path : String, data : Array(T)) forall T
      delete(path) if exists?(path)
      create_dataset(path, data)
    end

    # ── Container inspection ──────────────────────────────────────────────────

    def exists?(path : String) : Bool
      LibHDF5.H5Lexists(hid, path, LibHDF5::H5P_DEFAULT) > 0
    end

    def object_type(path : String) : Symbol
      oid = LibHDF5.H5Oopen(hid, path, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Object not found: '#{path}'") if oid == LibHDF5::H5_INVALID_HID

      info = uninitialized LibHDF5::ObjInfo
      ret = LibHDF5.H5Oget_info3(oid, pointerof(info), LibHDF5::H5O_INFO_BASIC)
      LibHDF5.H5Oclose(oid)
      raise Error.new("Failed to get object info for '#{path}'") if ret < 0

      case info.type
      when LibHDF5::ObjType::Group
        :group
      when LibHDF5::ObjType::Dataset
        :dataset
      when LibHDF5::ObjType::NamedDatatype
        :named_datatype
      else
        :unknown
      end
    end

    def delete(path : String) : Nil
      ret = LibHDF5.H5Ldelete(hid, path, LibHDF5::H5P_DEFAULT)
      raise ObjectNotFoundError.new("Link not found: '#{path}'") if ret < 0
    end

    def link(source_path : String, destination_path : String) : Nil
      with_link_create_plist do |lcpl_id|
        ret = LibHDF5.H5Lcreate_hard(hid, source_path, hid, destination_path,
          lcpl_id, LibHDF5::H5P_DEFAULT)
        raise Error.new("Failed to create hard link from '#{source_path}' to '#{destination_path}'") if ret < 0
      end
    end

    def soft_link(target_path : String, link_path : String) : Nil
      with_link_create_plist do |lcpl_id|
        ret = LibHDF5.H5Lcreate_soft(target_path, hid, link_path,
          lcpl_id, LibHDF5::H5P_DEFAULT)
        raise Error.new("Failed to create soft link '#{link_path}' -> '#{target_path}'") if ret < 0
      end
    end

    def external_link(filename : String, target_path : String, link_path : String) : Nil
      with_link_create_plist do |lcpl_id|
        ret = LibHDF5.H5Lcreate_external(filename, target_path, hid, link_path,
          lcpl_id, LibHDF5::H5P_DEFAULT)
        raise Error.new("Failed to create external link '#{link_path}' -> '#{filename}:#{target_path}'") if ret < 0
      end
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

    def each(& : String ->) : Nil
      keys.each { |k| yield k }
    end

    def nlinks : UInt64
      info = LibHDF5::GroupInfo.new
      ret = LibHDF5.H5Gget_info(hid, pointerof(info))
      raise Error.new("Failed to get group info") if ret < 0
      info.nlinks
    end

    def attrs : Attributes
      Attributes.new(hid)
    end

    # ── Private helpers ───────────────────────────────────────────────────────

    private def build_numeric_dataset(
      path : String,
      type : T.class,
      dims : Array(UInt64),
      opts : DatasetCreateOptions? = nil,
    ) : Dataset forall T
      dtype = NativeType.for(T)
      opts_max = opts.try(&.max_shape)
      space = Dataspace.simple(dims, opts_max)
      dcpl_id = LibHDF5::H5P_DEFAULT
      if opts && (opts.chunk || (opts.compression && !opts.compression.try(&.none?)) || opts.shuffle? || opts.fletcher32?)
        dcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_dataset_create_id_g)
        opts.apply_to(dcpl_id, dims)
      end
      did = LibHDF5.H5Dcreate2(hid, path, dtype, space.id,
        LibHDF5::H5P_DEFAULT, dcpl_id, LibHDF5::H5P_DEFAULT)
      LibHDF5.H5Pclose(dcpl_id) if dcpl_id != LibHDF5::H5P_DEFAULT
      space.close
      raise Error.new("Failed to create dataset '#{path}'") if did == LibHDF5::H5_INVALID_HID
      Dataset.new(did)
    end

    private def build_string_dataset(path : String, n : UInt64,
                                     opts : DatasetCreateOptions? = nil,
                                     string_type : StringType = StringType.variable) : Dataset
      build_string_dataset(path, [n], opts, string_type: string_type)
    end

    private def build_string_dataset(path : String, dims : Array(UInt64),
                                     opts : DatasetCreateOptions? = nil,
                                     string_type : StringType = StringType.variable) : Dataset
      type_id = string_type.to_hdf5_type_id
      opts_max = opts.try(&.max_shape)
      space = Dataspace.simple(dims, opts_max)
      dcpl_id = LibHDF5::H5P_DEFAULT
      if opts && (opts.chunk || (opts.compression && !opts.compression.try(&.none?)))
        dcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_dataset_create_id_g)
        opts.apply_to(dcpl_id, dims)
      end
      did = LibHDF5.H5Dcreate2(hid, path, type_id, space.id,
        LibHDF5::H5P_DEFAULT, dcpl_id, LibHDF5::H5P_DEFAULT)
      LibHDF5.H5Pclose(dcpl_id) if dcpl_id != LibHDF5::H5P_DEFAULT
      space.close
      LibHDF5.H5Tclose(type_id)
      raise Error.new("Failed to create string dataset '#{path}'") if did == LibHDF5::H5_INVALID_HID
      Dataset.new(did)
    end

    private def build_options(
      chunk : Indexable?,
      compression : Compression | Symbol?,
      compression_level : Int32,
      shuffle : Bool,
      fletcher32 : Bool,
      max_shape : Indexable?,
    ) : DatasetCreateOptions?
      resolved_comp = case compression
                      in Compression then compression
                      in Symbol
                        compression == :gzip ? Compression.gzip(level: compression_level) : nil
                      in Nil
                        nil
                      end
      needs_dcpl = chunk || resolved_comp || shuffle || fletcher32 || max_shape
      return unless needs_dcpl
      DatasetCreateOptions.new(
        chunk: chunk.try(&.map(&.to_u64).to_a),
        compression: resolved_comp,
        shuffle: shuffle,
        fletcher32: fletcher32,
        max_shape: max_shape.try(&.map(&.to_u64).to_a)
      )
    end

    private def with_link_create_plist(& : LibHDF5::Hid -> T) : T forall T
      lcpl_id = LibHDF5.H5Pcreate(LibHDF5.h5p_cls_link_create_id_g)
      raise Error.new("Failed to create link creation property list") if lcpl_id == LibHDF5::H5_INVALID_HID
      LibHDF5.H5Pset_create_intermediate_group(lcpl_id, 1)
      begin
        yield lcpl_id
      ensure
        LibHDF5.H5Pclose(lcpl_id)
      end
    end
  end

  class Group
    include Container

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
