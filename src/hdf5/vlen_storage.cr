module HDF5
  module VLenStorage
    def self.read(
      type : Array(T).class,
      type_id : LibHDF5::Hid,
      space_id : LibHDF5::Hid,
      count : Int,
      buffer : Array(LibHDF5::VLen),
    ) : Array(Array(T)) forall T
      begin
        Array(Array(T)).new(count) do |index|
          vlen = buffer[index]
          row = Array(T).new(vlen.len.to_i)
          ptr = vlen.p.as(T*)
          vlen.len.to_i.times { |offset| row << ptr[offset] }
          row
        end
      ensure
        reclaim = LibHDF5.H5Dvlen_reclaim(type_id, space_id, LibHDF5::H5P_DEFAULT,
          buffer.to_unsafe.as(Void*))
        raise Error.new("Failed to reclaim variable-length memory") if reclaim < 0
      end
    end

    def self.descriptors(data : Array(Array(T))) : Array(LibHDF5::VLen) forall T
      data.map do |row|
        LibHDF5::VLen.new(
          len: LibC::SizeT.new(row.size),
          p: row.empty? ? Pointer(Void).null : row.to_unsafe.as(Void*)
        )
      end
    end
  end
end
