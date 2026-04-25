require "./spec_helper"

TMP_FILE = File.join(Dir.tempdir, "hdf5_spec_#{Process.pid}.h5")

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
  end

  describe ".lib_version" do
    it "returns the HDF5 library version string" do
      ver = HDF5.lib_version
      ver.should match(/^\d+\.\d+\.\d+$/)
    end
  end

  describe "File" do
    it "creates a new file in write mode" do
      HDF5::File.open(TMP_FILE, :w) { }
      File.exists?(TMP_FILE).should be_true
    end

    it "opens an existing file for reading" do
      HDF5::File.open(TMP_FILE, :w) { }
      HDF5::File.open(TMP_FILE, :r) { |file| file.id.should_not eq(LibHDF5::H5_INVALID_HID) }
    end

    it "raises on missing file in read mode" do
      expect_raises(HDF5::Error) do
        HDF5::File.open("/nonexistent_path/missing.h5", :r) { }
      end
    end

    it "reports accessible?" do
      HDF5::File.open(TMP_FILE, :w) { }
      HDF5::File.accessible?(TMP_FILE).should be_true
      HDF5::File.accessible?("/no/such/file.h5").should be_false
    end
  end

  describe "Group" do
    it "creates and opens a group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        g = file.create_group("mygroup")
        g.close

        g2 = file.open_group("mygroup")
        g2.close
      end
    end

    it "creates nested groups via create_group with path" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        g = file.create_group("a/b/c")
        g.close

        file.link_exists?("a").should be_true
        file.link_exists?("a/b").should be_true
        file.link_exists?("a/b/c").should be_true
      end
    end

    it "lists group keys" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("alpha").close
        file.create_group("beta").close
        file.create_group("gamma").close

        keys = file.keys
        keys.sort.should eq(["alpha", "beta", "gamma"])
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

    it "checks link_exists?" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.link_exists?("absent").should be_false
        file.create_group("present").close
        file.link_exists?("present").should be_true
      end
    end

    it "deletes a link" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.create_group("removeme").close
        file.link_exists?("removeme").should be_true
        file.delete_link("removeme")
        file.link_exists?("removeme").should be_false
      end
    end
  end

  describe "Dataset - numeric" do
    it "writes and reads Int32 array" do
      data = [1, 2, 3, 4, 5]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_dataset("ints", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        result = file.read_dataset("ints", Int32)
        result.should eq(data)
      end
    end

    it "writes and reads Float64 array" do
      data = [1.1, 2.2, 3.3, 4.4]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_dataset("floats", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        result = file.read_dataset("floats", Float64)
        result.size.should eq(4)
        result.each_with_index { |val, idx| val.should be_close(data[idx], 1e-12) }
      end
    end

    it "writes and reads Float32 array" do
      data = [1.0_f32, 2.5_f32, -3.14_f32]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_dataset("f32", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        result = file.read_dataset("f32", Float32)
        result.size.should eq(3)
        result.each_with_index { |val, idx| val.should be_close(data[idx], 1e-6_f32) }
      end
    end

    it "writes and reads Int8 array" do
      data = [-128_i8, 0_i8, 127_i8]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_dataset("i8", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        file.read_dataset("i8", Int8).should eq(data)
      end
    end

    it "writes and reads UInt64 array" do
      data = [0_u64, UInt64::MAX // 2, UInt64::MAX]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_dataset("u64", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        file.read_dataset("u64", UInt64).should eq(data)
      end
    end

    it "reports dataset dims and npoints" do
      data = Array(Float64).new(12, &.to_f64)
      HDF5::File.open(TMP_FILE, :w) do |file|
        ds = file.create_dataset("mat", Float64, [3_u64, 4_u64])
        ds.write(data)
        ds.dims.should eq([3_u64, 4_u64])
        ds.ndims.should eq(2)
        ds.npoints.should eq(12)
        ds.close
      end
    end

    it "raises on opening nonexistent dataset" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        expect_raises(HDF5::Error) do
          file.open_dataset("ghost")
        end
      end
    end
  end

  describe "Dataset - strings" do
    it "writes and reads variable-length string array" do
      data = ["hello", "world", "HDF5"]
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.write_string_dataset("strs", data)
      end
      HDF5::File.open(TMP_FILE, :r) do |file|
        result = file.read_string_dataset("strs")
        result.should eq(data)
      end
    end
  end

  describe "Attributes on groups" do
    it "sets and gets Int32 attribute on file root" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.set_attribute("answer", 42_i32)
        file.get_attribute("answer", Int32).should eq(42)
      end
    end

    it "sets and gets Float64 attribute" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.set_attribute("pi", 3.14159_f64)
        file.get_attribute("pi", Float64).should be_close(3.14159, 1e-12)
      end
    end

    it "sets and gets String attribute" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.set_attribute("title", "My Dataset")
        file.get_attribute("title", String).should eq("My Dataset")
      end
    end

    it "checks has_attribute?" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        file.has_attribute?("nope").should be_false
        file.set_attribute("yes", 1_i32)
        file.has_attribute?("yes").should be_true
      end
    end

    it "sets attribute on a group" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        group = file.create_group("grp")
        group.set_attribute("version", 2_i32)
        group.get_attribute("version", Int32).should eq(2)
        group.close
      end
    end
  end

  describe "Dataspace" do
    it "creates scalar dataspace" do
      sp = HDF5::Dataspace.scalar
      sp.type.should eq(LibHDF5::SpaceClass::Scalar)
      sp.close
    end

    it "creates simple 1D dataspace" do
      sp = HDF5::Dataspace.simple([10_u64])
      sp.ndims.should eq(1)
      sp.dims.should eq([10_u64])
      sp.npoints.should eq(10)
      sp.close
    end

    it "creates simple 2D dataspace" do
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

  describe "round-trip with nested groups and datasets" do
    it "writes and reads nested structure" do
      HDF5::File.open(TMP_FILE, :w) do |file|
        group = file.create_group("sensors")
        group.write_dataset("temperature", [20.0_f64, 21.5_f64, 19.8_f64])
        group.write_dataset("humidity", [55_i32, 60_i32, 58_i32])
        group.set_attribute("units", "SI")
        group.close
      end

      HDF5::File.open(TMP_FILE, :r) do |file|
        group = file.open_group("sensors")
        temps = group.read_dataset("temperature", Float64)
        temps.size.should eq(3)
        temps[0].should be_close(20.0, 1e-12)
        humids = group.read_dataset("humidity", Int32)
        humids.should eq([55, 60, 58])
        group.get_attribute("units", String).should eq("SI")
        group.close
      end
    end
  end
end
