module HDF5
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

    def variable_length_string? : Bool
      string? && LibHDF5.H5Tis_variable_str(@id) > 0
    end

    def reference? : Bool
      type_class == LibHDF5::TypeClass::Reference
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
