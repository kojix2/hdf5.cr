module HDF5
  enum StringEncoding
    Ascii
    Utf8

    def self.parse(value : Symbol | StringEncoding) : StringEncoding
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

    def self.from_lib(value : LibHDF5::CharSet) : StringEncoding
      case value
      when LibHDF5::CharSet::Ascii then Ascii
      when LibHDF5::CharSet::Utf8  then Utf8
      else
        raise Error.new("Unknown HDF5 string character set: #{value}")
      end
    end
  end

  enum StringPadding
    NullTerm
    NullPad
    SpacePad

    def self.from_lib(value : LibHDF5::StrPad) : StringPadding
      case value
      when LibHDF5::StrPad::NullTerm then NullTerm
      when LibHDF5::StrPad::NullPad  then NullPad
      when LibHDF5::StrPad::SpacePad then SpacePad
      else
        raise Error.new("Unknown HDF5 string padding mode: #{value}")
      end
    end
  end

  struct StringType
    getter size : Int32?
    getter encoding : StringEncoding
    getter padding : StringPadding

    def initialize(@size : Int32?, @encoding : StringEncoding, @padding : StringPadding)
      # Validation for fixed sizes is performed when constructing HDF5 type ids.
    end

    def self.variable(encoding : Symbol | StringEncoding = StringEncoding::Utf8,
                      padding : StringPadding = StringPadding::NullTerm) : StringType
      new(nil, StringEncoding.parse(encoding), padding)
    end

    def self.fixed(size : Int,
                   encoding : Symbol | StringEncoding = StringEncoding::Utf8,
                   padding : StringPadding = StringPadding::NullPad) : StringType
      new(size.to_i32, StringEncoding.parse(encoding), padding)
    end

    def variable? : Bool
      @size.nil?
    end

    def fixed? : Bool
      !variable?
    end

    def with_encoding(encoding : Symbol | StringEncoding) : StringType
      self.class.new(@size, StringEncoding.parse(encoding), @padding)
    end

    def to_hdf5_type_id : LibHDF5::Hid
      type_id = LibHDF5.H5Tcopy(LibHDF5.h5t_c_s1_g)
      raise Error.new("Failed to copy string type") if type_id == LibHDF5::H5_INVALID_HID

      size_value = if variable?
                     LibC::SizeT::MAX
                   else
                     fixed_size = (@size || raise Error.new("Fixed string type requires size")).as(Int32)
                     fixed_size.to_u64
                   end
      ret = LibHDF5.H5Tset_size(type_id, size_value)
      if ret < 0
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to set string size")
      end

      ret = LibHDF5.H5Tset_cset(type_id, string_encoding_to_lib(@encoding))
      if ret < 0
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to set string encoding")
      end

      ret = LibHDF5.H5Tset_strpad(type_id, string_padding_to_lib(@padding).value)
      if ret < 0
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to set string padding")
      end

      type_id
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

    def initialize(@id : LibHDF5::Hid)
      @owned_children = [] of Datatype
    end

    def type_class : LibHDF5::TypeClass
      type_class = LibHDF5.H5Tget_class(@id)
      raise Error.new("Failed to get datatype class") if type_class == LibHDF5::TypeClass::NoClass
      type_class
    end

    def size : Int32
      bytes = LibHDF5.H5Tget_size(@id)
      raise Error.new("Failed to get datatype size") if bytes == 0
      bytes.to_i32
    end

    def integer? : Bool
      type_class == LibHDF5::TypeClass::Integer
    end

    def float? : Bool
      type_class == LibHDF5::TypeClass::Float
    end

    def string? : Bool
      type_class == LibHDF5::TypeClass::String
    end

    def fixed_length_string? : Bool
      string? && !variable_length_string?
    end

    def string_encoding : StringEncoding
      raise Error.new("Datatype is not string") unless string?
      cset = LibHDF5.H5Tget_cset(@id)
      raise Error.new("Failed to get string encoding") if cset == LibHDF5::CharSet::Error
      StringEncoding.from_lib(cset)
    end

    def string_padding : StringPadding
      raise Error.new("Datatype is not string") unless string?
      strpad = LibHDF5.H5Tget_strpad(@id)
      raise Error.new("Failed to get string padding") if strpad == LibHDF5::StrPad::Error
      StringPadding.from_lib(strpad)
    end

    def variable_length_string? : Bool
      return false unless string?
      result = LibHDF5.H5Tis_variable_str(@id)
      raise Error.new("Failed to determine whether datatype is variable-length string") if result < 0
      result > 0
    end

    def time? : Bool
      type_class == LibHDF5::TypeClass::Time
    end

    def bitfield? : Bool
      type_class == LibHDF5::TypeClass::Bitfield
    end

    def opaque? : Bool
      type_class == LibHDF5::TypeClass::Opaque
    end

    def reference? : Bool
      type_class == LibHDF5::TypeClass::Reference
    end

    def object_reference? : Bool
      reference? && LibHDF5.H5Tequal(@id, LibHDF5.h5t_std_ref_g) > 0
    end

    def enum? : Bool
      type_class == LibHDF5::TypeClass::Enum
    end

    def vlen? : Bool
      type_class == LibHDF5::TypeClass::Vlen
    end

    def compound? : Bool
      type_class == LibHDF5::TypeClass::Compound
    end

    def array? : Bool
      type_class == LibHDF5::TypeClass::Array
    end

    def complex? : Bool
      type_class == LibHDF5::TypeClass::Complex
    end

    def signed? : Bool
      return false unless integer?
      sign = LibHDF5.H5Tget_sign(@id)
      raise Error.new("Failed to get integer datatype sign") if sign == LibHDF5::Sign::Error
      sign == LibHDF5::Sign::Two
    end

    def unsigned? : Bool
      integer? && !signed?
    end

    def base_type : Datatype?
      return unless enum? || vlen? || array?
      type_id = LibHDF5.H5Tget_super(@id)
      raise Error.new("Failed to get base datatype") if type_id == LibHDF5::H5_INVALID_HID
      own(Datatype.new(type_id))
    end

    def array_rank : Int32
      return 0 unless array?
      rank = LibHDF5.H5Tget_array_ndims(@id)
      raise Error.new("Failed to get array datatype rank") if rank < 0
      rank
    end

    def array_dims : Array(UInt64)
      n = array_rank
      return [] of UInt64 if n <= 0
      dims = Array(UInt64).new(n, 0_u64)
      ret = LibHDF5.H5Tget_array_dims2(@id, dims.to_unsafe)
      raise Error.new("Failed to get array datatype dimensions") if ret < 0
      dims
    end

    def member_count : Int32
      return 0 unless compound?
      count = LibHDF5.H5Tget_nmembers(@id)
      raise Error.new("Failed to get compound member count") if count < 0
      count
    end

    def member(index : Int) : CompoundMember
      raise Error.new("Datatype is not compound") unless compound?
      raise Error.new("Compound member index out of bounds") if index < 0 || index >= member_count

      name_ptr = LibHDF5.H5Tget_member_name(@id, index.to_u32)
      raise Error.new("Failed to get compound member name") if name_ptr.null?

      begin
        type_id = LibHDF5.H5Tget_member_type(@id, index.to_u32)
        raise Error.new("Failed to get compound member datatype") if type_id == LibHDF5::H5_INVALID_HID
        CompoundMember.new(
          String.new(name_ptr),
          LibHDF5.H5Tget_member_offset(@id, index.to_u32).to_u64,
          own(Datatype.new(type_id))
        )
      ensure
        LibHDF5.H5free_memory(name_ptr.as(Void*))
      end
    end

    def members : Array(CompoundMember)
      Array(CompoundMember).new(member_count) { |index| member(index) }
    end

    def close
      @owned_children.reverse_each(&.close)
      @owned_children.clear
      LibHDF5.H5Tclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    private def own(datatype : Datatype) : Datatype
      @owned_children << datatype
      datatype
    end
  end

  module NativeType
    def self.for(type : T.class) forall T
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

    def self.variable_length_string : LibHDF5::Hid
      StringType.variable.to_hdf5_type_id
    end

    def self.fixed_length_string(size : Int) : LibHDF5::Hid
      StringType.fixed(size).to_hdf5_type_id
    end
  end

  module VLenType
    def self.for(type : T.class) : LibHDF5::Hid forall T
      {% if T < Number %}
        type_id = LibHDF5.H5Tvlen_create(NativeType.for(T))
        raise Error.new("Failed to create variable-length datatype") if type_id == LibHDF5::H5_INVALID_HID
        type_id
      {% else %}
        {% raise "Unsupported variable-length base type: #{T}" %}
      {% end %}
    end
  end
end
