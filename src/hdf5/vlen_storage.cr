module HDF5
  module VLenStorage
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
