module HDF5
  enum StringEncoding
    Ascii
    Utf8

    def self.parse(value : Symbol | StringEncoding) : StringEncoding
      Native.synchronize do
        case value
        in StringEncoding
          value
        in Symbol
          case value
          when :ascii then Ascii
          when :utf8  then Utf8
          else
            raise Error.new("Unsupported string encoding: #{value}")
          end
        end
      end
    end

    def self.from_lib(value : LibHDF5::CharSet) : StringEncoding
      Native.synchronize do
        case value
        when LibHDF5::CharSet::Ascii then Ascii
        when LibHDF5::CharSet::Utf8  then Utf8
        else
          raise Error.new("Unknown HDF5 string character set: #{value}")
        end
      end
    end
  end

  enum StringPadding
    NullTerm
    NullPad
    SpacePad

    def self.from_lib(value : LibHDF5::StrPad) : StringPadding
      Native.synchronize do
        case value
        when LibHDF5::StrPad::NullTerm then NullTerm
        when LibHDF5::StrPad::NullPad  then NullPad
        when LibHDF5::StrPad::SpacePad then SpacePad
        else
          raise Error.new("Unknown HDF5 string padding mode: #{value}")
        end
      end
    end
  end

  struct StringType
    getter size : Int32?
    getter encoding : StringEncoding
    getter padding : StringPadding

    def initialize(@size : Int32?, @encoding : StringEncoding, @padding : StringPadding)
      raise Error.new("Fixed string size must be positive") if (size = @size) && size <= 0
    end

    def self.variable(encoding : Symbol | StringEncoding = StringEncoding::Utf8,
                      padding : StringPadding = StringPadding::NullTerm) : StringType
      Native.synchronize do
        new(nil, StringEncoding.parse(encoding), padding)
      end
    end

    def self.fixed(size : Int,
                   encoding : Symbol | StringEncoding = StringEncoding::Utf8,
                   padding : StringPadding = StringPadding::NullPad) : StringType
      Native.synchronize do
        new(size.to_i32, StringEncoding.parse(encoding), padding)
      end
    end

    def variable? : Bool
      Native.synchronize do
        @size.nil?
      end
    end

    def fixed? : Bool
      Native.synchronize do
        !variable?
      end
    end

    def with_encoding(encoding : Symbol | StringEncoding) : StringType
      Native.synchronize do
        self.class.new(@size, StringEncoding.parse(encoding), @padding)
      end
    end

    def to_hdf5_type_id : LibHDF5::Hid
      Native.synchronize do
        InternalChecks.ensure_herr(Native.h5open, "Failed to initialize HDF5")
        type_id = Native.h5tcopy(LibHDF5.h5t_c_s1_g)
        raise Error.new("Failed to copy string type") if type_id == LibHDF5::H5_INVALID_HID

        size_value = if variable?
                       LibC::SizeT::MAX
                     else
                       fixed_size = (@size || raise Error.new("Fixed string type requires size")).as(Int32)
                       raise Error.new("Fixed string size must be positive") if fixed_size <= 0
                       fixed_size.to_u64
                     end
        ret = Native.h5tset_size(type_id, size_value)
        if ret < 0
          Native.h5tclose(type_id)
          raise Error.new("Failed to set string size")
        end

        ret = Native.h5tset_cset(type_id, string_encoding_to_lib(@encoding))
        if ret < 0
          Native.h5tclose(type_id)
          raise Error.new("Failed to set string encoding")
        end

        ret = Native.h5tset_strpad(type_id, string_padding_to_lib(@padding).value)
        if ret < 0
          Native.h5tclose(type_id)
          raise Error.new("Failed to set string padding")
        end

        type_id
      end
    end

    private def string_encoding_to_lib(encoding : StringEncoding) : LibHDF5::CharSet
      case encoding.value
      when 0 then LibHDF5::CharSet::Ascii
      when 1 then LibHDF5::CharSet::Utf8
      else
        raise Error.new("Unsupported string encoding: #{encoding}")
      end
    end

    private def string_padding_to_lib(padding : StringPadding) : LibHDF5::StrPad
      case padding.value
      when 0 then LibHDF5::StrPad::NullTerm
      when 1 then LibHDF5::StrPad::NullPad
      when 2 then LibHDF5::StrPad::SpacePad
      else
        raise Error.new("Unsupported string padding: #{padding}")
      end
    end
  end

  record CompoundMember, name : String, offset : UInt64, datatype : Datatype

  class Datatype
    getter id : LibHDF5::Hid
    getter context : FileContext?
    @closed = false

    def initialize(@id : LibHDF5::Hid, @context : FileContext? = nil)
      @context.try(&.register(@id, :datatype))
      @owned_children = [] of Datatype
    end

    def type_class : LibHDF5::TypeClass
      Native.synchronize do
        ensure_open
        type_class = Native.h5tget_class(@id)
        raise Error.new("Failed to get datatype class") if type_class == LibHDF5::TypeClass::NoClass
        type_class
      end
    end

    def size : Int32
      Native.synchronize do
        ensure_open
        bytes = Native.h5tget_size(@id)
        raise Error.new("Failed to get datatype size") if bytes == 0
        bytes.to_i32
      end
    end

    def integer? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Integer
      end
    end

    def float? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Float
      end
    end

    def string? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::String
      end
    end

    def fixed_length_string? : Bool
      Native.synchronize do
        string? && !variable_length_string?
      end
    end

    def string_encoding : StringEncoding
      Native.synchronize do
        raise Error.new("Datatype is not string") unless string?
        cset = Native.h5tget_cset(@id)
        raise Error.new("Failed to get string encoding") if cset == LibHDF5::CharSet::Error
        StringEncoding.from_lib(cset)
      end
    end

    def string_padding : StringPadding
      Native.synchronize do
        raise Error.new("Datatype is not string") unless string?
        strpad = Native.h5tget_strpad(@id)
        raise Error.new("Failed to get string padding") if strpad == LibHDF5::StrPad::Error
        StringPadding.from_lib(strpad)
      end
    end

    def variable_length_string? : Bool
      Native.synchronize do
        return false unless string?
        result = Native.h5tis_variable_str(@id)
        raise Error.new("Failed to determine whether datatype is variable-length string") if result < 0
        result > 0
      end
    end

    def time? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Time
      end
    end

    def bitfield? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Bitfield
      end
    end

    def opaque? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Opaque
      end
    end

    def reference? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Reference
      end
    end

    def object_reference? : Bool
      Native.synchronize do
        reference? && InternalChecks.ensure_htri(Native.h5tequal(@id, LibHDF5.h5t_std_ref_g), "Failed to inspect reference datatype")
      end
    end

    def enum? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Enum
      end
    end

    def vlen? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Vlen
      end
    end

    def compound? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Compound
      end
    end

    def array? : Bool
      Native.synchronize do
        type_class == LibHDF5::TypeClass::Array
      end
    end

    def complex? : Bool
      Native.synchronize do
        return true if type_class == LibHDF5::TypeClass::Complex
        return false unless compound? && member_count == 2 && {8, 16}.includes?(size)
        r = Native.h5tget_member_index(@id, "r")
        i = Native.h5tget_member_index(@id, "i")
        return false if r < 0 || i < 0
        real = member(r)
        imag = member(i)
        complex_members?(real, imag)
      end
    end

    private def complex_members?(real, imag) : Bool
      real.offset == 0 && imag.offset == (size // 2) &&
        real.datatype.float? && imag.datatype.float? &&
        real.datatype.size == size // 2 && imag.datatype.size == size // 2 &&
        real.datatype.byte_order == imag.datatype.byte_order
    end

    def bool? : Bool
      Native.synchronize do
        return false unless enum? && size == 1 && Native.h5tget_nmembers(@id) == 2
        f = 0_i8
        t = 0_i8
        Native.h5tenum_valueof(@id, "FALSE", pointerof(f).as(Void*)) >= 0 &&
          Native.h5tenum_valueof(@id, "TRUE", pointerof(t).as(Void*)) >= 0 && f == 0 && t == 1
      end
    end

    def byte_order : LibHDF5::ByteOrder
      Native.synchronize do
        return members.first.datatype.byte_order if complex? && compound?
        order = Native.h5tget_order(@id)
        raise Error.new("Failed to get byte order") if order.error?
        order
      end
    end

    def precision : UInt64
      Native.synchronize do
        ensure_open
        value = Native.h5tget_precision(@id)
        raise Error.new("Failed to get precision") if value == 0
        value.to_u64
      end
    end

    def offset : Int32
      Native.synchronize do
        ensure_open
        value = Native.h5tget_offset(@id)
        raise Error.new("Failed to get bit offset") if value < 0
        value
      end
    end

    def signed? : Bool
      Native.synchronize do
        return false unless integer?
        sign = Native.h5tget_sign(@id)
        raise Error.new("Failed to get integer datatype sign") if sign == LibHDF5::Sign::Error
        sign == LibHDF5::Sign::Two
      end
    end

    def unsigned? : Bool
      Native.synchronize do
        integer? && !signed?
      end
    end

    def base_type : Datatype?
      Native.synchronize do
        return unless enum? || vlen? || array?
        type_id = Native.h5tget_super(@id)
        raise Error.new("Failed to get base datatype") if type_id == LibHDF5::H5_INVALID_HID
        own(Datatype.new(type_id, @context))
      end
    end

    def array_rank : Int32
      Native.synchronize do
        return 0 unless array?
        rank = Native.h5tget_array_ndims(@id)
        raise Error.new("Failed to get array datatype rank") if rank < 0
        rank
      end
    end

    def array_dims : Array(UInt64)
      Native.synchronize do
        n = array_rank
        return [] of UInt64 if n <= 0
        dims = Array(UInt64).new(n, 0_u64)
        ret = Native.h5tget_array_dims2(@id, dims.to_unsafe)
        raise Error.new("Failed to get array datatype dimensions") if ret < 0
        dims
      end
    end

    def member_count : Int32
      Native.synchronize do
        return 0 unless compound?
        count = Native.h5tget_nmembers(@id)
        raise Error.new("Failed to get compound member count") if count < 0
        count
      end
    end

    def member(index : Int) : CompoundMember
      Native.synchronize do
        raise Error.new("Datatype is not compound") unless compound?
        raise Error.new("Compound member index out of bounds") if index < 0 || index >= member_count

        name_ptr = Native.h5tget_member_name(@id, index.to_u32)
        raise Error.new("Failed to get compound member name") if name_ptr.null?

        begin
          type_id = Native.h5tget_member_type(@id, index.to_u32)
          raise Error.new("Failed to get compound member datatype") if type_id == LibHDF5::H5_INVALID_HID
          CompoundMember.new(
            String.new(name_ptr),
            Native.h5tget_member_offset(@id, index.to_u32).to_u64,
            own(Datatype.new(type_id, @context))
          )
        ensure
          Native.h5free_memory(name_ptr.as(Void*))
        end
      end
    end

    def members : Array(CompoundMember)
      Native.synchronize do
        Array(CompoundMember).new(member_count) { |index| member(index) }
      end
    end

    def close
      Native.synchronize do
        @owned_children.reverse_each(&.close)
        @owned_children.clear
        if ctx = @context
          ctx.close(@id)
        elsif @id != LibHDF5::H5_INVALID_HID
          InternalChecks.ensure_herr(Native.h5tclose(@id), "Failed to close datatype")
        end
        @id = LibHDF5::H5_INVALID_HID
        @closed = true
      end
    end

    def finalize
      close
    rescue
    end

    private def ensure_open
      @context.try(&.ensure_open(@id))
      raise ClosedObjectError.new("Datatype is closed") if @closed
    end

    private def own(datatype : Datatype) : Datatype
      @owned_children << datatype
      datatype
    end
  end

  module NativeType
    def self.for(type : T.class) forall T
      Native.synchronize do
        {% if T == Int8 %}
          LibHDF5.h5t_native_int8_g
        {% elsif T == UInt8 %}
          LibHDF5.h5t_native_uint8_g
        {% elsif T == Int16 %}
          LibHDF5.h5t_native_int16_g
        {% elsif T == UInt16 %}
          LibHDF5.h5t_native_uint16_g
        {% elsif T == Int32 %}
          LibHDF5.h5t_native_int32_g
        {% elsif T == UInt32 %}
          LibHDF5.h5t_native_uint32_g
        {% elsif T == Int64 %}
          LibHDF5.h5t_native_int64_g
        {% elsif T == UInt64 %}
          LibHDF5.h5t_native_uint64_g
        {% elsif T == Float32 %}
          LibHDF5.h5t_native_float_g
        {% elsif T == Float64 %}
          LibHDF5.h5t_native_double_g
        {% elsif T == HDF5::Reference %}
          LibHDF5.h5t_std_ref_g
        {% else %}
          {% raise "Unsupported HDF5 type: #{T}" %}
        {% end %}
      end
    end

    def self.variable_length_string : LibHDF5::Hid
      Native.synchronize do
        StringType.variable.to_hdf5_type_id
      end
    end

    def self.fixed_length_string(size : Int) : LibHDF5::Hid
      Native.synchronize do
        StringType.fixed(size).to_hdf5_type_id
      end
    end
  end

  module VLenType
    def self.for(type : T.class) : LibHDF5::Hid forall T
      Native.synchronize do
        {% if T < Number %}
          type_id = Native.h5tvlen_create(NativeType.for(T))
          raise Error.new("Failed to create variable-length datatype") if type_id == LibHDF5::H5_INVALID_HID
          type_id
        {% else %}
          {% raise "Unsupported variable-length base type: #{T}" %}
        {% end %}
      end
    end
  end
end
