module HDF5
  struct HardLink
  end

  record SoftLink, target : String
  record ExternalLink, filename : String, path : String
  alias LinkInfo = HardLink | SoftLink | ExternalLink

  module Container
    def move(source : String, destination : String) : Nil
      Native.synchronize do
        with_link_create_plist do |lcpl|
          InternalChecks.ensure_herr(Native.h5lmove(hid, source, hid, destination, lcpl,
            LibHDF5::H5P_DEFAULT), "Failed to move link '#{source}'")
        end
      end
    end

    def link_info(path : String) : LinkInfo
      Native.synchronize do
        info = LibHDF5::LinkInfo.new
        InternalChecks.ensure_herr(Native.h5lget_info2(hid, path, pointerof(info), LibHDF5::H5P_DEFAULT), "Failed to inspect link '#{path}'")
        return HardLink.new if info.type == 0
        buffer = Bytes.new(info.value.size.to_i)
        InternalChecks.ensure_herr(Native.h5lget_val(hid, path, buffer.to_unsafe.as(Void*),
          buffer.size.to_u64, LibHDF5::H5P_DEFAULT), "Failed to read link '#{path}'")
        case info.type
        when 1
          SoftLink.new(String.new(buffer.to_unsafe))
        when 64
          flags = 0_u32
          filename = Pointer(UInt8).null
          target = Pointer(UInt8).null
          InternalChecks.ensure_herr(Native.h5lunpack_elink_val(buffer.to_unsafe.as(Void*),
            buffer.size.to_u64, pointerof(flags), pointerof(filename), pointerof(target)), "Failed to unpack external link")
          ExternalLink.new(String.new(filename), String.new(target))
        else
          raise TypeMismatchError.new("Unsupported link type #{info.type}")
        end
      end
    end
  end
end
