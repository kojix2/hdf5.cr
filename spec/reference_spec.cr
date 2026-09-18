require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

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
end
