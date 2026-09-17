module HDF5
  # Shared buffer encoding for datasets, attributes and fill values.
  module Codec
    def self.transfer(read : Bool, kind : Symbol, id : LibHDF5::Hid, type : LibHDF5::Hid,
                      memory : LibHDF5::Hid, file : LibHDF5::Hid, buffer : Void*) : Nil
      status = case kind
               when :dataset
                 read ? Native.h5dread(id, type, memory, file, LibHDF5::H5P_DEFAULT, buffer) : Native.h5dwrite(id, type, memory, file, LibHDF5::H5P_DEFAULT, buffer)
               when :attribute
                 read ? Native.h5aread(id, type, buffer) : Native.h5awrite(id, type, buffer)
               when :fill
                 read ? Native.h5pget_fill_value(id, type, buffer) : Native.h5pset_fill_value(id, type, buffer)
               else
                 raise Error.new("Unknown storage kind")
               end
      InternalChecks.ensure_herr(status, "Failed to #{read ? "read" : "write"} #{kind}")
    end

    def self.read(kind : Symbol, id : LibHDF5::Hid, type : T.class, file_type : Datatype,
                  memory : LibHDF5::Hid, file : LibHDF5::Hid, count : Int,
                  context : FileContext? = nil, casting : Casting = Casting::Unsafe) : Array(T) forall T
      if count == 0
        Cleanup.with(TypeFactory.build(T)) { |target| CastingChecks.check(file_type, target, casting) }
        {% if T == String %}
          raise TypeMismatchError.new("Expected string datatype") unless file_type.string?
        {% elsif T == Bool %}
          raise TypeMismatchError.new("Expected Bool enum datatype") unless file_type.bool?
        {% elsif T == Reference %}
          raise TypeMismatchError.new("Expected object reference datatype") unless file_type.object_reference?
        {% end %}
        return [] of T
      end
      {% if T == String %}
        raise TypeMismatchError.new("Expected string datatype") unless file_type.string?
        read_strings(kind, id, file_type, memory, file, count)
      {% elsif T == Reference %}
        raise TypeMismatchError.new("Expected object reference datatype") unless file_type.object_reference?
        refs = Array(LibHDF5::Reference).new(count) { LibHDF5::Reference.new }
        begin
          transfer(true, kind, id, NativeType.for(Reference), memory, file, refs.to_unsafe.as(Void*))
        rescue exception
          refs.each_index { |i| Native.h5rdestroy(refs.to_unsafe + i) }
          raise exception
        end
        refs.map { |ref| Reference.new(ref, context) }
      {% elsif T < Array %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(file_type, dtype, casting)
          buffer = Array(LibHDF5::VLen).new(count) { LibHDF5::VLen.new }
          failed = false
          begin
            transfer(true, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
            Array(T).new(count) do |i|
              descriptor = buffer[i]
              Array({{ T.type_vars[0] }}).new(descriptor.len.to_i) { |j| descriptor.p.as({{ T.type_vars[0] }}*)[j] }
            end
          rescue exception
            failed = true
            raise exception
          ensure
            ret = Native.h5dvlen_reclaim(dtype.id, memory, LibHDF5::H5P_DEFAULT, buffer.to_unsafe.as(Void*))
            InternalChecks.ensure_herr(ret, "Failed to reclaim variable-length memory") unless failed
          end
        end
      {% elsif T == Bool %}
        raise TypeMismatchError.new("Expected Bool enum datatype") unless file_type.bool?
        Cleanup.with(TypeFactory.build(Bool)) do |dtype|
          buffer = Bytes.new(count)
          transfer(true, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
          buffer.map { |v| v != 0 }.to_a
        end
      {% elsif T == Complex || T == Complex32 %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(file_type, dtype, casting)
          if file_type.integer? || file_type.float?
            values = read(kind, id, Float64, file_type, memory, file, count, context)
            values.map { |v| T.new(v, 0) }
          else
            raise TypeMismatchError.new("Unsupported complex datatype") unless file_type.complex?
            {% if T == Complex %}
              buffer = Array(LibHDF5::Complex64).new(count) { LibHDF5::Complex64.new }
            {% else %}
              buffer = Array(LibHDF5::Complex32).new(count) { LibHDF5::Complex32.new }
            {% end %}
            transfer(true, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
            buffer.map { |v| T.new(v.real, v.imag) }
          end
        end
      {% else %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(file_type, dtype, casting)
          buffer = Array(T).new(count) { T.zero }
          transfer(true, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
          buffer
        end
      {% end %}
    end

    def self.write(kind : Symbol, id : LibHDF5::Hid, data : Indexable(T), file_type : Datatype,
                   memory : LibHDF5::Hid, file : LibHDF5::Hid,
                   casting : Casting = Casting::Unsafe) : Nil forall T
      {% if T == String %}
        raise TypeMismatchError.new("Expected string datatype") unless file_type.string?
        validate_strings(data, file_type, casting)
      {% end %}
      if data.empty?
        Cleanup.with(TypeFactory.build(T)) { |source| CastingChecks.check(source, file_type, casting) }
        return
      end
      {% if T == String %}
        write_strings(kind, id, data, file_type, memory, file)
      {% elsif T == Reference %}
        raise TypeMismatchError.new("Expected object reference datatype") unless file_type.object_reference?
        refs = [] of LibHDF5::Reference
        begin
          data.each { |reference| refs << reference.to_hdf5_reference }
          transfer(false, kind, id, NativeType.for(Reference), memory, file, refs.to_unsafe.as(Void*))
        ensure
          refs.each_index { |i| Native.h5rdestroy(refs.to_unsafe + i) }
        end
      {% elsif T < Array %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(dtype, file_type, casting)
          descriptors = VLenStorage.descriptors(data.to_a)
          transfer(false, kind, id, dtype.id, memory, file, descriptors.to_unsafe.as(Void*))
        end
      {% elsif T == Bool %}
        raise TypeMismatchError.new("Expected Bool enum datatype") unless file_type.bool?
        Cleanup.with(TypeFactory.build(Bool)) do |dtype|
          buffer = data.map { |v| v ? 1_u8 : 0_u8 }.to_a
          transfer(false, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
        end
      {% elsif T == Complex || T == Complex32 %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(dtype, file_type, casting)
          {% if T == Complex %}
            buffer = data.map { |v| LibHDF5::Complex64.new(real: v.real, imag: v.imag) }.to_a
          {% else %}
            buffer = data.map { |v| LibHDF5::Complex32.new(real: v.real, imag: v.imag) }.to_a
          {% end %}
          transfer(false, kind, id, dtype.id, memory, file, buffer.to_unsafe.as(Void*))
        end
      {% else %}
        Cleanup.with(TypeFactory.build(T)) do |dtype|
          CastingChecks.check(dtype, file_type, casting)
          if file_type.complex?
            values = data.map { |v| Complex.new(v.to_f64, 0) }.to_a
            write(kind, id, values, file_type, memory, file)
          else
            transfer(false, kind, id, dtype.id, memory, file, data.to_unsafe.as(Void*))
          end
        end
      {% end %}
    end

    def self.validate_strings(data : Indexable(String), encoding : StringEncoding) : Nil
      data.each do |value|
        raise TypeMismatchError.new("Strings cannot contain NUL") if value.includes?('\0')
        if encoding.ascii?
          raise TypeMismatchError.new("String is not ASCII") unless value.ascii_only?
        else
          raise TypeMismatchError.new("String is not valid UTF-8") unless value.valid_encoding?
        end
      end
    end

    def self.validate_strings(data : Indexable(String), dtype : Datatype, casting : Casting = Casting::Unsafe) : Nil
      raise TypeMismatchError.new("Expected string datatype") unless dtype.string?
      validate_strings(data, dtype.string_encoding)
      if casting.safe? && dtype.fixed_length_string?
        limit = dtype.string_padding.null_term? ? dtype.size - 1 : dtype.size
        raise TypeMismatchError.new("Fixed string conversion would truncate input") if data.any? { |string| string.bytesize > limit }
      end
    end

    private def self.read_strings(kind, id, file_type, memory, file, count) : Array(String)
      if file_type.variable_length_string?
        Cleanup.with(TypeFactory.build(String, string_type: StringType.variable(file_type.string_encoding))) do |dtype|
          pointers = Array(Pointer(UInt8)).new(count, Pointer(UInt8).null)
          failed = false
          begin
            transfer(true, kind, id, dtype.id, memory, file, pointers.to_unsafe.as(Void*))
            pointers.map { |ptr| ptr.null? ? "" : String.new(ptr) }
          rescue exception
            failed = true
            raise exception
          ensure
            ret = Native.h5dvlen_reclaim(dtype.id, memory, LibHDF5::H5P_DEFAULT, pointers.to_unsafe.as(Void*))
            InternalChecks.ensure_herr(ret, "Failed to reclaim string memory") unless failed
          end
        end
      else
        buffer = Bytes.new(count * file_type.size)
        transfer(true, kind, id, file_type.id, memory, file, buffer.to_unsafe.as(Void*))
        Array(String).new(count) do |i|
          bytes = buffer[i * file_type.size, file_type.size]
          if file_type.string_padding.space_pad?
            stop = bytes.size
            while stop > 0 && bytes[stop - 1] == 32
              stop -= 1
            end
            String.new(bytes[0, stop])
          else
            String.new(bytes[0, bytes.index(0_u8) || bytes.size])
          end
        end
      end
    end

    private def self.write_strings(kind, id, data, file_type, memory, file) : Nil
      if file_type.variable_length_string?
        Cleanup.with(TypeFactory.build(String, string_type: StringType.variable(file_type.string_encoding))) do |dtype|
          pointers = data.map(&.to_unsafe).to_a
          transfer(false, kind, id, dtype.id, memory, file, pointers.to_unsafe.as(Void*))
        end
      else
        length = file_type.size
        pad = file_type.string_padding.space_pad? ? 32_u8 : 0_u8
        buffer = Bytes.new(data.size * length, pad)
        max_length = file_type.string_padding.null_term? ? length - 1 : length
        data.each_with_index do |value, i|
          bytes = value.to_slice
          bytes[0, Math.min(bytes.size, max_length)].copy_to(buffer[i * length, length])
        end
        transfer(false, kind, id, file_type.id, memory, file, buffer.to_unsafe.as(Void*))
      end
    end
  end
end
