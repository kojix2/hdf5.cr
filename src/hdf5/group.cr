module HDF5
  module Container
    # ── Group operations ──────────────────────────────────────────────────────

    def create_group(path : String) : Group
      Native.synchronize do
        location = hid
        raise AlreadyExistsError.new("Group already exists: '#{path}'") if exists?(path)
        with_link_create_plist do |lcpl|
          id = InternalChecks.ensure_hid(Native.h5gcreate2(location, path, lcpl,
            LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT), "Failed to create group '#{path}'")
          Group.new(id, context)
        end
      end
    end

    def create_group(path : String, &block : Group ->) : Nil
      Cleanup.with(create_group(path)) { |object| block.call(object) }
    end

    def open_group(path : String) : Group
      Native.synchronize do
        raise TypeMismatchError.new("Object is not a group: '#{path}'") if exists?(path) && object_type(path) != :group
        gid = Native.h5gopen2(hid, path, LibHDF5::H5P_DEFAULT)
        raise ObjectNotFoundError.new("Group not found: '#{path}'") if gid == LibHDF5::H5_INVALID_HID
        Group.new(gid, context)
      end
    end

    def open_group(path : String, &block : Group ->) : Nil
      Cleanup.with(open_group(path)) { |object| block.call(object) }
    end

    def require_group(path : String) : Group
      Native.synchronize do
        if exists?(path)
          raise TypeMismatchError.new("Existing object is not a group: #{path}") unless object_type(path) == :group
          open_group(path)
        else
          create_group(path)
        end
      end
    end

    def require_group(path : String, &block : Group ->) : Nil
      Cleanup.with(require_group(path)) { |object| block.call(object) }
    end

    def create_dataset(path : String, data : Slice(T), **options) : TypedDataset(T) forall T
      Native.synchronize do
        create_dataset(path, data.to_a, **options)
      end
    end

    def create_dataset(path : String, type : T.class, data : Slice(U), **options) : TypedDataset(T) forall T, U
      Native.synchronize do
        create_dataset(path, T, data.to_a, **options)
      end
    end

    # Dataset elements are flat; a nested Array is a variable-length element.
    def create_dataset(path : String, data : Array(T), *,
                       shape : Indexable? = nil, casting : Casting = Casting::Unsafe,
                       **options) : TypedDataset(T) forall T
      Native.synchronize do
        dims = shape ? Shapes.normalize(shape) : [data.size.to_u64]
        Shapes.validate_count(dims, data.size)
        validate_initial(T, data, casting, options)
        ds = create_dataset(path, T, **options, shape: dims, casting: casting)
        initialize_dataset(path, ds, data, casting)
      end
    end

    def create_dataset(path : String, type : T.class, data : Array(U), *,
                       shape : Indexable? = nil, casting : Casting = Casting::Unsafe,
                       **options) : TypedDataset(T) forall T, U
      Native.synchronize do
        dims = shape ? Shapes.normalize(shape) : [data.size.to_u64]
        Shapes.validate_count(dims, data.size)
        validate_initial(T, data, casting, options)
        ds = create_dataset(path, T, **options, shape: dims, casting: casting)
        initialize_dataset(path, ds, data, casting)
      end
    end

    {% for type in {Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Float32, Float64, Bool, String, Complex, Complex32, Reference} %}
    def create_dataset(path : String, value : {{ type }}, *, shape : Indexable = [] of UInt64, casting : Casting = Casting::Unsafe,
                       **options) : TypedDataset({{ type }})
      Native.synchronize do
        validate_initial_scalar({{ type }}, value, casting, options)
        ds = create_dataset(path, {{ type }}, **options, shape: shape, casting: casting)
        initialize_dataset(path, ds, value, casting)
      end
    end

    def create_dataset(path : String, type : T.class, value : {{ type }}, *,
                       shape : Indexable = [] of UInt64, casting : Casting = Casting::Unsafe,
                       **options) : TypedDataset(T) forall T
      Native.synchronize do
        validate_initial_scalar(T, value, casting, options)
        ds = create_dataset(path, T, **options, shape: shape, casting: casting)
        initialize_dataset(path, ds, value, casting)
      end
    end

    def create_dataset(path : String, value : {{ type }}, **options,
                       &block : TypedDataset({{ type }}) ->) : Nil
      Cleanup.with(create_dataset(path, value, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, type : T.class, value : {{ type }}, **options,
                       &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(create_dataset(path, T, value, **options)) { |dataset| block.call(dataset) }
    end

    {% end %}

    def create_dataset(path : String, value : Empty(T), **options) : TypedDataset(T) forall T
      Native.synchronize do
        create_dataset(path, T, **options, null: true)
      end
    end

    def create_dataset(path : String, type : T.class, *,
                       shape : Indexable = [] of UInt64, null : Bool = false,
                       max_shape : Indexable? = nil, chunk : Indexable | Symbol? = nil,
                       compression : Compression | Symbol? = nil,
                       compression_level : Int32 = 6, shuffle : Bool = false,
                       fletcher32 : Bool = false, options : DatasetCreateOptions? = nil,
                       string_type : StringType = StringType.variable,
                       encoding : Symbol | StringEncoding? = nil,
                       fill_value = nil, casting : Casting = Casting::Unsafe) : TypedDataset(T) forall T
      Native.synchronize do
        location = hid
        dims = Shapes.normalize(shape)
        opts = options || build_options(chunk, compression, compression_level, shuffle, fletcher32, max_shape)
        resolved_string = encoding ? string_type.with_encoding(encoding) : string_type
        Cleanup.with(TypeFactory.build(T, storage: true, string_type: resolved_string)) do |dtype|
          opts.validate(dims, dtype)
          validate_null_options(dims, opts, fill_value) if null
          space = null ? Dataspace.null : Dataspace.simple(dims, opts.max_shape)
          Cleanup.with(space) do |file_space|
            dcpl = InternalChecks.ensure_hid(Native.h5pcreate(LibHDF5.h5p_cls_dataset_create_id_g), "Failed to create dataset options")
            begin
              opts.apply_to(dcpl, dims, dtype.size) unless null
              unless fill_value.nil?
                CastingChecks.scalar(fill_value, dtype, casting)
                Cleanup.with(Dataspace.scalar) do |memory|
                  Codec.write(:fill, dcpl, [fill_value], dtype, memory.id, LibHDF5::H5S_ALL)
                end
              end
              with_link_create_plist do |lcpl|
                id = InternalChecks.ensure_hid(Native.h5dcreate2(location, path, dtype.id, file_space.id,
                  lcpl, dcpl, LibHDF5::H5P_DEFAULT), "Failed to create dataset '#{path}'")
                TypedDataset(T).new(Dataset.new(id, context))
              end
            ensure
              Native.h5pclose(dcpl)
            end
          end
        end
      end
    end

    # All creation overloads also support automatic block cleanup.
    def create_dataset(path : String, type : T.class, **options, &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(create_dataset(path, T, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, data : Array(T), **options, &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(create_dataset(path, data, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, data : Slice(T), **options, &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(create_dataset(path, data, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, empty : Empty(T), **options, &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(create_dataset(path, empty, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, type : T.class, data : Array(U), **options, &block : TypedDataset(T) ->) : Nil forall T, U
      Cleanup.with(create_dataset(path, T, data, **options)) { |dataset| block.call(dataset) }
    end

    def create_dataset(path : String, type : T.class, data : Slice(U), **options, &block : TypedDataset(T) ->) : Nil forall T, U
      Cleanup.with(create_dataset(path, T, data, **options)) { |dataset| block.call(dataset) }
    end

    # ── Dataset open / access ─────────────────────────────────────────────────

    def open_dataset(path : String) : Dataset
      Native.synchronize do
        raise TypeMismatchError.new("Object is not a dataset: '#{path}'") if exists?(path) && object_type(path) != :dataset
        did = Native.h5dopen2(hid, path, LibHDF5::H5P_DEFAULT)
        raise ObjectNotFoundError.new("Dataset not found: '#{path}'") if did == LibHDF5::H5_INVALID_HID
        Dataset.new(did, context)
      end
    end

    def dataset(path : String, type : T.class) : TypedDataset(T) forall T
      Native.synchronize do
        TypedDataset(T).new(open_dataset(path))
      end
    end

    def dataset(path : String, type : T.class, &block : TypedDataset(T) ->) : Nil forall T
      Cleanup.with(dataset(path, T)) { |object| block.call(object) }
    end

    def open_object(path : String) : Group | Dataset
      Native.synchronize do
        self[path]
      end
    end

    def open_object(path : String, &block : (Group | Dataset) ->) : Nil
      Cleanup.with(open_object(path)) { |object| block.call(object) }
    end

    def reference(path : String) : Reference
      Native.synchronize do
        Reference.object(self, path)
      end
    end

    # ── [] / []= convenience ──────────────────────────────────────────────────

    def [](path : String) : Group | Dataset
      Native.synchronize do
        oid = Native.h5oopen(hid, path, LibHDF5::H5P_DEFAULT)
        raise ObjectNotFoundError.new("Object not found: '#{path}'") if oid == LibHDF5::H5_INVALID_HID
        obj_type = Native.h5iget_type(oid)
        Native.h5oclose(oid)
        case obj_type
        when LibHDF5::H5I_GROUP
          open_group(path)
        when LibHDF5::H5I_DATASET
          open_dataset(path)
        else
          raise Error.new("Unknown object type at '#{path}'")
        end
      end
    end

    def []=(path : String, data : Array(T)) forall T
      Native.synchronize do
        delete(path) if exists?(path)
        create_dataset(path, data).close
      end
    end

    # ── Container inspection ──────────────────────────────────────────────────

    def exists?(path : String) : Bool
      Native.synchronize do
        location = hid
        parts = path.split('/').reject(&.empty?)
        return InternalChecks.ensure_htri(Native.h5lexists(location, path, LibHDF5::H5P_DEFAULT), "Failed to check link existence") if parts.empty?
        prefix = path.starts_with?('/') ? "/" : ""
        parts.each do |part|
          prefix += part
          return false unless InternalChecks.ensure_htri(Native.h5lexists(location, prefix, LibHDF5::H5P_DEFAULT), "Failed to check link existence")
          prefix += "/"
        end
        true
      end
    end

    def object_type(path : String) : Symbol
      Native.synchronize do
        oid = Native.h5oopen(hid, path, LibHDF5::H5P_DEFAULT)
        raise ObjectNotFoundError.new("Object not found: '#{path}'") if oid == LibHDF5::H5_INVALID_HID

        info = uninitialized LibHDF5::ObjInfo
        ret = Native.h5oget_info3(oid, pointerof(info), LibHDF5::H5O_INFO_BASIC)
        Native.h5oclose(oid)
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
    end

    def delete(path : String) : Nil
      Native.synchronize do
        ret = Native.h5ldelete(hid, path, LibHDF5::H5P_DEFAULT)
        raise ObjectNotFoundError.new("Link not found: '#{path}'") if ret < 0
      end
    end

    def link(source_path : String, destination_path : String) : Nil
      Native.synchronize do
        with_link_create_plist do |lcpl_id|
          ret = Native.h5lcreate_hard(hid, source_path, hid, destination_path,
            lcpl_id, LibHDF5::H5P_DEFAULT)
          raise Error.new("Failed to create hard link from '#{source_path}' to '#{destination_path}'") if ret < 0
        end
      end
    end

    def soft_link(target_path : String, link_path : String) : Nil
      Native.synchronize do
        with_link_create_plist do |lcpl_id|
          ret = Native.h5lcreate_soft(target_path, hid, link_path,
            lcpl_id, LibHDF5::H5P_DEFAULT)
          raise Error.new("Failed to create soft link '#{link_path}' -> '#{target_path}'") if ret < 0
        end
      end
    end

    def external_link(filename : String, target_path : String, link_path : String) : Nil
      Native.synchronize do
        with_link_create_plist do |lcpl_id|
          ret = Native.h5lcreate_external(filename, target_path, hid, link_path,
            lcpl_id, LibHDF5::H5P_DEFAULT)
          raise Error.new("Failed to create external link '#{link_path}' -> '#{filename}:#{target_path}'") if ret < 0
        end
      end
    end

    def keys : Array(String)
      Native.synchronize do
        info = LibHDF5::GroupInfo.new
        ret = Native.h5gget_info(hid, pointerof(info))
        raise Error.new("Failed to get group info") if ret < 0
        result = Array(String).new(info.nlinks.to_i)
        info.nlinks.times do |idx|
          size = Native.h5lget_name_by_idx(hid, ".", LibHDF5::IndexType::Name,
            LibHDF5::IterOrder::Inc, idx.to_u64, nil, 0,
            LibHDF5::H5P_DEFAULT)
          raise Error.new("Failed to get link name size") if size < 0
          buf = Bytes.new(size + 1)
          ret = Native.h5lget_name_by_idx(hid, ".", LibHDF5::IndexType::Name,
            LibHDF5::IterOrder::Inc, idx.to_u64,
            buf.to_unsafe.as(UInt8*), LibC::SizeT.new(size + 1),
            LibHDF5::H5P_DEFAULT)
          raise Error.new("Failed to get link name") if ret < 0
          result << String.new(buf[0, size])
        end
        result
      end
    end

    def each(& : String ->) : Nil
      keys.each { |k| yield k }
    end

    def nlinks : UInt64
      Native.synchronize do
        info = LibHDF5::GroupInfo.new
        ret = Native.h5gget_info(hid, pointerof(info))
        raise Error.new("Failed to get group info") if ret < 0
        info.nlinks
      end
    end

    def attrs : Attributes
      Native.synchronize do
        Attributes.new(hid, context)
      end
    end

    # ── Private helpers ───────────────────────────────────────────────────────

    private def initial_datatype(type : T.class, options) : Datatype forall T
      string_type = options[:string_type]? || StringType.variable
      encoding = options[:encoding]?
      resolved = encoding ? string_type.with_encoding(encoding) : string_type
      TypeFactory.build(T, storage: true, string_type: resolved)
    end

    private def validate_initial(type : T.class, data : Indexable(U), casting, options) : Nil forall T, U
      Cleanup.with(initial_datatype(T, options)) do |dtype|
        Cleanup.with(TypeFactory.build(U)) { |source| CastingChecks.check(source, dtype, casting) }
        {% if U == String %}
          Codec.validate_strings(data, dtype, casting)
        {% end %}
      end
    end

    private def validate_initial_scalar(type : T.class, value, casting, options) : Nil forall T
      Cleanup.with(initial_datatype(T, options)) do |dtype|
        CastingChecks.scalar(value, dtype, casting)
        if value.is_a?(String)
          Codec.validate_strings([value], dtype, casting)
        end
      end
    end

    private def initialize_dataset(path, ds, data, casting)
      begin
        ds.write(data, casting: casting)
      rescue exception
        begin
          ds.close
        rescue
          # The shared context retains the handle for a later close retry.
        end
        begin
          delete(path)
        rescue error
          raise Error.new("Dataset creation cleanup failed: #{error.message}", cause: exception)
        end
        raise exception
      end
      ds
    end

    private def validate_null_options(dims, options, fill_value) : Nil
      valid = dims.empty? && options.chunk.nil? && options.max_shape.nil? &&
              !options.shuffle? && !options.fletcher32? &&
              (options.compression.nil? || options.compression.try(&.none?)) && fill_value.nil?
      raise ShapeMismatchError.new("Null datasets cannot have storage options or a shape") unless valid
    end

    private def build_options(chunk, compression, compression_level, shuffle, fletcher32, max_shape) : DatasetCreateOptions
      comp = case compression
             when Compression then compression
             when Symbol
               case compression
               when :gzip then Compression.gzip(compression_level)
               when :none then Compression.none
               else            raise ArgumentError.new("Unknown compression: #{compression}")
               end
             end
      chunks = case chunk
               when Indexable then Shapes.normalize(chunk)
               when Symbol    then chunk
               end
      DatasetCreateOptions.new(chunk: chunks, compression: comp, shuffle: shuffle,
        fletcher32: fletcher32, max_shape: max_shape ? Shapes.maxima(max_shape) : nil)
    end

    private def with_link_create_plist(& : LibHDF5::Hid -> T) : T forall T
      lcpl_id = Native.h5pcreate(LibHDF5.h5p_cls_link_create_id_g)
      raise Error.new("Failed to create link creation property list") if lcpl_id == LibHDF5::H5_INVALID_HID
      begin
        InternalChecks.ensure_herr(Native.h5pset_create_intermediate_group(lcpl_id, 1), "Failed to enable intermediate groups")
        yield lcpl_id
      ensure
        Native.h5pclose(lcpl_id)
      end
    end
  end

  class Group
    include Container

    getter id : LibHDF5::Hid
    getter context : FileContext?

    def initialize(@id : LibHDF5::Hid, @context : FileContext? = nil)
      @context.try(&.register(@id, :group))
    end

    def hid : LibHDF5::Hid
      Native.synchronize do
        raise ClosedObjectError.new("Group is closed") if @id == LibHDF5::H5_INVALID_HID
        @context.try(&.ensure_open(@id))
        @id
      end
    end

    def close
      Native.synchronize do
        if ctx = @context
          ctx.close(@id)
        elsif @id != LibHDF5::H5_INVALID_HID
          InternalChecks.ensure_herr(Native.h5gclose(@id), "Failed to close group")
        end
        @id = LibHDF5::H5_INVALID_HID
      end
    end

    def finalize
      close
    rescue
    end
  end
end
