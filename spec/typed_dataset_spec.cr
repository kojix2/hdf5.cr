require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe "TypedDataset" do
    it "create_dataset with shape: returns TypedDataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("mat", Float64, shape: {3, 4})
        ds.should be_a(HDF5::TypedDataset(Float64))
        ds.shape.should eq([3_u64, 4_u64])
        ds.rank.should eq(2)
        ds.size.should eq(12)
        ds.close
      end
    end

    it "dataset(path, T) opens as TypedDataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["vals"] = [1.0, 2.0, 3.0]
      end
      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("vals", Float64)
        ds.should be_a(HDF5::TypedDataset(Float64))
        ds.read.should eq([1.0, 2.0, 3.0])
        ds.close
      end
    end

    it "dataset(path, T) supports block form" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["nums"] = [10, 20, 30]
      end
      HDF5.open(TMP_FILE, :r) do |file|
        result = nil
        file.dataset("nums", Int32) { |dataset| result = dataset.read }
        result.should eq([10, 20, 30])
      end
    end

    it "create_dataset with data infers type" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("v", [10_i32, 20_i32, 30_i32])
        ds.should be_a(HDF5::TypedDataset(Int32))
        ds.close
      end
    end

    it "create_dataset supports block form with shape:" do
      HDF5.open(TMP_FILE, :w) do |file|
        data = Array(Float64).new(12, &.to_f64)
        file.create_dataset("mat", Float64, shape: {3, 4}) do |dataset|
          dataset.write(data)
          dataset.attrs["desc"] = "test matrix"
        end
      end
      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("mat", Float64)
        ds.shape.should eq([3_u64, 4_u64])
        ds.attrs.get("desc", String).should eq("test matrix")
        ds.close
      end
    end

    it "shape/rank/size are consistent" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("cube", Float32, shape: {2, 3, 4})
        ds.shape.should eq([2_u64, 3_u64, 4_u64])
        ds.rank.should eq(3)
        ds.size.should eq(24)
        ds.close
      end
    end
  end

  # ── TypedDataset – strings ────────────────────────────────────────────────

  describe "TypedDataset - strings" do
    it "writes and reads variable-length string array" do
      data = ["hello", "world", "HDF5"]
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset("strs", data).close
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("strs", String).read.should eq(data)
      end
    end

    it "[]= and dataset() roundtrip for strings" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["genes"] = ["TP53", "CTNNB1", "TERT"]
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("genes", String).read.should eq(["TP53", "CTNNB1", "TERT"])
      end
    end

    it "supports explicit encoding for string datasets" do
      data = ["こんにちは", "世界"]
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset("utf8_names", data, encoding: :utf8).close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("utf8_names", String)
        ds.read.should eq(data)
        dtype = ds.datatype
        dtype.string_encoding.should eq(HDF5::StringEncoding::Utf8)
        dtype.string_padding.should eq(HDF5::StringPadding::NullTerm)
        dtype.close
      end
    end

    it "supports fixed-length string datasets via StringType" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset(
          "fixed_codes",
          String,
          shape: {2},
          string_type: HDF5::StringType.fixed(8, encoding: :ascii)
        )
        ds.write(["ABC", "XYZ"])
        ds.close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("fixed_codes").datatype
        dtype.fixed_length_string?.should be_true
        dtype.size.should eq(8)
        dtype.string_encoding.should eq(HDF5::StringEncoding::Ascii)
        dtype.string_padding.should eq(HDF5::StringPadding::NullPad)
        dtype.close
      end
    end
  end

  # ── TypedDataset – variable-length numeric arrays ────────────────────────

  describe "TypedDataset - variable-length numeric arrays" do
    it "writes and reads Int32 ragged arrays" do
      data = [[1_i32, 2_i32, 3_i32], [] of Int32, [4_i32]]
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset("ragged", data).close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("ragged", Array(Int32))
        ds.read.should eq(data)

        dtype = ds.datatype
        dtype.vlen?.should be_true
        base = dtype.base_type
        base.should_not be_nil
        if base
          base.integer?.should be_true
          base.size.should eq(sizeof(Int32))
        end
        dtype.close
        ds.close
      end
    end

    it "supports explicit shape and selection I/O" do
      HDF5.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("ragged", Array(Float64), shape: {4})
        ds.write([[1.5_f64], [2.0_f64, 3.0_f64], [] of Float64, [4.25_f64]])
        ds.write([[9.0_f64, 10.0_f64], [11.0_f64]], HDF5.s[1...3])
        ds.close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("ragged", Array(Float64))
        ds.read.should eq([[1.5_f64], [9.0_f64, 10.0_f64], [11.0_f64], [4.25_f64]])
        ds[HDF5.s[1...3]].should eq([[9.0_f64, 10.0_f64], [11.0_f64]])
        ds.close
      end
    end
  end
end
