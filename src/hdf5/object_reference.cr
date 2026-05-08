module HDF5
  class ObjectReference
    getter ref : LibHDF5::Reference

    def self.create(location, path : String) : ObjectReference
      ref = uninitialized LibHDF5::Reference
      ret = LibHDF5.H5Rcreate_object(location_id(location), path, LibHDF5::H5P_DEFAULT, pointerof(ref))
      raise Error.new("Failed to create object reference to '#{path}'") if ret < 0
      new(ref)
    end

    def initialize(@ref : LibHDF5::Reference)
      @closed = false
    end

    def name : String
      ensure_open
      size = LibHDF5.H5Rget_obj_name(pointerof(@ref), LibHDF5::H5P_DEFAULT, nil, 0)
      raise Error.new("Failed to get object reference name size") if size < 0
      buf = Bytes.new(size + 1)
      ret = LibHDF5.H5Rget_obj_name(pointerof(@ref), LibHDF5::H5P_DEFAULT,
        buf.to_unsafe.as(UInt8*), LibC::SizeT.new(size + 1))
      raise Error.new("Failed to get object reference name") if ret < 0
      String.new(buf[0, size])
    end

    def file_name : String
      ensure_open
      size = LibHDF5.H5Rget_file_name(pointerof(@ref), nil, 0)
      raise Error.new("Failed to get object reference file name size") if size < 0
      buf = Bytes.new(size + 1)
      ret = LibHDF5.H5Rget_file_name(pointerof(@ref), buf.to_unsafe.as(UInt8*),
        LibC::SizeT.new(size + 1))
      raise Error.new("Failed to get object reference file name") if ret < 0
      String.new(buf[0, size])
    end

    def object_type : Symbol
      ensure_open
      type = LibHDF5::ObjType::Unknown
      ret = LibHDF5.H5Rget_obj_type3(pointerof(@ref), LibHDF5::H5P_DEFAULT, pointerof(type))
      raise Error.new("Failed to get object reference type") if ret < 0

      case type
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

    def open : Group | Dataset
      ensure_open
      object_id = LibHDF5.H5Ropen_object(pointerof(@ref), LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      raise Error.new("Failed to open object reference") if object_id == LibHDF5::H5_INVALID_HID

      object_type = LibHDF5.H5Iget_type(object_id)
      case object_type
      when LibHDF5::H5I_GROUP
        Group.new(object_id)
      when LibHDF5::H5I_DATASET
        Dataset.new(object_id)
      else
        LibHDF5.H5Oclose(object_id)
        raise Error.new("Unsupported object reference target type")
      end
    end

    def close : Nil
      return if @closed
      LibHDF5.H5Rdestroy(pointerof(@ref))
      @closed = true
    end

    def finalize
      close
    end

    private def self.location_id(location) : LibHDF5::Hid
      if location.responds_to?(:hid)
        location.hid
      elsif location.responds_to?(:id)
        location.id
      else
        raise Error.new("Object references require a File, Group, Dataset, or Attribute location")
      end
    end

    private def ensure_open : Nil
      raise ClosedObjectError.new("Object reference is closed") if @closed
    end
  end
end
