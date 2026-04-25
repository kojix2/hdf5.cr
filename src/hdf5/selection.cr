module HDF5
  class Selection
    record Slice,
      start : Int64,
      count : Int64,
      stride : Int64 = 1_i64,
      block : Int64 = 1_i64

    getter slices : Array(Slice?)

    def initialize(@slices : Array(Slice?))
    end

    def self.hyperslab(
      start : Indexable,
      count : Indexable,
      stride : Indexable? = nil,
      block : Indexable? = nil,
    ) : Selection
      rank = start.size
      slices = Array(Slice?).new(rank) do |i|
        Slice.new(
          start: start[i].to_i64,
          count: count[i].to_i64,
          stride: stride ? stride[i].to_i64 : 1_i64,
          block: block ? block[i].to_i64 : 1_i64
        )
      end
      new(slices)
    end

    def apply_to(space_id : LibHDF5::Hid) : Nil
      ndims = LibHDF5.H5Sget_simple_extent_ndims(space_id)
      actual = Array(LibHDF5::Hsize).new(ndims, 0_u64)
      LibHDF5.H5Sget_simple_extent_dims(space_id, actual.to_unsafe, nil)

      starts = Array(LibHDF5::Hsize).new(ndims, 0_u64)
      counts = Array(LibHDF5::Hsize).new(ndims, 0_u64)
      strides = Array(LibHDF5::Hsize).new(ndims, 1_u64)
      blocks = Array(LibHDF5::Hsize).new(ndims, 1_u64)

      @slices.each_with_index do |slice, idx|
        break if idx >= ndims
        if slice
          starts[idx] = slice.start.to_u64
          counts[idx] = slice.count.to_u64
          strides[idx] = slice.stride.to_u64
          blocks[idx] = slice.block.to_u64
        else
          starts[idx] = 0_u64
          counts[idx] = actual[idx]
          strides[idx] = 1_u64
          blocks[idx] = 1_u64
        end
      end

      ret = LibHDF5.H5Sselect_hyperslab(space_id, 0, starts.to_unsafe, strides.to_unsafe,
        counts.to_unsafe, blocks.to_unsafe)
      raise Error.new("Failed to apply selection") if ret < 0
    end

    def npoints(space_id : LibHDF5::Hid) : Int64
      apply_to(space_id)
      LibHDF5.H5Sget_select_npoints(space_id)
    end
  end

  class SelectionProxy
    def [](*dims) : Selection
      slices = Array(Selection::Slice?).new
      dims.each do |dim|
        slices << parse_dim(dim)
      end
      Selection.new(slices)
    end

    private def parse_dim(dim : Int) : Selection::Slice
      Selection::Slice.new(start: dim.to_i64, count: 1_i64)
    end

    private def parse_dim(dim : Range) : Selection::Slice?
      b = dim.begin
      e = dim.end
      return if b.nil? && e.nil?
      start_val = (b || 0).to_i64
      if e.nil?
        nil
      else
        end_val = e.to_i64
        count = dim.exclusive? ? end_val - start_val : end_val - start_val + 1
        Selection::Slice.new(start: start_val, count: count)
      end
    end

    private def parse_dim(dim : Symbol) : Selection::Slice?
      nil
    end

    private def parse_dim(dim : Nil) : Selection::Slice?
      nil
    end
  end

  def self.s : SelectionProxy
    SelectionProxy.new
  end

  def self.all : Symbol
    :all
  end

  def self.unlimited : UInt64
    UInt64::MAX
  end
end
