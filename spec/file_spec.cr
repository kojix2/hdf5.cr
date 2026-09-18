require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
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
end
