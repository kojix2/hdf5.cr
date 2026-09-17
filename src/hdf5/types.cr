require "complex"

module HDF5
  enum Casting
    Unsafe
    Safe
  end

  struct Empty(T)
  end

  struct Complex32
    getter real : Float32
    getter imag : Float32

    def initialize(real : Number, imag : Number = 0)
      @real = real.to_f32
      @imag = imag.to_f32
    end

    def self.new(value : Complex)
      new(value.real, value.imag)
    end

    def self.zero : self
      new(0, 0)
    end

    def to_c : Complex
      Complex.new(real, imag)
    end
  end

  module Shapes
    def self.normalize(shape : Indexable) : Array(UInt64)
      raise ShapeMismatchError.new("Too many dimensions") if shape.size > 32
      result = [] of UInt64
      shape.each do |dim|
        raise ShapeMismatchError.new("Dimensions must be integers") unless dim.is_a?(Int)
        raise ShapeMismatchError.new("Dimensions must be nonnegative") if dim < 0
        value = dim.to_u64
        raise ShapeMismatchError.new("Unlimited is only valid in maximum dimensions") if value == UInt64::MAX
        result << value
      end
      result
    rescue OverflowError
      raise ShapeMismatchError.new("Dimension is too large")
    end

    def self.maxima(shape : Indexable) : Array(UInt64)
      result = [] of UInt64
      shape.each do |dim|
        if dim.nil?
          result << UInt64::MAX
        else
          raise ShapeMismatchError.new("Maximum dimensions must be integers") unless dim.is_a?(Int)
          raise ShapeMismatchError.new("Maximum dimensions must be nonnegative") if dim < 0
          result << dim.to_u64
        end
      end
      result
    rescue OverflowError
      raise ShapeMismatchError.new("Maximum dimension is too large")
    end

    def self.count(shape : Array(UInt64)) : UInt64
      return 0_u64 if shape.includes?(0_u64)
      shape.reduce(1_u64) { |count, dim| count * dim }
    rescue OverflowError
      raise ShapeMismatchError.new("Shape element count overflows")
    end

    def self.buffer_count(count : Int64 | UInt64) : Int32
      raise ShapeMismatchError.new("Too many elements for one Crystal buffer; use each_block") unless 0 <= count <= Int32::MAX
      count.to_i32
    end

    def self.validate_count(shape : Array(UInt64), count : Int) : Nil
      raise ShapeMismatchError.new("Shape does not match #{count} elements") unless self.count(shape) == count
    end
  end
end
