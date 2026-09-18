require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

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

    it "writes and reads variable-length numeric array attributes" do
      data = [[1_i32, 2_i32], [] of Int32, [3_i32, 4_i32, 5_i32]]
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["ragged"] = data
      end

      HDF5.open(TMP_FILE, :r) do |file|
        attr = file.attrs["ragged"]
        attr.array?.should be_true
        attr.shape.should eq([3_u64])
        attr.read_array(Array(Int32)).should eq(data)

        dtype = attr.datatype
        dtype.vlen?.should be_true
        base = dtype.base_type
        base.should_not be_nil
        if base
          base.integer?.should be_true
          base.size.should eq(sizeof(Int32))
        end
        dtype.close
        attr.close
      end
    end
  end
end
