require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

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
          SpecSupport.create_raw_dataset(file, "fixed_str", type_id)
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
          SpecSupport.create_raw_dataset(file, "compound", type_id)
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
          SpecSupport.create_raw_dataset(file, "array_type", type_id)
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
          SpecSupport.create_raw_dataset(file, "vlen_ints", type_id)
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
end
