require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

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
end
