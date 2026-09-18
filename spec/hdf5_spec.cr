require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

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
end
