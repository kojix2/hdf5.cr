module HDF5
  class File
    include Container

    H5F_ACC_RDONLY = 0x0000_u32
    H5F_ACC_RDWR   = 0x0001_u32
    H5F_ACC_TRUNC  = 0x0002_u32
    H5F_ACC_EXCL   = 0x0004_u32
    H5F_ACC_CREAT  = 0x0010_u32

    getter id : LibHDF5::Hid
    getter filename : String
    getter mode : Symbol

    def self.open(filename : String, mode : Symbol = :r) : File
      new(filename, mode)
    end

    def self.open(filename : String, mode : Symbol = :r, &block : File ->) : Nil
      f = new(filename, mode)
      begin
        block.call(f)
      ensure
        f.close
      end
    end

    def initialize(@filename : String, @mode : Symbol = :r)
      LibHDF5.H5open
      case mode
      when :r
        @id = LibHDF5.H5Fopen(filename, H5F_ACC_RDONLY, LibHDF5::H5P_DEFAULT)
      when :r_plus, :rw
        @id = LibHDF5.H5Fopen(filename, H5F_ACC_RDWR, LibHDF5::H5P_DEFAULT)
      when :w
        @id = LibHDF5.H5Fcreate(filename, H5F_ACC_TRUNC, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      when :a
        if ::File.exists?(filename)
          @id = LibHDF5.H5Fopen(filename, H5F_ACC_RDWR, LibHDF5::H5P_DEFAULT)
        else
          @id = LibHDF5.H5Fcreate(filename, H5F_ACC_TRUNC, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
        end
      when :excl
        @id = LibHDF5.H5Fcreate(filename, H5F_ACC_EXCL, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      else
        raise Error.new("Unknown file mode: #{mode}")
      end
      begin
        InternalChecks.ensure_hid(@id, "Failed to open/create HDF5 file '#{filename}' (mode=#{mode})")
      rescue Error
        raise FileError.new("Failed to open/create HDF5 file '#{filename}' (mode=#{mode})")
      end
    end

    def hid : LibHDF5::Hid
      @id
    end

    def flush
      LibHDF5.H5Fflush(@id, 0)
    end

    def close
      LibHDF5.H5Fclose(@id) if @id != LibHDF5::H5_INVALID_HID
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    end

    def self.accessible?(filename : String) : Bool
      LibHDF5.H5open
      LibHDF5.H5Fis_accessible(filename, LibHDF5::H5P_DEFAULT) > 0
    end
  end
end
