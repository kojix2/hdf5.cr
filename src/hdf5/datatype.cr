module HDF5
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
