module HDF5
  class Selection
    record Slice,
      start : Int64,
      count : Int64,
      stride : Int64 = 1_i64,
      block : Int64 = 1_i64,
      range : Bool = false,
      range_end : Int64? = nil,
      exclusive : Bool = false,
      index : Bool = false

    getter slices : Array(Slice?)

    def initialize(@slices : Array(Slice?))
    end

    def self.hyperslab(start : Indexable, count : Indexable,
                       stride : Indexable? = nil, block : Indexable? = nil) : Selection
      rank = start.size
      raise IndexError.new("Hyperslab ranks must match") unless count.size == rank &&
                                                                (stride.nil? || stride.size == rank) && (block.nil? || block.size == rank)
      new(Array(Slice?).new(rank) do |i|
        Slice.new(integer_axis(start[i]), integer_axis(count[i]),
          stride ? integer_axis(stride[i]) : 1_i64, block ? integer_axis(block[i]) : 1_i64)
      end)
    end

    private def self.integer_axis(value) : Int64
      raise IndexError.new("Hyperslab values must be integers") unless value.is_a?(Int)
      value.to_i64
    rescue OverflowError
      raise IndexError.new("Hyperslab value is too large")
    end

    def normalize(shape : Array(UInt64)) : Selection
      raise IndexError.new("Too many selection axes") if slices.size > shape.size
      normalized = Array(Slice?).new(shape.size) do |i|
        dimension = shape[i].to_i64
        if axis = slices[i]?
          normalize_axis(axis, dimension)
        else
          Slice.new(0_i64, dimension)
        end
      end
      Selection.new(normalized)
    rescue OverflowError
      raise IndexError.new("Selection is too large")
    end

    private def normalize_axis(axis : Slice, dimension : Int64) : Slice
      raise IndexError.new("Stride and block must be positive") if axis.stride <= 0 || axis.block <= 0
      if axis.index
        normalize_index(axis, dimension)
      elsif axis.range
        normalize_range(axis, dimension)
      else
        normalize_hyperslab(axis, dimension)
      end
    end

    private def normalize_index(axis : Slice, dimension : Int64) : Slice
      start = axis.start < 0 ? dimension + axis.start : axis.start
      raise IndexError.new("Index outside dimension of size #{dimension}") unless 0 <= start < dimension
      Slice.new(start, 1_i64, index: true)
    end

    private def normalize_range(axis : Slice, dimension : Int64) : Slice
      start = axis.start < 0 ? dimension + axis.start : axis.start
      if last = axis.range_end
        last += dimension if last < 0
        last += 1 unless axis.exclusive
      else
        last = dimension
      end
      start = start.clamp(0_i64, dimension)
      last = last.clamp(start, dimension)
      count = (last - start + axis.stride - 1) // axis.stride
      Slice.new(start, count, axis.stride)
    end

    private def normalize_hyperslab(axis : Slice, dimension : Int64) : Slice
      raise IndexError.new("Invalid hyperslab") if axis.start < 0 || axis.count < 0 || (axis.count > 1 && axis.stride < axis.block)
      if axis.count > 0
        limit = axis.start + (axis.count - 1) * axis.stride + axis.block
        raise IndexError.new("Hyperslab outside dimension") if limit > dimension
      elsif axis.start > dimension
        raise IndexError.new("Empty hyperslab outside dimension")
      end
      axis
    end

    def result_shape(shape : Indexable) : Array(UInt64)
      normalize(Shapes.normalize(shape)).slices.compact.reject(&.index).map { |axis| (axis.count * axis.block).to_u64 }
    end

    def apply_to(space_id : LibHDF5::Hid) : Nil
      rank = Native.h5sget_simple_extent_ndims(space_id)
      raise Error.new("Failed to get dataspace rank") if rank < 0
      shape = Array(UInt64).new(rank, 0_u64)
      InternalChecks.ensure_herr(Native.h5sget_simple_extent_dims(space_id, shape.to_unsafe, nil), "Failed to get dimensions")
      axes = normalize(shape).slices.compact
      if axes.any? { |axis| axis.count == 0 }
        InternalChecks.ensure_herr(Native.h5sselect_none(space_id), "Failed to select empty region")
      elsif rank == 0
        InternalChecks.ensure_herr(Native.h5sselect_all(space_id), "Failed to select scalar")
      else
        starts = axes.map(&.start.to_u64)
        counts = axes.map(&.count.to_u64)
        strides = axes.map(&.stride.to_u64)
        blocks = axes.map(&.block.to_u64)
        InternalChecks.ensure_herr(Native.h5sselect_hyperslab(space_id, 0, starts.to_unsafe,
          strides.to_unsafe, counts.to_unsafe, blocks.to_unsafe), "Failed to select hyperslab")
      end
    end

    def npoints(space_id : LibHDF5::Hid) : Int64
      apply_to(space_id)
      count = Native.h5sget_select_npoints(space_id)
      raise Error.new("Failed to get selection size") if count < 0
      count
    end

    # Tiles logical result coordinates, preserving stride and dropped axes.
    def each_tile(shape : Array(UInt64), max_elements : Int, &block : Selection ->) : Nil
      normalized = normalize(shape)
      axes = normalized.slices.compact
      logical_shape = axes.map { |a| (a.count * a.block).to_u64 }
      blocks = self.class.block_shape(logical_shape, max_elements)
      self.class.each_region(logical_shape, blocks) do |region|
        tile_axes = region.slices.compact
        # Unit-block selections can be tiled directly. Block hyperslabs are
        # decomposed to single contiguous block fragments along each axis.
        if axes.all? { |a| a.block == 1 }
          tile = Array(Slice?).new(axes.size) do |i|
            a = axes[i]
            r = tile_axes[i]
            Slice.new(a.start + r.start * a.stride, r.count, a.stride, index: a.index)
          end
          block.call(Selection.new(tile))
        else
          each_point_tile(axes, tile_axes, 0, [] of Slice?) { |tile| block.call(tile) }
        end
      end
    end

    private def each_point_tile(axes, tiles, axis, prefix, &block : Selection ->) : Nil
      if axis == axes.size
        yield Selection.new(prefix)
      else
        a = axes[axis]
        t = tiles[axis]
        t.count.times do |i|
          logical = t.start + i
          position = a.start + (logical // a.block) * a.stride + logical % a.block
          each_point_tile(axes, tiles, axis + 1, prefix + [Slice.new(position, 1_i64, index: a.index)], &block)
        end
      end
    end

    def self.block_shape(shape : Array(UInt64), max_elements : Int) : Array(UInt64)
      raise ArgumentError.new("Element budget must be positive") if max_elements <= 0
      remaining = max_elements.to_u64
      blocks = Array(UInt64).new(shape.size, 1_u64)
      (shape.size - 1).downto(0) do |i|
        blocks[i] = Math.min(Math.max(shape[i], 1_u64), remaining)
        remaining = Math.max(remaining // blocks[i], 1_u64)
      end
      blocks
    end

    def self.each_region(shape : Array(UInt64), blocks : Array(UInt64), &block : Selection ->) : Nil
      return if shape.includes?(0_u64)
      walk_regions(shape, blocks, 0, [] of Slice?, &block)
    end

    private def self.walk_regions(shape, blocks, axis, prefix, &block : Selection ->) : Nil
      if axis == shape.size
        yield new(prefix)
      else
        start = 0_u64
        while start < shape[axis]
          count = Math.min(blocks[axis], shape[axis] - start)
          walk_regions(shape, blocks, axis + 1, prefix + [Slice.new(start.to_i64, count.to_i64)], &block)
          start += count
        end
      end
    end
  end

  class SelectionProxy
    def [](*dims) : Selection
      slices = [] of Selection::Slice?
      dims.each { |dim| slices << parse_dim(dim) }
      Selection.new(slices)
    rescue OverflowError
      raise IndexError.new("Selector is too large")
    end

    private def parse_dim(dim : Int) : Selection::Slice
      Selection::Slice.new(dim.to_i64, 1_i64, index: true)
    end

    private def parse_dim(dim : Range) : Selection::Slice
      first = dim.begin
      last = dim.end
      raise IndexError.new("Range endpoints must be integers") unless (first.nil? || first.is_a?(Int)) && (last.nil? || last.is_a?(Int))
      start = first ? first.to_i64 : 0_i64
      finish = last ? last.to_i64 : nil
      count = finish ? Math.max(finish - start + (dim.exclusive? ? 0 : 1), 0_i64) : 0_i64
      Selection::Slice.new(start, count, range: true, range_end: finish, exclusive: dim.exclusive?)
    end

    private def parse_dim(dim : Selection::Slice) : Selection::Slice
      dim
    end

    private def parse_dim(dim : Symbol) : Selection::Slice?
      raise IndexError.new("Only :all is a valid axis symbol") unless dim == :all
      nil
    end

    private def parse_dim(dim : Nil) : Selection::Slice?
      nil
    end

    private def parse_dim(dim) : Selection::Slice?
      raise IndexError.new("Unsupported selector #{dim}")
    end
  end

  def self.s : SelectionProxy
    SelectionProxy.new
  end

  def self.slice(range : Range, *, step : Int) : Selection::Slice
    raise IndexError.new("Slice step must be positive") if step <= 0
    axis = s[range].slices.first || raise IndexError.new("Expected a range selector")
    Selection::Slice.new(axis.start, axis.count, step.to_i64, range: true,
      range_end: axis.range_end, exclusive: axis.exclusive)
  end

  def self.all : Symbol
    :all
  end

  def self.unlimited : UInt64
    UInt64::MAX
  end
end
