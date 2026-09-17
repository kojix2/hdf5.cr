module HDF5
  class Attributes
    include Enumerable({String, Attribute})

    def initialize(@loc_id : LibHDF5::Hid, @context : FileContext? = nil)
    end

    def [](name : String) : Attribute
      Native.synchronize do
        ensure_open
        raise ObjectNotFoundError.new("Attribute not found: '#{name}'") unless has_key?(name)
        Attribute.new(InternalChecks.ensure_hid(Native.h5aopen(@loc_id, name, LibHDF5::H5P_DEFAULT), "Failed to open attribute"), @context)
      end
    end

    def []=(name : String, value) : Nil
      write(name, value)
    end

    def get(name : String, type : T.class, *, casting : Casting = Casting::Unsafe) : T forall T
      Cleanup.with(self[name], &.read(T, casting: casting))
    end

    def get?(name : String, type : T.class, *, casting : Casting = Casting::Unsafe) : T? forall T
      return unless has_key?(name)
      get(name, T, casting: casting)
    end

    def get_array(name : String, type : T.class, *, casting : Casting = Casting::Unsafe) : Array(T) forall T
      Cleanup.with(self[name]) { |attribute| attribute.read_array(T, casting: casting) }
    end

    def get_null(name : String, type : T.class) : Empty(T) forall T
      Cleanup.with(self[name], &.read_null(T))
    end

    def has_key?(name : String) : Bool
      Native.synchronize do
        ensure_open
        InternalChecks.ensure_htri(Native.h5aexists(@loc_id, name), "Failed to check attribute existence")
      end
    end

    def delete(name : String) : Nil
      Native.synchronize do
        ensure_open
        raise ObjectNotFoundError.new("Attribute not found: '#{name}'") unless has_key?(name)
        InternalChecks.ensure_herr(Native.h5adelete(@loc_id, name), "Failed to delete attribute")
      end
    end

    def keys : Array(String)
      Native.synchronize do
        ensure_open
        info = LibHDF5::ObjInfo.new
        InternalChecks.ensure_herr(Native.h5oget_info3(@loc_id, pointerof(info), LibHDF5::H5O_INFO_NUM_ATTRS), "Failed to list attributes")
        Array(String).new(info.num_attrs.to_i) do |i|
          id = InternalChecks.ensure_hid(Native.h5aopen_by_idx(@loc_id, ".", LibHDF5::IndexType::Name,
            LibHDF5::IterOrder::Inc, i.to_u64, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT), "Failed to open attribute by index")
          Cleanup.with(Attribute.new(id, @context), &.name)
        end
      end
    end

    def each(& : {String, Attribute} ->) : Nil
      keys.each do |name|
        Cleanup.with(self[name]) { |attribute| yield({name, attribute}) }
      end
    end

    def create(name : String, data : Slice(T), **options) : Nil forall T
      create(name, data.to_a, **options)
    end

    def modify(name : String, data : Slice(T), **options) : Nil forall T
      modify(name, data.to_a, **options)
    end

    def create(name : String, data : Array(T), *, shape : Indexable? = nil,
               **options) : Nil forall T
      create_values(name, T, data, shape ? Shapes.normalize(shape) : [data.size.to_u64], **options)
    end

    {% for type in {Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Float32, Float64, Bool, String, Complex, Complex32, Reference} %}
    def create(name : String, value : {{ type }}, **options) : Nil
      create_values(name, {{ type }}, [value], [] of UInt64, **options, scalar_input: true)
    end

    {% end %}

    def create(name : String, empty : Empty(T), *, string_type : StringType = StringType.variable,
               encoding : Symbol | StringEncoding? = nil) : Nil forall T
      Native.synchronize do
        ensure_open
        raise AlreadyExistsError.new("Attribute already exists: '#{name}'") if has_key?(name)
        resolved = encoding ? string_type.with_encoding(encoding) : string_type
        Cleanup.with(TypeFactory.build(T, storage: true, string_type: resolved)) do |dtype|
          Cleanup.with(Dataspace.null) do |space|
            id = InternalChecks.ensure_hid(Native.h5acreate2(@loc_id, name, dtype.id, space.id,
              LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT), "Failed to create Null attribute")
            Cleanup.with(Attribute.new(id, @context)) { }
          end
        end
      end
    end

    def create(name : String, type : T.class, data : Array(U), *,
               shape : Indexable? = nil, **options) : Nil forall T, U
      create_values(name, T, data, shape ? Shapes.normalize(shape) : [data.size.to_u64], **options)
    end

    def create(name : String, type : T.class, value : U, **options) : Nil forall T, U
      create_values(name, T, [value], [] of UInt64, **options, scalar_input: true)
    end

    def write(name : String, value, **options) : Nil
      replace(name) { |temporary| create(temporary, value, **options) }
    end

    def write(name : String, type : T.class, value, **options) : Nil forall T
      replace(name) { |temporary| create(temporary, T, value, **options) }
    end

    def modify(name : String, data : Array(T), *, shape : Indexable? = nil,
               casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        Cleanup.with(self[name]) do |attribute|
          raise ShapeMismatchError.new("Expected array attribute") unless attribute.array?
          if shape && Shapes.normalize(shape) != attribute.shape
            raise ShapeMismatchError.new("Attribute shape mismatch")
          end
          attribute.write_array(data, casting: casting)
        end
      end
    end

    def modify(name : String, value : Empty(T), *, casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize do
        Cleanup.with(self[name]) do |_|
          raise ShapeMismatchError.new("Empty values are only supported when creating a Null attribute")
        end
      end
    end

    def modify(name : String, value : T, *, casting : Casting = Casting::Unsafe) : Nil forall T
      Native.synchronize { Cleanup.with(self[name], &.write(value, casting: casting)) }
    end

    private def create_values(name : String, type : T.class, data : Indexable(U), dims : Array(UInt64), *,
                              string_type : StringType = StringType.variable,
                              encoding : Symbol | StringEncoding? = nil,
                              casting : Casting = Casting::Unsafe, scalar_input : Bool = false) : Nil forall T, U
      Native.synchronize do
        ensure_open
        raise AlreadyExistsError.new("Attribute already exists: '#{name}'") if has_key?(name)
        Shapes.validate_count(dims, data.size)
        resolved = encoding ? string_type.with_encoding(encoding) : string_type
        Cleanup.with(TypeFactory.build(T, storage: true, string_type: resolved)) do |dtype|
          if scalar_input
            CastingChecks.scalar(data.first, dtype, casting)
          else
            Cleanup.with(TypeFactory.build(U)) { |source| CastingChecks.check(source, dtype, casting) }
          end
          {% if U == String %}
            Codec.validate_strings(data, dtype, casting)
          {% end %}
          Cleanup.with(Dataspace.simple(dims)) do |space|
            id = InternalChecks.ensure_hid(Native.h5acreate2(@loc_id, name, dtype.id, space.id,
              LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT), "Failed to create attribute '#{name}'")
            begin
              Cleanup.with(Attribute.new(id, @context)) do |attribute|
                Codec.write(:attribute, attribute.hid, data, dtype, space.id, LibHDF5::H5S_ALL)
              end
            rescue exception
              Native.h5adelete(@loc_id, name)
              raise exception
            end
          end
        end
      end
    end

    private def replace(name : String, &)
      Native.synchronize do
        ensure_open
        temporary = temporary_name
        backup = temporary_name
        backed_up = false
        begin
          yield temporary
          if has_key?(name)
            InternalChecks.ensure_herr(Native.h5arename(@loc_id, name, backup), "Failed to back up attribute")
            backed_up = true
          end
          InternalChecks.ensure_herr(Native.h5arename(@loc_id, temporary, name), "Failed to replace attribute")
          delete(backup) if backed_up
        rescue exception
          if backed_up && !has_key?(name)
            rollback = Native.h5arename(@loc_id, backup, name)
            raise Error.new("Attribute replacement rollback failed", cause: exception) if rollback < 0
          end
          raise exception
        ensure
          Native.h5adelete(@loc_id, temporary) if has_key?(temporary)
        end
      end
    end

    private def temporary_name : String
      loop do
        name = "__hdf5_cr_#{Random::Secure.hex(16)}"
        return name unless has_key?(name)
      end
    end

    private def ensure_open : Nil
      @context.try(&.ensure_open(@loc_id))
      raise ClosedObjectError.new("Attribute owner is closed") unless InternalChecks.ensure_htri(Native.h5iis_valid(@loc_id), "Failed to check owner")
    end
  end
end
