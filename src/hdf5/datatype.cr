module HDF5
  record CompoundMember, name : String, offset : UInt64, datatype : Datatype

  class Datatype
    getter id : LibHDF5::Hid

    def initialize(@id : LibHDF5::Hid)
    end

    def type_class : LibHDF5::TypeClass
      LibHDF5.H5Tget_class(@id)
    end

    def size : Int32
      LibHDF5.H5Tget_size(@id).to_i32
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

    def variable_length_string? : Bool
      string? && LibHDF5.H5Tis_variable_str(@id) > 0
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
      integer? && LibHDF5.H5Tget_sign(@id) == LibHDF5::Sign::Two
    end

    def unsigned? : Bool
      integer? && !signed?
    end

    def base_type : Datatype?
      return unless enum? || vlen? || array?
      type_id = LibHDF5.H5Tget_super(@id)
      return if type_id == LibHDF5::H5_INVALID_HID
      Datatype.new(type_id)
    end

    def array_rank : Int32
      return 0 unless array?
      LibHDF5.H5Tget_array_ndims(@id)
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
      LibHDF5.H5Tget_nmembers(@id)
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
          Datatype.new(type_id)
        )
      ensure
        LibHDF5.H5free_memory(name_ptr.as(Void*))
      end
    end

    def members : Array(CompoundMember)
      Array(CompoundMember).new(member_count) { |index| member(index) }
    end

    def close
      LibHDF5.H5Tclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
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
      {% else %}
        {% raise "Unsupported HDF5 type: #{T}" %}
      {% end %}
    end

    def self.variable_length_string : LibHDF5::Hid
      tid = LibHDF5.H5Tcopy(LibHDF5.h5t_c_s1_g)
      raise Error.new("Failed to copy string type") if tid == LibHDF5::H5_INVALID_HID
      ret = LibHDF5.H5Tset_size(tid, LibC::SizeT::MAX)
      raise Error.new("Failed to set string size") if ret < 0
      tid
    end

    def self.fixed_length_string(size : Int) : LibHDF5::Hid
      tid = LibHDF5.H5Tcopy(LibHDF5.h5t_c_s1_g)
      raise Error.new("Failed to copy string type") if tid == LibHDF5::H5_INVALID_HID
      ret = LibHDF5.H5Tset_size(tid, LibC::SizeT.new(size))
      raise Error.new("Failed to set string size") if ret < 0
      tid
    end
  end
end
