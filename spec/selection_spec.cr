require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe ".s selection builder" do
    it "builds a 1D range selection" do
      sel = HDF5.s[0...10]
      sel.slices.size.should eq(1)
      slice = sel.slices[0]
      slice.should_not be_nil
      if slice
        slice.start.should eq(0)
        slice.count.should eq(10)
      end
    end

    it "builds a 2D range selection" do
      sel = HDF5.s[0...5, 0...8]
      sel.slices.size.should eq(2)
      slice0 = sel.slices[0]
      slice1 = sel.slices[1]
      slice0.should_not be_nil
      slice1.should_not be_nil
      if slice0 && slice1
        slice0.count.should eq(5)
        slice1.count.should eq(8)
      end
    end

    it "treats HDF5.all as full-axis (nil slice)" do
      sel = HDF5.s[HDF5.all, 0...4]
      sel.slices[0].should be_nil
      sel.slices[1].should_not be_nil
    end
  end

  describe "Selection.hyperslab" do
    it "builds from start/count" do
      sel = HDF5::Selection.hyperslab(start: [0, 0], count: [3, 4])
      slice = sel.slices[0]
      slice.should_not be_nil
      if slice
        slice.start.should eq(0)
        slice.count.should eq(3)
      end
    end

    it "tiles logical regions within the requested element budget" do
      HDF5::Selection.block_shape([3_u64, 4_u64], 5).should eq([1_u64, 4_u64])

      regions = [] of Array(UInt64)
      HDF5::Selection.each_region([3_u64, 4_u64], [2_u64, 3_u64]) do |region|
        regions << region.result_shape([3_u64, 4_u64])
      end

      regions.should eq([[2_u64, 3_u64], [2_u64, 1_u64], [1_u64, 3_u64], [1_u64, 1_u64]])
    end
  end

  describe "Selection partial I/O" do
    it "reads a slice of a 1D dataset" do
      data = Array(Int32).new(10) { |idx| idx * 10 }
      HDF5.open(TMP_FILE, :w) do |file|
        file["seq"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        sel = HDF5.s[2...5]
        result = file.dataset("seq", Int32).read(sel)
        result.should eq([20, 30, 40])
      end
    end

    it "reads a 2D slice of a matrix" do
      data = Array(Float64).new(12, &.to_f64)
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("mat", Float64, shape: {3, 4})
        ds.write(data)
        ds.close
      end
      HDF5.open(TMP_FILE, :r) do |file|
        sel = HDF5.s[1...3, 0...2]
        result = file.dataset("mat", Float64).read(sel)
        result.should eq([4.0, 5.0, 8.0, 9.0])
      end
    end

    it "writes a selection into a dataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("buf", Int32, shape: {6})
        ds.write(Array(Int32).new(6, 0))
        ds.write([99, 88], HDF5.s[2...4])
        ds.close
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("buf", Int32).read.should eq([0, 0, 99, 88, 0, 0])
      end
    end

    it "TypedDataset [] and []= shortcuts" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("v", Int32, shape: {5})
        ds.write([1, 2, 3, 4, 5])
        block = ds[HDF5.s[1...4]]
        block.should eq([2, 3, 4])
        ds[HDF5.s[1...4]] = [20, 30, 40]
        ds.read.should eq([1, 20, 30, 40, 5])
        ds.close
      end
    end

    it "raises ShapeMismatchError when write data size mismatches selection" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("v", Int32, shape: {5})
        ds.write([1, 2, 3, 4, 5])
        expect_raises(HDF5::ShapeMismatchError) do
          ds.write([1, 2, 3], HDF5.s[0...2])
        end
        ds.close
      end
    end
  end
end
