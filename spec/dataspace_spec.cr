require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe "Dataspace" do
    it "creates scalar dataspace" do
      sp = HDF5::Dataspace.scalar
      sp.type.should eq(LibHDF5::SpaceClass::Scalar)
      sp.close
    end

    it "creates a Null dataspace" do
      sp = HDF5::Dataspace.null
      sp.type.should eq(LibHDF5::SpaceClass::Null)
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
end
