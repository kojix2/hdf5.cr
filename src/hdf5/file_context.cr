module HDF5
  # Owns native handles without retaining their Crystal wrappers.
  class FileContext
    @handles = {} of LibHDF5::Hid => Symbol
    @references = [] of Reference
    @closed = false
    @@contexts = [] of FileContext
    @@exit_cleanup_registered = false

    def initialize(@file_id : LibHDF5::Hid)
      register(@file_id, :file)
      Native.synchronize do
        @@contexts << self
        unless @@exit_cleanup_registered
          at_exit do
            Native.synchronize do
              @@contexts.dup.reverse_each do |context|
                context.close_file
              rescue
                # Explicit close reports failures; exit cleanup is best effort.
              end
            end
          end
          @@exit_cleanup_registered = true
        end
      end
    end

    def register(id : LibHDF5::Hid, kind : Symbol) : Nil
      Native.synchronize do
        ensure_open
        @handles[id] = kind
      end
    end

    def register(reference : Reference) : Nil
      Native.synchronize do
        ensure_open
        @references << reference
      end
    end

    def unregister(reference : Reference) : Nil
      Native.synchronize { @references.delete(reference) }
    end

    def ensure_open(id : LibHDF5::Hid? = nil) : Nil
      raise ClosedObjectError.new("HDF5 file is closed") if @closed
      raise ClosedObjectError.new("HDF5 object is closed") if id && !@handles.has_key?(id)
    end

    def closed? : Bool
      @closed
    end

    def close(id : LibHDF5::Hid) : Nil
      Native.synchronize do
        if kind = @handles[id]?
          status = case kind
                   when :file      then Native.h5fclose(id)
                   when :group     then Native.h5gclose(id)
                   when :dataset   then Native.h5dclose(id)
                   when :attribute then Native.h5aclose(id)
                   when :datatype  then Native.h5tclose(id)
                   when :dataspace then Native.h5sclose(id)
                   else                 raise Error.new("Unknown native handle kind")
                   end
          InternalChecks.ensure_herr(status, "Failed to close HDF5 #{kind}")
          @handles.delete(id)
        end
      end
    end

    def close_file : Nil
      Native.synchronize do
        return if @closed
        @references.dup.reverse_each(&.close)
        @references.clear
        @handles.keys.reverse_each { |id| close(id) unless id == @file_id }
        close(@file_id)
        @closed = true
        @@contexts.delete(self)
      end
    end
  end

  module Cleanup
    # A cleanup failure must not replace an exception from the user's block.
    def self.with(object, &)
      failed = false
      begin
        yield object
      rescue exception
        failed = true
        raise exception
      ensure
        begin
          object.close
        rescue exception
          raise exception unless failed
        end
      end
    end
  end
end
