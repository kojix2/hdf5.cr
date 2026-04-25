module HDF5
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
