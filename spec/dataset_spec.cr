require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe "Dataset - numeric" do
    it "writes and reads Int32 array" do
      data = [1, 2, 3, 4, 5]
      HDF5.open(TMP_FILE, :w) do |file|
        file["ints"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("ints", Int32).read.should eq(data)
      end
    end

    it "writes and reads Float64 array" do
      data = [1.1, 2.2, 3.3, 4.4]
      HDF5.open(TMP_FILE, :w) do |file|
        file["floats"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        result = file.dataset("floats", Float64).read
        result.each_with_index { |val, idx| val.should be_close(data[idx], 1e-12) }
      end
    end

    it "writes and reads Float32 array" do
      data = [1.0_f32, 2.5_f32, -3.14_f32]
      HDF5.open(TMP_FILE, :w) do |file|
        file["f32"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        result = file.dataset("f32", Float32).read
        result.each_with_index { |val, idx| val.should be_close(data[idx], 1e-6_f32) }
      end
    end

    it "writes and reads Int8 array" do
      data = [-128_i8, 0_i8, 127_i8]
      HDF5.open(TMP_FILE, :w) do |file|
        file["i8"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("i8", Int8).read.should eq(data)
      end
    end

    it "writes and reads UInt64 array" do
      data = [0_u64, UInt64::MAX // 2, UInt64::MAX]
      HDF5.open(TMP_FILE, :w) do |file|
        file["u64"] = data
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("u64", UInt64).read.should eq(data)
      end
    end

    it "raises ObjectNotFoundError opening nonexistent dataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        expect_raises(HDF5::ObjectNotFoundError) do
          file.open_dataset("ghost")
        end
      end
    end
  end

  describe "Resizable dataset" do
    it "resizes a chunked dataset and writes to the new region" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset(
          "events",
          Int32,
          shape: {3},
          max_shape: {HDF5.unlimited},
          chunk: {3}
        )
        ds.write([1, 2, 3])
        ds.resize({6})
        ds.write([4, 5, 6], HDF5.s[3...6])
        ds.close
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("events", Int32).read.should eq([1, 2, 3, 4, 5, 6])
      end
    end
  end
end
