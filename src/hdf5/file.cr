module HDF5
  class File
    include Container

    H5F_ACC_RDONLY = 0x0000_u32
    H5F_ACC_RDWR   = 0x0001_u32
    H5F_ACC_TRUNC  = 0x0002_u32
    H5F_ACC_EXCL   = 0x0004_u32
    H5F_ACC_CREAT  = 0x0010_u32

    @id : LibHDF5::Hid = LibHDF5::H5_INVALID_HID
    getter id : LibHDF5::Hid
    getter filename : String
    getter context : FileContext
    getter mode : Symbol

    def self.open(filename : String, mode : Symbol = :r) : File
      new(filename, mode)
    end

    def self.open(filename : String, mode : Symbol = :r, &block : File ->) : Nil
      Cleanup.with(new(filename, mode)) { |file| block.call(file) }
    end

    def initialize(@filename : String, @mode : Symbol = :r)
      InternalChecks.ensure_herr(Native.h5open, "Failed to initialize HDF5")
      case mode
      when :r
        @id = Native.h5fopen(filename, H5F_ACC_RDONLY, LibHDF5::H5P_DEFAULT)
      when :r_plus, :rw
        @id = Native.h5fopen(filename, H5F_ACC_RDWR, LibHDF5::H5P_DEFAULT)
      when :w
        @id = Native.h5fcreate(filename, H5F_ACC_TRUNC, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      when :a
        if ::File.exists?(filename)
          @id = Native.h5fopen(filename, H5F_ACC_RDWR, LibHDF5::H5P_DEFAULT)
        else
          @id = Native.h5fcreate(filename, H5F_ACC_EXCL, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
          # Another process may have created the file after the existence check.
          if @id < 0 && ::File.exists?(filename)
            @id = Native.h5fopen(filename, H5F_ACC_RDWR, LibHDF5::H5P_DEFAULT)
          end
        end
      when :excl, :x
        @id = Native.h5fcreate(filename, H5F_ACC_EXCL, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
      else
        raise Error.new("Unknown file mode: #{mode}")
      end
      begin
        InternalChecks.ensure_hid(@id, "Failed to open/create HDF5 file '#{filename}' (mode=#{mode})")
      rescue Error
        raise FileError.new("Failed to open/create HDF5 file '#{filename}' (mode=#{mode})")
      end
      @context = FileContext.new(@id)
    end

    def hid : LibHDF5::Hid
      raise ClosedObjectError.new("File is closed") if @id == LibHDF5::H5_INVALID_HID
      @context.ensure_open(@id)
      @id
    end

    def flush
      Native.synchronize { InternalChecks.ensure_herr(Native.h5fflush(hid, 0), "Failed to flush file") }
    end

    def closed? : Bool
      @context.closed?
    end

    def close
      return if @id == LibHDF5::H5_INVALID_HID
      @context.close_file
      @id = LibHDF5::H5_INVALID_HID
    end

    def finalize
      close
    rescue
    end

    def self.accessible?(filename : String) : Bool
      InternalChecks.ensure_herr(Native.h5open, "Failed to initialize HDF5")
      Native.h5fis_accessible(filename, LibHDF5::H5P_DEFAULT) > 0
    end
  end
end
