module HDF5
  module InternalChecks
    def self.ensure_hid(id : LibHDF5::Hid, message : String) : LibHDF5::Hid
      raise Error.new(message) if id == LibHDF5::H5_INVALID_HID
      id
    end

    def self.ensure_herr(ret : LibHDF5::Herr, message : String) : Nil
      raise Error.new(message) if ret < 0
    end

    def self.ensure_htri(ret : LibHDF5::Htri, message : String) : Bool
      raise Error.new(message) if ret < 0
      ret > 0
    end
  end
end
