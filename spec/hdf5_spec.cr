require "./spec_helper"

TMP_FILE = File.join(Dir.tempdir, "hdf5_spec_#{Process.pid}.h5")
EXT_FILE = File.join(Dir.tempdir, "hdf5_ext_spec_#{Process.pid}.h5")

private def create_raw_dataset(file : HDF5::File, name : String, type_id : LibHDF5::Hid,
                               dims : Array(UInt64) = [1_u64]) : Nil
  space_id = LibHDF5.H5Screate_simple(dims.size, dims.to_unsafe, nil)
  raise "Failed to create dataspace for #{name}" if space_id == LibHDF5::H5_INVALID_HID

  dataset_id = LibHDF5.H5Dcreate2(file.id, name, type_id, space_id,
    LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT, LibHDF5::H5P_DEFAULT)
  raise "Failed to create dataset #{name}" if dataset_id == LibHDF5::H5_INVALID_HID
ensure
  LibHDF5.H5Dclose(dataset_id) if dataset_id && dataset_id != LibHDF5::H5_INVALID_HID
  LibHDF5.H5Sclose(space_id) if space_id && space_id != LibHDF5::H5_INVALID_HID
end

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  # ── Top-level module API ───────────────────────────────────────────────────

  describe ".lib_version" do
    it "returns the HDF5 library version string" do
      HDF5.lib_version.should match(/^\d+\.\d+\.\d+$/)
    end
  end

  describe ".open" do
    it "creates a file via HDF5.open block form" do
      HDF5.open(TMP_FILE, :w) { }
      File.exists?(TMP_FILE).should be_true
    end

    it "returns a File object in non-block form" do
      HDF5.open(TMP_FILE, :w).close
      file = HDF5.open(TMP_FILE, :r)
      file.id.should_not eq(LibHDF5::H5_INVALID_HID)
      file.close
    end
  end

  describe ".accessible?" do
    it "returns true for a valid HDF5 file" do
      HDF5.open(TMP_FILE, :w) { }
      HDF5.accessible?(TMP_FILE).should be_true
    end

    it "returns false for a missing file" do
      HDF5.accessible?("/no/such/file.h5").should be_false
    end
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
  end

  # ── File ──────────────────────────────────────────────────────────────────

  describe "File" do
    it "creates a new file in write mode" do
      HDF5::File.open(TMP_FILE, :w) { }
      File.exists?(TMP_FILE).should be_true
    end

    it "opens an existing file for reading" do
      HDF5::File.open(TMP_FILE, :w) { }
      HDF5::File.open(TMP_FILE, :r) { |file| file.id.should_not eq(LibHDF5::H5_INVALID_HID) }
    end

    it "raises FileError on missing file in read mode" do
      expect_raises(HDF5::FileError) do
        HDF5::File.open("/nonexistent_path/missing.h5", :r) { }
      end
    end

    it "reports accessible?" do
      HDF5::File.open(TMP_FILE, :w) { }
      HDF5::File.accessible?(TMP_FILE).should be_true
      HDF5::File.accessible?("/no/such/file.h5").should be_false
    end
  end

  # ── Group ─────────────────────────────────────────────────────────────────

  describe "Group" do
    it "creates and opens a group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("mygroup").close
        file.open_group("mygroup").close
      end
    end

    it "create_group raises AlreadyExistsError if group exists" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("dup").close
        expect_raises(HDF5::AlreadyExistsError) do
          file.create_group("dup")
        end
      end
    end

    it "open_group raises ObjectNotFoundError if missing" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        expect_raises(HDF5::ObjectNotFoundError) do
          file.open_group("ghost")
        end
      end
    end

    it "create_group supports block form" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("grp") do |grp|
          grp.attrs["x"] = 1_i32
        end
        file.exists?("grp").should be_true
      end
    end

    it "open_group supports block form" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("grp").close
        accessed = false
        file.open_group("grp") { accessed = true }
        accessed.should be_true
      end
    end

    it "open_object supports block form and closes handle" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("grp").close
        captured_id = LibHDF5::H5_INVALID_HID

        file.open_object("grp") do |obj|
          captured_id = obj.id
          obj.id.should_not eq(LibHDF5::H5_INVALID_HID)
        end

        captured_id.should_not eq(LibHDF5::H5_INVALID_HID)
      end
    end

    it "require_group opens existing group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("existing").close
        file.require_group("existing").close
        file.nlinks.should eq(1)
      end
    end

    it "require_group creates missing group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.require_group("new_group").close
        file.exists?("new_group").should be_true
      end
    end

    it "require_group supports block form" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.require_group("samples/S1") do |grp|
          grp["values"] = [1.0, 2.0, 3.0]
        end
        file.exists?("samples/S1").should be_true
      end
    end

    it "creates nested groups via create_group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("a/b/c").close
        file.exists?("a").should be_true
        file.exists?("a/b").should be_true
        file.exists?("a/b/c").should be_true
      end
    end

    it "lists group keys" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("alpha").close
        file.create_group("beta").close
        file.create_group("gamma").close
        file.keys.sort!.should eq(["alpha", "beta", "gamma"])
      end
    end

    it "iterates keys with each" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("one").close
        file.create_group("two").close
        found = [] of String
        file.each { |k| found << k }
        found.sort.should eq(["one", "two"])
      end
    end

    it "returns nlinks" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.nlinks.should eq(0)
        file.create_group("g1").close
        file.create_group("g2").close
        file.nlinks.should eq(2)
      end
    end

    it "checks exists?" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.exists?("absent").should be_false
        file.create_group("present").close
        file.exists?("present").should be_true
      end
    end

    it "reports object types" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("grp").close
        file["nums"] = [1, 2, 3]

        file.object_type("grp").should eq(:group)
        file.object_type("nums").should eq(:dataset)
      end
    end

    it "deletes a link" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("removeme").close
        file.delete("removeme")
        file.exists?("removeme").should be_false
      end
    end

    it "creates a hard link" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("trees").close
        file["trees/tree_0"] = [1, 2, 3]
        file.link("trees/tree_0", "trace/chains/chain_0/trees/tree_0")

        file.exists?("trace/chains/chain_0/trees/tree_0").should be_true
        file.object_type("trace/chains/chain_0/trees/tree_0").should eq(:dataset)
        file.dataset("trace/chains/chain_0/trees/tree_0", Int32).read.should eq([1, 2, 3])
      end
    end

    it "creates a soft link" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("trees").close
        file["trees/tree_0"] = [1, 2, 3]
        file.soft_link("/trees/tree_0", "/some/path")

        file.exists?("/some/path").should be_true
        file.object_type("/some/path").should eq(:dataset)
        file.dataset("/some/path", Int32).read.should eq([1, 2, 3])
      end
    end

    it "creates an external link" do
      HDF5::File.open(EXT_FILE, :w) do |external|
        external["target"] = [7, 8, 9]
      end

      HDF5::File.open(TMP_FILE, :w) do |file|
        file.external_link(EXT_FILE, "/target", "/external/target")

        file.exists?("/external/target").should be_true
        file.object_type("/external/target").should eq(:dataset)
        file.dataset("/external/target", Int32).read.should eq([7, 8, 9])
      end
    end

    it "[] returns a Group for a group path" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("grp").close
        obj = file["grp"]
        obj.should be_a(HDF5::Group)
        obj.as(HDF5::Group).close
      end
    end

    it "[] returns a Dataset for a dataset path" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file["nums"] = [1, 2, 3]
        obj = file["nums"]
        obj.should be_a(HDF5::Dataset)
        obj.as(HDF5::Dataset).close
      end
    end

    it "[] raises ObjectNotFoundError for missing path" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        expect_raises(HDF5::ObjectNotFoundError) do
          file["no_such_thing"]
        end
      end
    end

    it "[]= creates a dataset from array" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file["values"] = [10, 20, 30]
        file.exists?("values").should be_true
      end
    end

    it "[]= replaces an existing dataset" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file["values"] = [1, 2, 3]
        file["values"] = [4, 5, 6]
        result = file.dataset("values", Int32).read
        result.should eq([4, 5, 6])
      end
    end
  end

  # ── Attributes proxy ──────────────────────────────────────────────────────

  describe "Attributes" do
    it "sets and gets a numeric attribute via attrs[]=" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["answer"] = 42_i32
        file.attrs.get("answer", Int32).should eq(42)
      end
    end

    it "sets and gets a Float64 attribute" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["pi"] = 3.14159_f64
        file.attrs.get("pi", Float64).should be_close(3.14159, 1e-12)
      end
    end

    it "sets and gets a String attribute" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["title"] = "experiment"
        file.attrs.get("title", String).should eq("experiment")
      end
    end

    it "get? returns nil for missing attribute" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs.get?("missing", Int32).should be_nil
      end
    end

    it "get? returns value for existing attribute" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["n"] = 7_i32
        file.attrs.get?("n", Int32).should eq(7)
      end
    end

    it "has_key? works" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs.has_key?("nope").should be_false
        file.attrs["yes"] = 1_i32
        file.attrs.has_key?("yes").should be_true
      end
    end

    it "lists attribute keys" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["a"] = 1_i32
        file.attrs["b"] = 2_i32
        file.attrs["c"] = 3_i32
        file.attrs.keys.sort!.should eq(["a", "b", "c"])
      end
    end

    it "deletes an attribute" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["temp"] = 99_i32
        file.attrs.delete("temp")
        file.attrs.has_key?("temp").should be_false
      end
    end

    it "iterates with each" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["x"] = 1_i32
        file.attrs["y"] = 2_i32
        names = [] of String
        file.attrs.each { |name, _attr| names << name }
        names.sort.should eq(["x", "y"])
      end
    end

    it "overwrites an existing attribute via []=" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["v"] = 1_i32
        file.attrs["v"] = 2_i32
        file.attrs.get("v", Int32).should eq(2)
      end
    end

    it "sets attribute on a group" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_group("grp") do |group|
          group.attrs["version"] = 2_i32
          group.attrs.get("version", Int32).should eq(2)
        end
      end
    end

    it "sets attribute on a dataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset("ds", Int32, shape: {4}) do |dataset|
          dataset.attrs["unit"] = "count"
          dataset.attrs.get("unit", String).should eq("count")
        end
      end
    end

    it "opens an attribute via attrs[]" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["title"] = "experiment"
        attr = file.attrs["title"]
        attr.name.should eq("title")
        attr.read(String).should eq("experiment")
        attr.close
      end
    end

    it "exposes scalar attribute datatype and shape" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["answer"] = 42_i32
        attr = file.attrs["answer"]
        attr.scalar?.should be_true
        attr.array?.should be_false
        attr.shape.should eq([] of UInt64)
        attr.rank.should eq(0)
        attr.size.should eq(1_u64)

        dtype = attr.datatype
        dtype.integer?.should be_true
        dtype.size.should eq(sizeof(Int32))
        dtype.close
        attr.close
      end
    end

    it "exposes array attribute datatype and shape" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["values"] = [1_i32, 2_i32, 3_i32]
        attr = file.attrs["values"]
        attr.scalar?.should be_false
        attr.array?.should be_true
        attr.shape.should eq([3_u64])
        attr.rank.should eq(1)
        attr.size.should eq(3_u64)

        dtype = attr.datatype
        dtype.integer?.should be_true
        dtype.size.should eq(sizeof(Int32))
        dtype.close
        attr.close
      end
    end

    it "supports raw attribute read and write" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["answer"] = 42_i32
        attr = file.attrs["answer"]
        type_id = HDF5::NativeType.for(Int32)

        value = uninitialized Int32
        attr.read_raw(type_id, pointerof(value))
        value.should eq(42)

        updated = 99_i32
        attr.write_raw(type_id, pointerof(updated))
        attr.read(Int32).should eq(99)
        attr.close
      end
    end
  end

  # ── Dataset – numeric ──────────────────────────────────────────────────────

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

  # ── TypedDataset ──────────────────────────────────────────────────────────

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

  # ── Object references ─────────────────────────────────────────────────────

  describe "Reference" do
    it "writes and reads object references in a dataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_group("targets").close
        file.create_dataset("targets/values", [1_i32, 2_i32, 3_i32]).close

        group_ref = file.reference("/targets")
        dataset_ref = file.reference("/targets/values")
        ds = file.create_dataset("refs", [group_ref, dataset_ref])
        dtype = ds.datatype
        dtype.reference?.should be_true
        dtype.object_reference?.should be_true
        dtype.close
        ds.close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        refs = file.dataset("refs", HDF5::Reference).read
        refs.map(&.target_path).should eq(["/targets", "/targets/values"])
        refs[0].target_type.should eq(:group)
        refs[1].target_type.should eq(:dataset)

        obj = refs[1].open
        obj.should be_a(HDF5::Dataset)
        obj.as(HDF5::Dataset).read(Int32).should eq([1, 2, 3])
        obj.close
      end
    end

    it "supports selection I/O for reference datasets" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_group("a").close
        file.create_group("b").close
        file.create_group("c").close

        ds = file.create_dataset("refs", HDF5::Reference, shape: {3})
        ds.write([file.reference("/a"), file.reference("/b"), file.reference("/c")])
        ds.write([file.reference("/c")], HDF5.s[1...2])
        ds.close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        ds = file.dataset("refs", HDF5::Reference)
        ds[HDF5.s[1...3]].map(&.target_path).should eq(["/c", "/c"])
        ds.close
      end
    end

    it "writes and reads object references in attributes" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_group("sample").close
        file.attrs["sample_ref"] = file.reference("/sample")
      end

      HDF5.open(TMP_FILE, :r) do |file|
        ref = file.attrs.get("sample_ref", HDF5::Reference)
        ref.target_path.should eq("/sample")
        ref.target_type.should eq(:group)
        obj = ref.open
        obj.should be_a(HDF5::Group)
        obj.close
      end
    end

    it "raises when creating a reference to a missing object" do
      HDF5.open(TMP_FILE, :w) do |file|
        expect_raises(HDF5::Error) do
          file.reference("/missing")
        end
      end
    end
  end

  # ── Datatype introspection ───────────────────────────────────────────────

  describe "Datatype introspection" do
    it "reports integer dataset metadata" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["ints"] = [1_i32, 2_i32, 3_i32]
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("ints").datatype
        dtype.type_class.should eq(LibHDF5::TypeClass::Integer)
        dtype.size.should eq(sizeof(Int32))
        dtype.integer?.should be_true
        dtype.signed?.should be_true
        dtype.unsigned?.should be_false
        dtype.float?.should be_false
        dtype.string?.should be_false
        dtype.variable_length_string?.should be_false
        dtype.reference?.should be_false
        dtype.vlen?.should be_false
        dtype.compound?.should be_false
        dtype.array?.should be_false
        dtype.close
      end
    end

    it "reports unsigned integer dataset metadata" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["uints"] = [1_u16, 2_u16, 3_u16]
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("uints").datatype
        dtype.type_class.should eq(LibHDF5::TypeClass::Integer)
        dtype.size.should eq(sizeof(UInt16))
        dtype.integer?.should be_true
        dtype.signed?.should be_false
        dtype.unsigned?.should be_true
        dtype.close
      end
    end

    it "reports float dataset metadata through TypedDataset" do
      HDF5.open(TMP_FILE, :w) do |file|
        file["floats"] = [1.5_f64, 2.5_f64, 3.5_f64]
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.dataset("floats", Float64).datatype
        dtype.type_class.should eq(LibHDF5::TypeClass::Float)
        dtype.size.should eq(sizeof(Float64))
        dtype.integer?.should be_false
        dtype.float?.should be_true
        dtype.string?.should be_false
        dtype.variable_length_string?.should be_false
        dtype.close
      end
    end

    it "reports variable-length string metadata" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset("strs", ["alpha", "beta"]).close
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.dataset("strs", String).datatype
        dtype.type_class.should eq(LibHDF5::TypeClass::String)
        dtype.string?.should be_true
        dtype.fixed_length_string?.should be_false
        dtype.variable_length_string?.should be_true
        dtype.string_encoding.should eq(HDF5::StringEncoding::Utf8)
        dtype.string_padding.should eq(HDF5::StringPadding::NullTerm)
        dtype.integer?.should be_false
        dtype.float?.should be_false
        dtype.reference?.should be_false
        dtype.vlen?.should be_false
        dtype.compound?.should be_false
        dtype.array?.should be_false
        dtype.close
      end
    end

    it "reports fixed-length string metadata" do
      HDF5.open(TMP_FILE, :w) do |file|
        type_id = HDF5::NativeType.fixed_length_string(12)
        begin
          create_raw_dataset(file, "fixed_str", type_id)
        ensure
          LibHDF5.H5Tclose(type_id)
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("fixed_str").datatype
        dtype.type_class.should eq(LibHDF5::TypeClass::String)
        dtype.size.should eq(12)
        dtype.string?.should be_true
        dtype.fixed_length_string?.should be_true
        dtype.variable_length_string?.should be_false
        dtype.string_encoding.should eq(HDF5::StringEncoding::Utf8)
        dtype.string_padding.should eq(HDF5::StringPadding::NullPad)
        dtype.close
      end
    end

    it "reports compound members" do
      HDF5.open(TMP_FILE, :w) do |file|
        type_id = LibHDF5.H5Tcreate(LibHDF5::TypeClass::Compound, LibC::SizeT.new(12))
        raise "Failed to create compound datatype" if type_id == LibHDF5::H5_INVALID_HID
        begin
          LibHDF5.H5Tinsert(type_id, "id", LibC::SizeT.new(0), LibHDF5.h5t_native_int32_g).should eq(0)
          LibHDF5.H5Tinsert(type_id, "score", LibC::SizeT.new(4), LibHDF5.h5t_native_double_g).should eq(0)
          create_raw_dataset(file, "compound", type_id)
        ensure
          LibHDF5.H5Tclose(type_id)
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("compound").datatype
        dtype.compound?.should be_true
        dtype.member_count.should eq(2)

        members = dtype.members
        members.map(&.name).should eq(["id", "score"])
        members.map(&.offset).should eq([0_u64, 4_u64])
        members[0].datatype.integer?.should be_true
        members[0].datatype.size.should eq(sizeof(Int32))
        members[1].datatype.float?.should be_true
        members[1].datatype.size.should eq(sizeof(Float64))

        dtype.close
        members.each { |member| member.datatype.id.should eq(LibHDF5::H5_INVALID_HID) }
      end
    end

    it "reports array datatype dimensions and base type" do
      HDF5.open(TMP_FILE, :w) do |file|
        dims = [2_u64, 3_u64]
        type_id = LibHDF5.H5Tarray_create2(LibHDF5.h5t_native_int16_g, dims.size.to_u32, dims.to_unsafe)
        raise "Failed to create array datatype" if type_id == LibHDF5::H5_INVALID_HID
        begin
          create_raw_dataset(file, "array_type", type_id)
        ensure
          LibHDF5.H5Tclose(type_id)
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("array_type").datatype
        dtype.array?.should be_true
        dtype.array_rank.should eq(2)
        dtype.array_dims.should eq([2_u64, 3_u64])

        base_type = dtype.base_type
        base_type.should_not be_nil
        if base_type
          base_type.integer?.should be_true
          base_type.size.should eq(sizeof(Int16))
        end

        dtype.close
        base_type.try(&.id.should eq(LibHDF5::H5_INVALID_HID))
      end
    end

    it "reports variable-length non-string base type" do
      HDF5.open(TMP_FILE, :w) do |file|
        type_id = LibHDF5.H5Tvlen_create(LibHDF5.h5t_native_int32_g)
        raise "Failed to create vlen datatype" if type_id == LibHDF5::H5_INVALID_HID
        begin
          create_raw_dataset(file, "vlen_ints", type_id)
        ensure
          LibHDF5.H5Tclose(type_id)
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        dtype = file.open_dataset("vlen_ints").datatype
        dtype.vlen?.should be_true
        dtype.string?.should be_false

        base_type = dtype.base_type
        base_type.should_not be_nil
        if base_type
          base_type.integer?.should be_true
          base_type.size.should eq(sizeof(Int32))
        end

        dtype.close
        base_type.try(&.id.should eq(LibHDF5::H5_INVALID_HID))
      end
    end

    it "raises HDF5::Error for invalid datatype handles" do
      dtype = HDF5::Datatype.new(LibHDF5::H5_INVALID_HID)

      expect_raises(HDF5::Error, "Failed to get datatype class") do
        dtype.type_class
      end

      expect_raises(HDF5::Error, "Failed to get datatype size") do
        dtype.size
      end
    end
  end

  # ── Partial I/O with Selection ────────────────────────────────────────────

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

  # ── Compression and chunking ──────────────────────────────────────────────

  describe "Compression" do
    it "creates a gzip-compressed chunked dataset" do
      data = Array(Float64).new(100, &.to_f64)
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset(
          "compressed",
          Float64,
          shape: {100},
          chunk: {20},
          compression: :gzip,
          compression_level: 4
        ) do |dataset|
          dataset.write(data)
        end
      end
      HDF5.open(TMP_FILE, :r) do |file|
        result = file.dataset("compressed", Float64).read
        result.size.should eq(100)
        result[50].should be_close(50.0, 1e-12)
      end
    end

    it "accepts HDF5::Compression.gzip object" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset(
          "ds",
          Int32,
          shape: {50},
          chunk: {10},
          compression: HDF5::Compression.gzip(level: 3)
        ) do |dataset|
          dataset.write(Array(Int32).new(50) { |idx| idx })
        end
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("ds", Int32).read[25].should eq(25)
      end
    end
  end

  # ── Resizable dataset ─────────────────────────────────────────────────────

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

  # ── Dataspace ─────────────────────────────────────────────────────────────

  describe "Dataspace" do
    it "creates scalar dataspace" do
      sp = HDF5::Dataspace.scalar
      sp.type.should eq(LibHDF5::SpaceClass::Scalar)
      sp.close
    end

    it "creates 1D simple dataspace" do
      sp = HDF5::Dataspace.simple([10_u64])
      sp.ndims.should eq(1)
      sp.dims.should eq([10_u64])
      sp.npoints.should eq(10)
      sp.close
    end

    it "creates 2D simple dataspace" do
      sp = HDF5::Dataspace.simple([3_u64, 4_u64])
      sp.ndims.should eq(2)
      sp.dims.should eq([3_u64, 4_u64])
      sp.npoints.should eq(12)
      sp.close
    end

    it "creates simple dataspace with varargs" do
      sp = HDF5::Dataspace.simple(5, 6)
      sp.dims.should eq([5_u64, 6_u64])
      sp.close
    end
  end

  # ── Complex round-trip ────────────────────────────────────────────────────

  describe "round-trip with nested groups and datasets" do
    it "writes and reads nested structure" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["title"] = "RNA-seq"

        file.require_group("samples/S1") do |sample|
          sample["genes"] = ["TP53", "CTNNB1", "TERT"]
          sample["vaf"] = [0.42, 0.31, 0.18]
          sample.attrs["units"] = "SI"
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        file.attrs.get("title", String).should eq("RNA-seq")

        genes = file.dataset("samples/S1/genes", String).read
        genes.should eq(["TP53", "CTNNB1", "TERT"])

        vaf = file.dataset("samples/S1/vaf", Float64).read
        vaf[0].should be_close(0.42, 1e-12)

        file.open_group("samples/S1") do |sample|
          sample.attrs.get("units", String).should eq("SI")
        end
      end
    end
  end
end
