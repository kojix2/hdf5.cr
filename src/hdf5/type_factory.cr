module HDF5
  module TypeFactory
    def self.build(type : T.class, storage : Bool = false,
                   string_type : StringType = StringType.variable) : Datatype forall T
      InternalChecks.ensure_herr(Native.h5open, "Failed to initialize HDF5")
      {% if T == String %}
        Datatype.new(string_type.to_hdf5_type_id)
      {% elsif T == Bool %}
        base = storage ? LibHDF5.h5t_std_i8le_g : NativeType.for(Int8)
        id = InternalChecks.ensure_hid(Native.h5tenum_create(base), "Failed to create Bool datatype")
        begin
          f = 0_i8
          t = 1_i8
          InternalChecks.ensure_herr(Native.h5tenum_insert(id, "FALSE", pointerof(f).as(Void*)), "Failed to define FALSE")
          InternalChecks.ensure_herr(Native.h5tenum_insert(id, "TRUE", pointerof(t).as(Void*)), "Failed to define TRUE")
          Datatype.new(id)
        rescue exception
          Native.h5tclose(id)
          raise exception
        end
      {% elsif T == Complex || T == Complex32 %}
        {% if T == Complex %}
          component = storage ? LibHDF5.h5t_ieee_f64le_g : NativeType.for(Float64)
          size = 16
        {% else %}
          component = storage ? LibHDF5.h5t_ieee_f32le_g : NativeType.for(Float32)
          size = 8
        {% end %}
        id = InternalChecks.ensure_hid(Native.h5tcreate(LibHDF5::TypeClass::Compound, size.to_u64), "Failed to create complex datatype")
        begin
          InternalChecks.ensure_herr(Native.h5tinsert(id, "r", 0_u64, component), "Failed to define real member")
          InternalChecks.ensure_herr(Native.h5tinsert(id, "i", (size // 2).to_u64, component), "Failed to define imaginary member")
          Datatype.new(id)
        rescue exception
          Native.h5tclose(id)
          raise exception
        end
      {% elsif T < Array %}
        Datatype.new(VLenType.for({{ T.type_vars[0] }}))
      {% else %}
        native = NativeType.for(T)
        if storage
          {% for name, global in {Int8: "i8", UInt8: "u8", Int16: "i16", UInt16: "u16", Int32: "i32", UInt32: "u32", Int64: "i64", UInt64: "u64"} %}
            {% if T.stringify == name.stringify %}
              native = LibHDF5.h5t_std_{{ global.id }}le_g
            {% end %}
          {% end %}
          {% if T == Float32 %}
            native = LibHDF5.h5t_ieee_f32le_g
          {% elsif T == Float64 %}
            native = LibHDF5.h5t_ieee_f64le_g
          {% end %}
        end
        Datatype.new(InternalChecks.ensure_hid(Native.h5tcopy(native), "Failed to copy datatype"))
      {% end %}
    end
  end

  module CastingChecks
    def self.check(source : Datatype, target : Datatype, casting : Casting) : Nil
      return if casting.unsafe?
      raise TypeMismatchError.new("Conversion would lose information; use Casting::Unsafe to permit it") unless lossless?(source, target, casting)
    end

    private def self.lossless?(source : Datatype, target : Datatype, casting : Casting) : Bool
      return source.bool? && target.bool? if source.bool? || target.bool?
      if source.vlen? && target.vlen?
        source_base = source.base_type || raise TypeMismatchError.new("Missing source base datatype")
        target_base = target.base_type || raise TypeMismatchError.new("Missing target base datatype")
        check(source_base, target_base, casting)
        return true
      end
      numeric_conversion?(source, target, casting) || Native.h5tequal(source.id, target.id) > 0 || (source.string? && target.string?)
    end

    private def self.numeric_conversion?(source : Datatype, target : Datatype, casting : Casting) : Bool
      if source.integer?
        integer_conversion?(source, target, casting)
      elsif source.float?
        float_conversion?(source, target, casting)
      else
        source.complex? && target.complex? && source.size <= target.size
      end
    end

    private def self.integer_conversion?(source : Datatype, target : Datatype, casting : Casting) : Bool
      if target.integer?
        if source.signed? == target.signed?
          source.precision <= target.precision
        else
          source.unsigned? && target.signed? && source.precision < target.precision
        end
      elsif target.float?
        source.precision - (source.signed? ? 1 : 0) <= (target.size == 4 ? 24 : 53)
      elsif target.complex?
        check(source, target.members.first.datatype, casting)
        true
      else
        false
      end
    end

    private def self.float_conversion?(source : Datatype, target : Datatype, casting : Casting) : Bool
      if target.float?
        source.size <= target.size
      elsif target.complex?
        check(source, target.members.first.datatype, casting)
        true
      else
        false
      end
    end

    def self.scalar(value : T, target : Datatype, casting : Casting) : Nil forall T
      return if casting.unsafe?
      {% if T < Number || T == Complex32 %}
        {% if T == Complex || T == Complex32 %}
          raise TypeMismatchError.new("Cannot discard imaginary component") if !target.complex? && value.imag != 0
          real = value.real
        {% else %}
          real = value
        {% end %}
        if target.integer?
          raise TypeMismatchError.new("Cannot store fractional value as integer") unless real == real.trunc
          bits = target.precision.to_i
          low = target.signed? ? -(1_i128 << (bits - 1)) : 0_i128
          high = target.signed? ? (1_i128 << (bits - 1)) - 1 : (1_i128 << bits) - 1
          raise TypeMismatchError.new("Integer value out of range") unless real >= low && real <= high
        elsif target.float? || target.complex?
          bytes = target.complex? ? target.size // 2 : target.size
          converted = bytes == 4 ? real.to_f32.to_f64 : real.to_f64
          {% if T < Int %}
            exact = converted.finite? && converted.to_i128 == real
          {% else %}
            exact = converted == real || (converted.nan? && real.to_f64.nan?)
          {% end %}
          raise TypeMismatchError.new("Floating conversion would lose information") unless exact
          {% if T == Complex || T == Complex32 %}
            if bytes == 4
              imag = value.imag.to_f32.to_f64
              raise TypeMismatchError.new("Imaginary conversion would lose information") unless imag == value.imag || (imag.nan? && value.imag.nan?)
            end
          {% end %}
        else
          Cleanup.with(TypeFactory.build(T)) { |source| check(source, target, casting) }
        end
      {% elsif T == String %}
        Codec.validate_strings([value], target, casting)
      {% else %}
        Cleanup.with(TypeFactory.build(T)) { |source| check(source, target, casting) }
      {% end %}
    rescue OverflowError
      raise TypeMismatchError.new("Value out of range")
    end
  end
end
