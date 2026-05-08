module HDF5
  module DatasetStorage
    def self.read_all(dataset_id : LibHDF5::Hid, type : T.class, count : Int) : Array(T) forall T
      {% if T == HDF5::Reference %}
        refs = Array(LibHDF5::Reference).new(count) { LibHDF5::Reference.new }
        ret = LibHDF5.H5Dread(dataset_id, NativeType.for(Reference),
          LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, LibHDF5::H5P_DEFAULT,
          refs.to_unsafe.as(Void*))
        raise Error.new("Failed to read reference dataset") if ret < 0
        refs.map { |ref| Reference.new(ref) }
      {% elsif T < Array %}
        mem_space = Dataspace.simple([count.to_u64])
        begin
          read_vlen(dataset_id, T, mem_space.id, LibHDF5::H5S_ALL, count)
        ensure
          mem_space.close
        end
      {% else %}
        buf = Array(T).new(count) { T.zero }
        ret = LibHDF5.H5Dread(dataset_id, NativeType.for(T),
          LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, LibHDF5::H5P_DEFAULT,
          buf.to_unsafe.as(Void*))
        raise Error.new("Failed to read dataset") if ret < 0
        buf
      {% end %}
    end

    def self.read_selection(
      dataset_id : LibHDF5::Hid,
      type : T.class,
      mem_space_id : LibHDF5::Hid,
      file_space_id : LibHDF5::Hid,
      count : Int,
    ) : Array(T) forall T
      {% if T == HDF5::Reference %}
        refs = Array(LibHDF5::Reference).new(count) { LibHDF5::Reference.new }
        ret = LibHDF5.H5Dread(dataset_id, NativeType.for(Reference),
          mem_space_id, file_space_id, LibHDF5::H5P_DEFAULT,
          refs.to_unsafe.as(Void*))
        raise Error.new("Failed to read dataset with selection") if ret < 0
        refs.map { |ref| Reference.new(ref) }
      {% elsif T < Array %}
        read_vlen(dataset_id, T, mem_space_id, file_space_id, count)
      {% else %}
        buf = Array(T).new(count) { T.zero }
        ret = LibHDF5.H5Dread(dataset_id, NativeType.for(T),
          mem_space_id, file_space_id, LibHDF5::H5P_DEFAULT,
          buf.to_unsafe.as(Void*))
        raise Error.new("Failed to read dataset with selection") if ret < 0
        buf
      {% end %}
    end

    def self.write_all(dataset_id : LibHDF5::Hid, data : Array(T)) : Nil forall T
      {% if T == HDF5::Reference %}
        refs = data.map(&.to_hdf5_reference)
        ret = LibHDF5.H5Dwrite(dataset_id, NativeType.for(Reference),
          LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, LibHDF5::H5P_DEFAULT,
          refs.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset") if ret < 0
      {% elsif T < Array %}
        write_vlen(dataset_id, data, LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, "Failed to write dataset")
      {% else %}
        ret = LibHDF5.H5Dwrite(dataset_id, NativeType.for(T),
          LibHDF5::H5S_ALL, LibHDF5::H5S_ALL, LibHDF5::H5P_DEFAULT,
          data.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset") if ret < 0
      {% end %}
    end

    def self.write_selection(
      dataset_id : LibHDF5::Hid,
      data : Array(T),
      mem_space_id : LibHDF5::Hid,
      file_space_id : LibHDF5::Hid,
    ) : Nil forall T
      {% if T == HDF5::Reference %}
        refs = data.map(&.to_hdf5_reference)
        ret = LibHDF5.H5Dwrite(dataset_id, NativeType.for(Reference),
          mem_space_id, file_space_id, LibHDF5::H5P_DEFAULT,
          refs.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset with selection") if ret < 0
      {% elsif T < Array %}
        write_vlen(dataset_id, data, mem_space_id, file_space_id, "Failed to write dataset with selection")
      {% else %}
        ret = LibHDF5.H5Dwrite(dataset_id, NativeType.for(T),
          mem_space_id, file_space_id, LibHDF5::H5P_DEFAULT,
          data.to_unsafe.as(Void*))
        raise Error.new("Failed to write dataset with selection") if ret < 0
      {% end %}
    end

    private def self.read_vlen(
      dataset_id : LibHDF5::Hid,
      type : Array(T).class,
      mem_space_id : LibHDF5::Hid,
      file_space_id : LibHDF5::Hid,
      count : Int,
    ) : Array(Array(T)) forall T
      type_id = VLenType.for(T)
      vlens = Array(LibHDF5::VLen).new(count) { LibHDF5::VLen.new }
      ret = LibHDF5.H5Dread(dataset_id, type_id, mem_space_id, file_space_id,
        LibHDF5::H5P_DEFAULT, vlens.to_unsafe.as(Void*))
      if ret < 0
        LibHDF5.H5Tclose(type_id)
        raise Error.new("Failed to read variable-length dataset")
      end

      begin
        VLenStorage.read(Array(T), type_id, mem_space_id, count, vlens)
      ensure
        LibHDF5.H5Tclose(type_id)
      end
    end

    private def self.write_vlen(
      dataset_id : LibHDF5::Hid,
      data : Array(Array(T)),
      mem_space_id : LibHDF5::Hid,
      file_space_id : LibHDF5::Hid,
      error_message : String,
    ) : Nil forall T
      type_id = VLenType.for(T)
      vlens = VLenStorage.descriptors(data)
      ret = LibHDF5.H5Dwrite(dataset_id, type_id, mem_space_id, file_space_id,
        LibHDF5::H5P_DEFAULT, vlens.to_unsafe.as(Void*))
      LibHDF5.H5Tclose(type_id)
      raise Error.new(error_message) if ret < 0
    end
  end
end
