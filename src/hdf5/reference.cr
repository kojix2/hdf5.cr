module HDF5
  class Reference
    def self.object(location, path : String) : Reference
      Native.synchronize do
        ref = LibHDF5::Reference.new
        ret = Native.h5rcreate_object(location_id(location), path, LibHDF5::H5P_DEFAULT, pointerof(ref))
        raise Error.new("Failed to create object reference to '#{path}'") if ret < 0
        new(ref, location.context)
      end
    end

    def initialize(@ref : LibHDF5::Reference, @context : FileContext? = nil)
      @context.try(&.register(self))
      @closed = false
    end

    def target_path : String
      Native.synchronize do
        ensure_open
        size = Native.h5rget_obj_name(pointerof(@ref), LibHDF5::H5P_DEFAULT, nil, 0)
        raise Error.new("Failed to get reference target name size") if size < 0
        buf = Bytes.new(size + 1)
        ret = Native.h5rget_obj_name(pointerof(@ref), LibHDF5::H5P_DEFAULT,
          buf.to_unsafe.as(UInt8*), LibC::SizeT.new(size + 1))
        raise Error.new("Failed to get reference target name") if ret < 0
        String.new(buf[0, size])
      end
    end

    def file_name : String
      Native.synchronize do
        ensure_open
        size = Native.h5rget_file_name(pointerof(@ref), nil, 0)
        raise Error.new("Failed to get reference file name size") if size < 0
        buf = Bytes.new(size + 1)
        ret = Native.h5rget_file_name(pointerof(@ref), buf.to_unsafe.as(UInt8*),
          LibC::SizeT.new(size + 1))
        raise Error.new("Failed to get reference file name") if ret < 0
        String.new(buf[0, size])
      end
    end

    def target_type : Symbol
      Native.synchronize do
        ensure_open
        type = LibHDF5::ObjType::Unknown
        ret = Native.h5rget_obj_type3(pointerof(@ref), LibHDF5::H5P_DEFAULT, pointerof(type))
        raise Error.new("Failed to get reference target type") if ret < 0

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
    end

    def open : Group | Dataset
      Native.synchronize do
        ensure_open
        object_id = Native.h5ropen_object(pointerof(@ref), LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
        raise Error.new("Failed to open referenced object") if object_id == LibHDF5::H5_INVALID_HID

        object_type = Native.h5iget_type(object_id)
        case object_type
        when LibHDF5::H5I_GROUP
          Group.new(object_id, @context)
        when LibHDF5::H5I_DATASET
          Dataset.new(object_id, @context)
        else
          Native.h5oclose(object_id)
          raise Error.new("Unsupported reference target type")
        end
      end
    end

    def closed? : Bool
      @closed || !!@context.try(&.closed?)
    end

    def close : Nil
      Native.synchronize do
        return if @closed
        InternalChecks.ensure_herr(Native.h5rdestroy(pointerof(@ref)), "Failed to destroy reference")
        @closed = true
        @context.try(&.unregister(self))
      end
    end

    def finalize
      close
    rescue
    end

    def dup : Reference
      Native.synchronize do
        Reference.new(to_hdf5_reference, @context)
      end
    end

    # Returns an owned native copy. Low-level callers must H5Rdestroy it.
    def to_hdf5_reference : LibHDF5::Reference
      Native.synchronize do
        ensure_open
        copy = LibHDF5::Reference.new
        InternalChecks.ensure_herr(Native.h5rcopy(pointerof(@ref), pointerof(copy)), "Failed to copy reference")
        copy
      end
    end

    private def self.location_id(location) : LibHDF5::Hid
      if location.responds_to?(:hid)
        location.hid
      elsif location.responds_to?(:id)
        location.id
      else
        raise Error.new("References require a File, Group, Dataset, or Attribute location")
      end
    end

    private def ensure_open : Nil
      @context.try(&.ensure_open)
      raise ClosedObjectError.new("Reference is closed") if @closed
    end
  end
end
